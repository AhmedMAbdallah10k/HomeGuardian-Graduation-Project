"""
Home Guardian — Stuck in Room Detection (Nanny + Pet Mode)
==========================================================
3-Signal System:
    Signal 1 — Door closed + subject inside + time threshold exceeded
    Signal 2 — Subject repeatedly approaching door zone (3+ times in 2 mins)
    Signal 3 — Arms raised toward door handle (child only, MediaPipe)

Adult Awareness:
    If an adult is detected in the room → no alert fired

Tracked subjects:
    child  — person with small bbox (size-based heuristic)
    cat    — COCO class 15
    dog    — COCO class 16

Door approach zone:
    Derived from the door model bounding box + fixed pixel padding (80px).
    No hardcoded fractions — the zone follows wherever the door is in frame.

Pipeline:
    Camera feed
        ↓
    YOLO person+pet detection
        ↓
    Door model (open/closed) → dynamic approach zone
        ↓
    3-signal evaluator (Signal 3 skipped for pets)
        ↓
    2+ signals active → ALERT
"""

import cv2
import time
import mediapipe as mp
import numpy as np
from pathlib import Path
from ultralytics import YOLO
from collections import deque

_SCRIPT_DIR = Path(__file__).resolve().parent

# ──────────────────────────────────────────────
# CONFIGURATION
# ──────────────────────────────────────────────
CONFIG = {
    # Time threshold (seconds) — 60 for testing, 300 for production
    "STUCK_TIME_THRESHOLD": 60,

    # How many times subject must approach door zone to trigger Signal 2
    "DOOR_APPROACH_COUNT": 3,

    # Time window (seconds) to count door approaches
    "APPROACH_WINDOW": 120,

    # Person size threshold — bbox height as fraction of frame height
    # Below → child, above → adult
    "ADULT_HEIGHT_FRACTION": 0.55,

    # Minimum confidence for person/pet detection
    "PERSON_CONFIDENCE": 0.50,

    # Minimum confidence for door detection
    "DOOR_CONFIDENCE": 0.45,

    # Padding (pixels at original 640x480 resolution) added around
    # the door bbox to form the approach zone
    "DOOR_ZONE_PAD": 30,

    # Camera source
    "SOURCE": 0,

    # Path to your door state model (resolved next to this script)
    "DOOR_MODEL_PATH": str(_SCRIPT_DIR / "best.pt"),

    # Door classes from your model
    "DOOR_OPEN_CLASSES": ["door_opened"],
    "DOOR_CLOSED_CLASSES": ["door_closed"],

    # Minimum score to fire alert
    "ALERT_SCORE": 2,

    # Which subjects to monitor — remove any you don't want
    # Options: "child", "cat", "dog"
    "MONITOR_SUBJECTS": ["child", "cat", "dog"],
}

# COCO class IDs
PERSON_CLASS_ID = 0
CAT_CLASS_ID    = 15
DOG_CLASS_ID    = 16

# Subject display colors (BGR)
SUBJECT_COLORS = {
    "child": (0, 200, 255),
    "cat":   (255, 100, 255),
    "dog":   (100, 255, 100),
    "adult": (255, 100, 0),
}

# Alert messages per subject type
ALERT_MESSAGES = {
    "child": ("CHILD MAY BE STUCK IN ROOM", "Please check on the child immediately"),
    "cat":   ("CAT MAY BE STUCK IN ROOM",   "Please check on your cat immediately"),
    "dog":   ("DOG MAY BE STUCK IN ROOM",   "Please check on your dog immediately"),
}


# ──────────────────────────────────────────────
# PERSON / PET CLASSIFIER
# ──────────────────────────────────────────────
def classify_detection(box, frame_height, model_names, scale=1):
    cls_id = int(box.cls)
    if cls_id == CAT_CLASS_ID:
        return "cat"
    if cls_id == DOG_CLASS_ID:
        return "dog"
    if cls_id == PERSON_CLASS_ID:
        bbox = box.xyxy[0].tolist()
        # Apply scale so height is in original frame space before comparing
        h = (bbox[3] - bbox[1]) * scale
        ratio = h / frame_height
        return "adult" if ratio >= CONFIG["ADULT_HEIGHT_FRACTION"] else "child"
    return None


# ──────────────────────────────────────────────
# DYNAMIC DOOR ZONE
# ──────────────────────────────────────────────
def compute_door_zone(door_bbox, frame_w, frame_h, pad=None):
    """
    Expand the door bounding box by `pad` pixels on all sides,
    clamped to frame boundaries.
    Returns (x1, y1, x2, y2) or None if door_bbox is None.
    """
    if door_bbox is None:
        return None
    if pad is None:
        pad = CONFIG["DOOR_ZONE_PAD"]
    dx1, dy1, dx2, dy2 = door_bbox
    zx1 = max(0,       int(dx1) - pad)
    zy1 = max(0,       int(dy1))        # no top padding
    zx2 = min(frame_w, int(dx2) + pad)
    zy2 = min(frame_h, int(dy2))        # no bottom padding
    return (zx1, zy1, zx2, zy2)


def is_in_door_zone(subject_bbox, door_zone):
    """
    Check if the subject's center falls inside the door approach zone.
    """
    if door_zone is None:
        return False
    x1, y1, x2, y2 = subject_bbox
    cx = (x1 + x2) / 2
    cy = (y1 + y2) / 2
    zx1, zy1, zx2, zy2 = door_zone
    return zx1 <= cx <= zx2 and zy1 <= cy <= zy2


# ──────────────────────────────────────────────
# SIGNAL TRACKERS
# ──────────────────────────────────────────────
class StuckDetector:
    def __init__(self, subject_type):
        self.subject_type = subject_type

        # Signal 1
        self.in_room_since = None

        # Signal 2
        self.approach_timestamps = deque()
        self.signal2_active = False

        # Signal 3 (child only)
        self.signal3_active = False

    def update_signal1(self, subject_in_room, door_closed):
        now = time.time()
        if subject_in_room and door_closed:
            if self.in_room_since is None:
                self.in_room_since = now
                print(f"[Signal 1] {self.subject_type} in closed room — timer started")
            elapsed = now - self.in_room_since
            return elapsed >= CONFIG["STUCK_TIME_THRESHOLD"], elapsed
        else:
            if self.in_room_since is not None:
                print(f"[Signal 1] {self.subject_type} timer reset")
            self.in_room_since = None
            return False, 0

    def update_signal2(self, subject_in_door_zone):
        now = time.time()
        while (self.approach_timestamps and
               now - self.approach_timestamps[0] > CONFIG["APPROACH_WINDOW"]):
            self.approach_timestamps.popleft()

        if subject_in_door_zone:
            if (not self.approach_timestamps or
                    now - self.approach_timestamps[-1] > 3):
                self.approach_timestamps.append(now)
                print(f"[Signal 2] {self.subject_type} door approach "
                      f"#{len(self.approach_timestamps)}")

        self.signal2_active = (len(self.approach_timestamps) >=
                               CONFIG["DOOR_APPROACH_COUNT"])
        return self.signal2_active, len(self.approach_timestamps)

    def update_signal3(self, arms_raised):
        # Only meaningful for child
        self.signal3_active = arms_raised if self.subject_type == "child" else False
        return self.signal3_active

    def reset_door_open(self):
        if self.in_room_since is not None:
            print(f"[Signal 1] {self.subject_type} timer reset — door open")
        self.in_room_since = None
        self.approach_timestamps.clear()
        self.signal2_active = False


# ──────────────────────────────────────────────
# MEDIAPIPE ARM RAISE DETECTOR
# ──────────────────────────────────────────────
class ArmRaiseDetector:
    def __init__(self):
        self.mp_pose = mp.solutions.pose
        self.pose = self.mp_pose.Pose(
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
        )

    def detect(self, frame):
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = self.pose.process(rgb)
        if not results.pose_landmarks:
            return False
        lm = results.pose_landmarks.landmark
        l_shoulder = lm[self.mp_pose.PoseLandmark.LEFT_SHOULDER]
        r_shoulder = lm[self.mp_pose.PoseLandmark.RIGHT_SHOULDER]
        l_wrist    = lm[self.mp_pose.PoseLandmark.LEFT_WRIST]
        r_wrist    = lm[self.mp_pose.PoseLandmark.RIGHT_WRIST]
        left_raised  = l_wrist.y < l_shoulder.y and l_wrist.visibility > 0.5
        right_raised = r_wrist.y < r_shoulder.y and r_wrist.visibility > 0.5
        return left_raised or right_raised

    def release(self):
        self.pose.close()


# ──────────────────────────────────────────────
# OVERLAY DRAWING
# ──────────────────────────────────────────────
def draw_overlay(frame, detections, door_state, door_zone,
                 active_subject, elapsed, approach_count,
                 signals, alert_active, adult_present):
    h, w = frame.shape[:2]
    THRESHOLD = CONFIG["STUCK_TIME_THRESHOLD"]
    ratio = min(elapsed / THRESHOLD, 1.0) if THRESHOLD > 0 else 0

    # ── Door approach zone ──
    if door_zone is not None:
        zx1, zy1, zx2, zy2 = door_zone
        cv2.rectangle(frame, (zx1, zy1), (zx2, zy2), (255, 165, 0), 2)
        cv2.putText(frame, "Door Zone", (zx1 + 4, zy1 + 18),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 165, 0), 1)

    # ── Subject boxes ──
    for stype, bbox in detections:
        x1, y1, x2, y2 = map(int, bbox)
        color = SUBJECT_COLORS.get(stype, (200, 200, 200))
        cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
        cv2.putText(frame, stype.upper(), (x1, y1 - 6),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 1)

    # ── Info panel ──
    panel_h = 210
    cv2.rectangle(frame, (0, 0), (320, panel_h), (0, 0, 0), -1)
    cv2.rectangle(frame, (0, 0), (320, panel_h), (50, 50, 50), 1)

    def put(text, y, color=(200, 200, 200)):
        cv2.putText(frame, text, (8, y),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.48, color, 1, cv2.LINE_AA)

    mode_label = "Pet Mode" if active_subject in ("cat", "dog") else "Nanny Mode"
    put(f"Home Guardian — {mode_label}", 20)
    put(f"Tracking: {active_subject.upper() if active_subject else 'none'}", 38,
        SUBJECT_COLORS.get(active_subject, (200, 200, 200)) if active_subject else (80, 80, 80))
    put(f"Door: {door_state.upper()}", 56,
        (0, 255, 0) if "open" in door_state else
        (0, 0, 255) if door_state == "closed" else (120, 120, 120))

    if adult_present:
        put("Adult present — monitoring paused", 76, (0, 255, 255))
    elif door_state == "open":
        put("Door open — monitoring paused", 76, (0, 255, 255))
    else:
        put(f"Timer: {elapsed:.0f}s / {THRESHOLD}s", 76,
            (0, 0, 255) if ratio > 0.7 else (200, 200, 200))
        bar_filled = int(298 * ratio)
        cv2.rectangle(frame, (8, 84), (308, 93), (50, 50, 50), -1)
        bar_color = ((0, 255, 0) if ratio < 0.5 else
                     (0, 165, 255) if ratio < 0.8 else (0, 0, 255))
        if bar_filled > 0:
            cv2.rectangle(frame, (8, 84), (8 + bar_filled, 93), bar_color, -1)

    s1, s2, s3 = signals
    put(f"[{'+' if s1 else ' '}] S1: Time threshold", 112,
        (0, 255, 255) if s1 else (80, 80, 80))
    put(f"[{'+' if s2 else ' '}] S2: Door approaches "
        f"({approach_count}/{CONFIG['DOOR_APPROACH_COUNT']})", 130,
        (0, 255, 255) if s2 else (80, 80, 80))
    put(f"[{'+' if s3 else ' '}] S3: Arms raised (child only)", 148,
        (0, 255, 255) if s3 else (80, 80, 80))

    score = sum(signals)
    put(f"Score: {score}/3  —  {'ALERT' if score >= CONFIG['ALERT_SCORE'] else 'OK'}",
        170, (0, 0, 255) if score >= CONFIG["ALERT_SCORE"] else (200, 200, 200))

    # ── Alert banner ──
    if alert_active and not adult_present and active_subject:
        line1, line2 = ALERT_MESSAGES.get(active_subject, ("STUCK IN ROOM", "Please check immediately"))
        overlay = frame.copy()
        cv2.rectangle(overlay, (0, h - 90), (w, h), (0, 0, 180), -1)
        cv2.addWeighted(overlay, 0.65, frame, 0.35, 0, frame)
        cv2.putText(frame, f"!  {line1}",
                    (w // 2 - 210, h - 48),
                    cv2.FONT_HERSHEY_DUPLEX, 0.8, (255, 255, 255), 2, cv2.LINE_AA)
        cv2.putText(frame, line2,
                    (w // 2 - 185, h - 16),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.58, (200, 200, 200), 1, cv2.LINE_AA)


# ──────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────
def run():
    print("[Home Guardian] Stuck in Room Detection starting...")
    print(f"[Config] Monitoring: {CONFIG['MONITOR_SUBJECTS']}")
    print(f"[Config] Alert threshold: {CONFIG['STUCK_TIME_THRESHOLD']}s")
    print("[Info] Press Q to quit")

    print("[Info] Loading person/pet detection model (YOLOv8m)...")
    person_model = YOLO(str(_SCRIPT_DIR / "yolov8m.pt"))

    print("[Info] Loading door state model...")
    door_model = YOLO(CONFIG["DOOR_MODEL_PATH"], task="detect")

    print("[Info] Loading MediaPipe pose...")
    arm_detector = ArmRaiseDetector()

    cap = cv2.VideoCapture(CONFIG["SOURCE"], cv2.CAP_DSHOW)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

    print("[Info] Warming up camera...")
    time.sleep(2)
    for _ in range(30):
        cap.read()

    if not cap.isOpened():
        print(f"[ERROR] Cannot open camera: {CONFIG['SOURCE']}")
        return

    # One detector per subject type
    detectors = {s: StuckDetector(s) for s in CONFIG["MONITOR_SUBJECTS"]}

    door_state  = "unknown"
    door_bbox   = None   # raw door bbox in original frame coords
    door_zone   = None   # padded approach zone
    frame_count = 0

    # Cached values for skipped frames
    s1, s2, s3    = False, False, False
    elapsed       = 0
    approach_count = 0
    detections    = []   # list of (subject_type, bbox)
    alert_active  = False
    adult_detected = False
    active_subject = None  # which subject triggered the alert logic this frame

    while True:
        ret, frame = cap.read()
        if not ret:
            print("[Info] End of stream")
            break

        frame_count += 1

        # ── Skipped frames — redraw with cached values ──
        if frame_count % 3 != 0:
            draw_overlay(frame, detections, door_state, door_zone,
                         active_subject, elapsed, approach_count,
                         (s1, s2, s3), alert_active, adult_detected)
            cv2.imshow("Home Guardian — Stuck in Room", frame)
            if cv2.waitKey(1) & 0xFF == ord('q'):
                break
            continue

        h, w = frame.shape[:2]
        # Person/pet model — 320 inference is fine for classification
        small = cv2.resize(frame, (320, 240))
        scale = 2  # 320→640

        # ────────────────────────────────────────
        # Person + Pet Detection (320 inference)
        # ────────────────────────────────────────
        person_results = person_model(small, verbose=False, imgsz=320)[0]
        detections     = []
        adult_detected = False
        found_subjects = {s: False for s in CONFIG["MONITOR_SUBJECTS"]}
        subject_in_door_zone = {s: False for s in CONFIG["MONITOR_SUBJECTS"]}

        for box in person_results.boxes:
            if float(box.conf) < CONFIG["PERSON_CONFIDENCE"]:
                continue

            stype = classify_detection(box, h, person_model.names, scale=scale)
            if stype is None:
                continue

            # Scale bbox back to original resolution
            bx1, by1, bx2, by2 = box.xyxy[0].tolist()
            bbox = [bx1 * scale, by1 * scale, bx2 * scale, by2 * scale]

            if stype == "adult":
                adult_detected = True
                detections.append(("adult", bbox))
                continue

            if stype not in CONFIG["MONITOR_SUBJECTS"]:
                continue

            found_subjects[stype] = True
            detections.append((stype, bbox))

            if is_in_door_zone(bbox, door_zone):
                subject_in_door_zone[stype] = True

        # ────────────────────────────────────────
        # Door Detection — full frame at 640, iou=0.60
        # Matches the test script that gave accurate bboxes
        # ────────────────────────────────────────
        door_state     = "unknown"
        door_bbox      = None
        best_door_conf = 0.0

        door_results = door_model(
            frame,
            conf=CONFIG["DOOR_CONFIDENCE"],
            iou=0.60,
            imgsz=640,
            verbose=False,
        )[0]
        for box in door_results.boxes:
            conf = float(box.conf)
            if conf >= CONFIG["DOOR_CONFIDENCE"] and conf > best_door_conf:
                cls_name = door_model.names[int(box.cls)]
                if cls_name in CONFIG["DOOR_CLOSED_CLASSES"]:
                    door_state = "closed"
                    best_door_conf = conf
                    bx1, by1, bx2, by2 = box.xyxy[0].tolist()
                    door_bbox = [bx1, by1, bx2, by2]  # already full-res, no scaling
                elif cls_name in CONFIG["DOOR_OPEN_CLASSES"]:
                    door_state = "open"
                    best_door_conf = conf
                    bx1, by1, bx2, by2 = box.xyxy[0].tolist()
                    door_bbox = [bx1, by1, bx2, by2]  # already full-res, no scaling

        # Recompute approach zone from latest door bbox
        door_zone = compute_door_zone(door_bbox, w, h)

        door_closed = door_state == "closed"

        # ────────────────────────────────────────
        # MediaPipe — child only, every 10th processed frame
        # ────────────────────────────────────────
        if frame_count % 10 == 0 and found_subjects.get("child"):
            s3 = arm_detector.detect(frame)
        elif not found_subjects.get("child"):
            s3 = False

        # ────────────────────────────────────────
        # Signal Evaluation — per subject
        # ────────────────────────────────────────
        # Priority: child > dog > cat (first monitored subject found wins display)
        active_subject  = None
        s1, s2          = False, False
        elapsed         = 0
        approach_count  = 0
        alert_active    = False

        if adult_detected:
            # Adult present — reset all detectors
            for det in detectors.values():
                det.reset_door_open()
            s3 = False
        else:
            for stype in CONFIG["MONITOR_SUBJECTS"]:
                det = detectors[stype]

                if door_state == "open":
                    det.reset_door_open()
                    continue

                if not found_subjects[stype]:
                    # Subject left — reset timer but keep approach count
                    if det.in_room_since is not None:
                        det.in_room_since = None
                    continue

                # Subject is present and door is closed/unknown
                _s1, _elapsed = det.update_signal1(True, door_closed)
                _s2, _count   = det.update_signal2(subject_in_door_zone[stype])
                _s3           = det.update_signal3(s3) if stype == "child" else False

                _score = sum([_s1, _s2, _s3])
                if _score >= CONFIG["ALERT_SCORE"]:
                    # This subject triggered an alert — use it for display
                    active_subject = stype
                    s1, s2, elapsed, approach_count = _s1, _s2, _elapsed, _count
                    s3 = _s3
                    alert_active = True
                    print(f"[ALERT] {stype} may be stuck! Score: {_score}/3")
                    break
                elif active_subject is None and found_subjects[stype]:
                    # No alert yet — show this subject's stats in overlay
                    active_subject = stype
                    s1, s2, elapsed, approach_count = _s1, _s2, _elapsed, _count
                    s3 = _s3

        # ────────────────────────────────────────
        # Draw
        # ────────────────────────────────────────
        draw_overlay(frame, detections, door_state, door_zone,
                     active_subject, elapsed, approach_count,
                     (s1, s2, s3), alert_active, adult_detected)

        cv2.imshow("Home Guardian — Stuck in Room", frame)

        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

    cap.release()
    arm_detector.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    run()