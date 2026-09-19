"""
Sleep Monitor
=============
Uses YOLOv8s to detect the bed region and MediaPipe PoseLandmarker
to detect if a person is in the bed. Movement is then tracked
only inside the bed bounding box.

HOW IT WORKS:
  1. YOLOv8s scans the frame and finds the bed (class "bed")
  2. MediaPipe checks if a person is inside that bed region
  3. Once person is in bed, movement is tracked inside the bed box only
  4. Low movement for STILL_THRESHOLD_SECS → Asleep
  5. Large movement for WAKE_CONFIRM_SECS  → Awake
  6. Person leaves bed → session logged, reset

ON FIRST RUN:
  - YOLOv8s model (~22MB) downloads automatically via ultralytics
  - MediaPipe pose model (~5MB) downloads automatically from Google

INSTALL:
  pip install opencv-python ultralytics mediapipe numpy

Dependencies: opencv-python, ultralytics, mediapipe, numpy
"""

import cv2
import numpy as np
import time
import os
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Optional, Tuple

_SCRIPT_DIR = Path(__file__).resolve().parent

# ── Try imports and give clear errors if missing ──────────────────────────────
try:
    from ultralytics import YOLO
except ImportError:
    raise ImportError("Run: pip install ultralytics")

try:
    import mediapipe as mp
    from mediapipe.tasks import python as mp_python
    from mediapipe.tasks.python import vision as mp_vision
except ImportError:
    raise ImportError("Run: pip install mediapipe")

# =============================================================================
# CONFIG — all tunable values here
# =============================================================================

CAMERA_INDEX           = 0       # 0 = built-in laptop camera

# ── Timing ──
STILL_THRESHOLD_SECS   = 20     # seconds of stillness → asleep
                                  # change to 600 (10 min) for real overnight use
WAKE_CONFIRM_SECS      = 3       # seconds of large movement → confirm awake
OUT_OF_BED_SECS        = 10      # seconds with no person in bed → out of bed

# ── Movement ──
LARGE_MOVE_THRESHOLD   = 0.010   # fraction of bed-ROI pixels changed = large move
                                  # raise if rolling over falsely wakes it
                                  # lower if real wake-ups are missed
SMOOTHING_FRAMES       = 8       # frames to average movement over

# ── Detection ──
YOLO_CONF              = 0.40    # YOLO confidence threshold (0–1)
POSE_CONF              = 0.50    # MediaPipe pose confidence threshold
BED_SCAN_EVERY_N       = 30      # re-run YOLO bed detection every N frames
                                  # (bed doesn't move, no need every frame)
PERSON_CHECK_EVERY_N   = 5       # re-run pose detection every N frames

# ── Model paths (same folder as this script; auto-downloaded on first run) ──
YOLO_MODEL_PATH        = str(_SCRIPT_DIR / "yolov8s.pt")
MEDIAPIPE_MODEL_PATH   = str(_SCRIPT_DIR / "pose_landmarker_full.task")
MEDIAPIPE_MODEL_URL    = (
    "https://storage.googleapis.com/mediapipe-models/"
    "pose_landmarker/pose_landmarker_full/float16/1/"
    "pose_landmarker_full.task"
)

# =============================================================================
# STATES
# =============================================================================

STATE_EMPTY  = "Not in bed"
STATE_AWAKE  = "Awake"
STATE_ASLEEP = "Asleep"
STATE_INIT   = "Initializing..."

# =============================================================================
# MODEL LOADER — downloads models if not present
# =============================================================================

def load_models():
    """
    Loads YOLOv8s and MediaPipe PoseLandmarker.
    Downloads models automatically if not found locally.
    """

    # ── YOLOv8s ──────────────────────────────────────────────────────────────
    print("  Loading YOLOv8s...", end=" ", flush=True)
    yolo = YOLO(YOLO_MODEL_PATH)   # ultralytics downloads automatically if missing
    print("OK")

    # ── MediaPipe PoseLandmarker ──────────────────────────────────────────────
    print("  Loading MediaPipe PoseLandmarker...", end=" ", flush=True)

    if not os.path.exists(MEDIAPIPE_MODEL_PATH):
        print(f"\n  Downloading pose model from Google...", end=" ", flush=True)
        try:
            urllib.request.urlretrieve(MEDIAPIPE_MODEL_URL, MEDIAPIPE_MODEL_PATH)
            print("OK")
        except Exception as e:
            raise RuntimeError(
                f"Failed to download MediaPipe model.\n"
                f"Download it manually from:\n  {MEDIAPIPE_MODEL_URL}\n"
                f"and place it in the same folder as this script.\n"
                f"Error: {e}"
            )

    base_options   = mp_python.BaseOptions(model_asset_path=MEDIAPIPE_MODEL_PATH)
    pose_options   = mp_vision.PoseLandmarkerOptions(
        base_options   = base_options,
        running_mode   = mp_vision.RunningMode.IMAGE,
        min_pose_detection_confidence = POSE_CONF,
        min_pose_presence_confidence  = POSE_CONF,
        min_tracking_confidence       = POSE_CONF,
    )
    pose_detector  = mp_vision.PoseLandmarker.create_from_options(pose_options)
    print("OK")

    return yolo, pose_detector


# =============================================================================
# BED DETECTOR — runs YOLOv8s, finds "bed" class
# =============================================================================

class BedDetector:
    """
    Uses YOLOv8s to find the bed in the frame.
    Only runs every BED_SCAN_EVERY_N frames (bed doesn't move).
    Returns a bounding box (x1,y1,x2,y2) of the detected bed.
    """

    BED_CLASS_NAME = "bed"

    def __init__(self, yolo_model):
        self.model      = yolo_model
        self.bed_box: Optional[Tuple[int,int,int,int]] = None
        self.frame_count = 0

    def update(self, frame: np.ndarray) -> Optional[Tuple[int,int,int,int]]:
        self.frame_count += 1

        # Only re-scan every N frames
        if self.frame_count % BED_SCAN_EVERY_N != 1:
            return self.bed_box

        results = self.model(frame, verbose=False, conf=YOLO_CONF)[0]

        best_box  = None
        best_conf = 0.0

        for box in results.boxes:
            class_name = results.names[int(box.cls)]
            conf       = float(box.conf)

            if class_name.lower() == self.BED_CLASS_NAME and conf > best_conf:
                x1, y1, x2, y2 = map(int, box.xyxy[0])
                best_box  = (x1, y1, x2, y2)
                best_conf = conf

        if best_box is not None:
            self.bed_box = best_box

        return self.bed_box

    def draw(self, frame: np.ndarray, color):
        if self.bed_box:
            x1, y1, x2, y2 = self.bed_box
            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
            cv2.putText(frame, "BED", (x1 + 6, y1 + 22),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)


# =============================================================================
# PERSON DETECTOR — runs MediaPipe inside the bed box
# =============================================================================

class PersonDetector:
    """
    Uses MediaPipe PoseLandmarker to check if a person is
    inside the bed bounding box.

    Only runs every PERSON_CHECK_EVERY_N frames to save CPU.
    Returns True if at least one pose landmark is inside the bed box.
    """

    # Skeleton connections — pairs of landmark indices (MediaPipe 33-point model)
    CONNECTIONS = [
        (0,1),(1,2),(2,3),(3,7),
        (0,4),(4,5),(5,6),(6,8),
        (9,10),
        (11,12),
        (11,13),(13,15),
        (12,14),(14,16),
        (11,23),(12,24),(23,24),
        (23,25),(25,27),(27,29),(29,31),
        (24,26),(26,28),(28,30),(30,32),
    ]

    def __init__(self, pose_model):
        self.model          = pose_model
        self.person_found   = False
        self.frame_count    = 0
        self.last_landmarks = None   # cached for drawing between detection frames

    def update(self, frame: np.ndarray,
               bed_box: Optional[Tuple]) -> bool:

        self.frame_count += 1

        # No bed detected yet
        if bed_box is None:
            self.person_found   = False
            self.last_landmarks = None
            return False

        # Only re-run every N frames
        if self.frame_count % PERSON_CHECK_EVERY_N != 1:
            return self.person_found

        h, w = frame.shape[:2]
        x1, y1, x2, y2 = bed_box

        rgb    = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = self.model.detect(mp_img)

        if not result.pose_landmarks:
            self.person_found   = False
            self.last_landmarks = None
            return False

        # Check if any landmark is inside the bed box
        for landmarks in result.pose_landmarks:
            for lm in landmarks:
                px = int(lm.x * w)
                py = int(lm.y * h)
                if x1 <= px <= x2 and y1 <= py <= y2:
                    self.person_found   = True
                    self.last_landmarks = landmarks
                    return True

        self.person_found   = False
        self.last_landmarks = None
        return False

    def draw_skeleton(self, frame: np.ndarray, color):
        """Draw skeleton joints and connecting bones on the frame."""
        if self.last_landmarks is None:
            return

        h, w = frame.shape[:2]
        pts  = [(int(lm.x * w), int(lm.y * h)) for lm in self.last_landmarks]

        # Bones
        for a, b in self.CONNECTIONS:
            if a < len(pts) and b < len(pts):
                cv2.line(frame, pts[a], pts[b], color, 2, cv2.LINE_AA)

        # Joints
        for pt in pts:
            cv2.circle(frame, pt, 4, (255, 255, 255), -1)
            cv2.circle(frame, pt, 4, color, 1)


# =============================================================================
# MOVEMENT DETECTOR — measures pixel change inside bed box only
# =============================================================================

class MovementDetector:
    """
    Measures frame-to-frame pixel change INSIDE the bed bounding box only.
    This means TV flickering, people walking past, or shadows outside
    the bed area are completely ignored.
    """

    def __init__(self):
        self.prev_gray  = None
        self.smooth_buf = []

    def update(self, frame: np.ndarray,
               bed_box: Optional[Tuple]) -> Tuple[float, bool]:

        h, w = frame.shape[:2]

        # Crop to bed region only
        if bed_box:
            x1, y1, x2, y2 = bed_box
            roi = frame[max(0,y1):min(h,y2), max(0,x1):min(w,x2)]
        else:
            roi = frame

        if roi.size == 0:
            return 0.0, False

        gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
        gray = cv2.GaussianBlur(gray, (9, 9), 0)

        if self.prev_gray is None or self.prev_gray.shape != gray.shape:
            self.prev_gray = gray
            return 0.0, False

        diff = cv2.absdiff(self.prev_gray, gray)
        _, thr = cv2.threshold(diff, 15, 255, cv2.THRESH_BINARY)

        total  = gray.shape[0] * gray.shape[1]
        score  = np.count_nonzero(thr) / total

        self.prev_gray = gray

        self.smooth_buf.append(score)
        if len(self.smooth_buf) > SMOOTHING_FRAMES:
            self.smooth_buf.pop(0)
        smoothed = float(np.mean(self.smooth_buf))

        return smoothed, smoothed > LARGE_MOVE_THRESHOLD

    def reset(self):
        self.prev_gray  = None
        self.smooth_buf = []


# =============================================================================
# SLEEP LOG
# =============================================================================

class SleepLog:

    def __init__(self):
        self.sessions              = []
        self.sleep_start: Optional[float] = None

    def start_sleep(self):
        if self.sleep_start is None:
            self.sleep_start = time.time()

    def end_sleep(self, reason: str = "woke up"):
        if self.sleep_start is None:
            return
        end_time = time.time()
        duration = end_time - self.sleep_start
        session  = {
            "start":    self.sleep_start,
            "end":      end_time,
            "duration": duration,
            "reason":   reason,
        }
        self.sessions.append(session)
        self._print_session(session)
        self.sleep_start = None

    def _print_session(self, s):
        start = datetime.fromtimestamp(s["start"]).strftime("%I:%M:%S %p")
        end   = datetime.fromtimestamp(s["end"]).strftime("%I:%M:%S %p")
        print(f"\n  [SESSION] Asleep: {start}  Woke: {end}  "
              f"Duration: {self.fmt(s['duration'])}  Reason: {s['reason']}")

    @property
    def current_sleep_duration(self) -> float:
        return (time.time() - self.sleep_start) if self.sleep_start else 0.0

    @property
    def total_sleep_today(self) -> float:
        return sum(s["duration"] for s in self.sessions)

    @staticmethod
    def fmt(secs: float) -> str:
        h = int(secs // 3600)
        m = int((secs % 3600) // 60)
        s = int(secs % 60)
        return f"{h}h {m:02d}m {s:02d}s" if h > 0 else f"{m}m {s:02d}s"

    def sessions_display(self) -> list:
        lines = []
        for s in self.sessions[-5:]:
            start = datetime.fromtimestamp(s["start"]).strftime("%I:%M %p")
            end   = datetime.fromtimestamp(s["end"]).strftime("%I:%M %p")
            lines.append(f"{start} -> {end}  ({self.fmt(s['duration'])})")
        return lines


# =============================================================================
# SLEEP STATE MACHINE
# =============================================================================

class SleepStateMachine:
    """
    Controls state transitions:

    NOT IN BED  ──(person detected in bed)──►  AWAKE
    AWAKE       ──(still for 60s)────────────►  ASLEEP
    ASLEEP      ──(large move for 8s)────────►  AWAKE
    AWAKE/ASLEEP──(person leaves bed)────────►  NOT IN BED
    """

    def __init__(self, log: SleepLog):
        self.log   = log
        self.state = STATE_EMPTY

        self.still_since:      Optional[float] = None
        self.large_move_since: Optional[float] = None
        self.no_person_since:  Optional[float] = None

    def update(self, person_in_bed: bool,
               movement_score: float, is_large_move: bool):
        now = time.time()

        # ── Track absence ────────────────────────────────────────────────────
        if not person_in_bed:
            if self.no_person_since is None:
                self.no_person_since = now
            if now - self.no_person_since >= OUT_OF_BED_SECS:
                if self.state == STATE_ASLEEP:
                    self.log.end_sleep(reason="left bed")
                if self.state != STATE_EMPTY:
                    print(f"\n  Person left bed "
                          f"({datetime.now().strftime('%I:%M:%S %p')})")
                self._reset()
                self.state = STATE_EMPTY
            return
        else:
            self.no_person_since = None

        # ── Person just got into bed ─────────────────────────────────────────
        if self.state == STATE_EMPTY:
            self.state = STATE_AWAKE
            print(f"\n  Person in bed — monitoring started "
                  f"({datetime.now().strftime('%I:%M:%S %p')})")

        # ── AWAKE: watch for sustained stillness ─────────────────────────────
        if self.state == STATE_AWAKE:
            if not is_large_move:
                if self.still_since is None:
                    self.still_since = now
                if now - self.still_since >= STILL_THRESHOLD_SECS:
                    self.state = STATE_ASLEEP
                    self.log.start_sleep()
                    self.large_move_since = None
                    print(f"\n  Fell asleep at "
                          f"{datetime.now().strftime('%I:%M:%S %p')}")
            else:
                self.still_since = None

        # ── ASLEEP: watch for sustained large movement ───────────────────────
        elif self.state == STATE_ASLEEP:
            if is_large_move:
                if self.large_move_since is None:
                    self.large_move_since = now
                if now - self.large_move_since >= WAKE_CONFIRM_SECS:
                    self.state = STATE_AWAKE
                    self.log.end_sleep(reason="woke up")
                    self.still_since = None
                    print(f"\n  Woke up at "
                          f"{datetime.now().strftime('%I:%M:%S %p')}")
            else:
                self.large_move_since = None

    def _reset(self):
        self.still_since      = None
        self.large_move_since = None
        self.no_person_since  = None

    def sleep_progress(self) -> float:
        if self.state != STATE_AWAKE or self.still_since is None:
            return 0.0
        return min((time.time() - self.still_since) / STILL_THRESHOLD_SECS, 1.0)

    def wake_progress(self) -> float:
        if self.state != STATE_ASLEEP or self.large_move_since is None:
            return 0.0
        return min((time.time() - self.large_move_since) / WAKE_CONFIRM_SECS, 1.0)


# =============================================================================
# UI DRAWING
# =============================================================================

def draw_ui(frame, state, log, movement_score, sleep_prog,
            wake_prog, bed_detector, person_detector, person_found):

    h, w = frame.shape[:2]

    COLOR_ASLEEP = (80,  200, 80)
    COLOR_AWAKE  = (0,   200, 255)
    COLOR_EMPTY  = (120, 120, 120)
    COLOR_TEXT   = (220, 220, 220)
    COLOR_DIM    = (100, 100, 100)

    color = {
        STATE_ASLEEP: COLOR_ASLEEP,
        STATE_AWAKE:  COLOR_AWAKE,
        STATE_EMPTY:  COLOR_EMPTY,
        STATE_INIT:   COLOR_EMPTY,
    }.get(state, COLOR_EMPTY)

    # ── Bed bounding box ──────────────────────────────────────────────────────
    bed_detector.draw(frame, color)

    # ── Skeleton ──────────────────────────────────────────────────────────────
    person_detector.draw_skeleton(frame, color)

    # ── Small info box — top right corner ────────────────────────────────────
    # Box dimensions
    BOX_W  = 220
    BOX_H  = 155
    BOX_X  = w - BOX_W - 10   # 10px from right edge
    BOX_Y  = 10                # 10px from top edge
    PAD    = 8                 # inner padding

    # Semi-transparent dark background
    overlay = frame.copy()
    cv2.rectangle(overlay, (BOX_X, BOX_Y), (BOX_X + BOX_W, BOX_Y + BOX_H),
                  (20, 20, 20), -1)
    cv2.addWeighted(overlay, 0.75, frame, 0.25, 0, frame)

    # Colored border matching state
    cv2.rectangle(frame, (BOX_X, BOX_Y), (BOX_X + BOX_W, BOX_Y + BOX_H), color, 2)

    px = BOX_X + PAD
    py = BOX_Y + PAD

    # State (big-ish label)
    cv2.putText(frame, state, (px, py + 16),
                cv2.FONT_HERSHEY_SIMPLEX, 0.65, color, 2, cv2.LINE_AA)
    py += 26

    # Person indicator
    dot_color = COLOR_ASLEEP if person_found else COLOR_DIM
    cv2.circle(frame, (px + 5, py + 5), 5, dot_color, -1)
    cv2.putText(frame, "In bed" if person_found else "Not detected",
                (px + 14, py + 10), cv2.FONT_HERSHEY_SIMPLEX, 0.38, dot_color, 1)
    py += 18

    # Movement bar
    bar_w = BOX_W - PAD * 2
    filled = int(min(movement_score / (LARGE_MOVE_THRESHOLD * 2), 1.0) * bar_w)
    bar_color = COLOR_AWAKE if movement_score > LARGE_MOVE_THRESHOLD else COLOR_ASLEEP
    cv2.rectangle(frame, (px, py), (px + bar_w, py + 7), (50, 50, 50), -1)
    if filled > 0:
        cv2.rectangle(frame, (px, py), (px + filled, py + 7), bar_color, -1)
    cv2.putText(frame, "movement", (px, py + 17),
                cv2.FONT_HERSHEY_SIMPLEX, 0.32, COLOR_DIM, 1)
    py += 22

    # Confirmation progress bar (sleep or wake)
    if sleep_prog > 0:
        cv2.rectangle(frame, (px, py), (px + bar_w, py + 6), (50, 50, 50), -1)
        cv2.rectangle(frame, (px, py), (px + int(bar_w * sleep_prog), py + 6),
                      COLOR_ASLEEP, -1)
        cv2.putText(frame, f"sleep confirm {sleep_prog:.0%}",
                    (px, py + 16), cv2.FONT_HERSHEY_SIMPLEX, 0.32, COLOR_DIM, 1)
        py += 22
    elif wake_prog > 0:
        cv2.rectangle(frame, (px, py), (px + bar_w, py + 6), (50, 50, 50), -1)
        cv2.rectangle(frame, (px, py), (px + int(bar_w * wake_prog), py + 6),
                      COLOR_AWAKE, -1)
        cv2.putText(frame, f"wake confirm {wake_prog:.0%}",
                    (px, py + 16), cv2.FONT_HERSHEY_SIMPLEX, 0.32, COLOR_DIM, 1)
        py += 22

    # Current sleep duration
    if state == STATE_ASLEEP and log.sleep_start:
        dur_str = SleepLog.fmt(log.current_sleep_duration)
        cv2.putText(frame, f"Asleep: {dur_str}",
                    (px, py + 12), cv2.FONT_HERSHEY_SIMPLEX, 0.42, color, 1)
        py += 18

    # Total sleep today
    total = log.total_sleep_today + log.current_sleep_duration
    cv2.putText(frame, f"Total:  {SleepLog.fmt(total)}",
                (px, py + 12), cv2.FONT_HERSHEY_SIMPLEX, 0.42, COLOR_TEXT, 1)


# =============================================================================
# MAIN
# =============================================================================

def main():
    print("\n" + "="*55)
    print("  Sleep Monitor")
    print("="*55)

    # Load models
    yolo, pose_model = load_models()

    # Setup components
    log            = SleepLog()
    bed_detector   = BedDetector(yolo)
    person_detector = PersonDetector(pose_model)
    movement_detector = MovementDetector()
    state_machine  = SleepStateMachine(log)

    print(f"\n  Still threshold : {STILL_THRESHOLD_SECS}s  "
          f"(STILL_THRESHOLD_SECS in config)")
    print(f"  Wake confirm    : {WAKE_CONFIRM_SECS}s")
    print(f"  Large move at   : {LARGE_MOVE_THRESHOLD}")
    print("  Press Q to quit")
    print("="*55 + "\n")

    cap = cv2.VideoCapture(CAMERA_INDEX)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open camera {CAMERA_INDEX}")
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    while True:
        ok, frame = cap.read()
        if not ok:
            time.sleep(0.03)
            continue

        # ── Detections ────────────────────────────────────────────────────────
        bed_box      = bed_detector.update(frame)
        person_found = person_detector.update(frame, bed_box)
        movement_score, is_large = movement_detector.update(frame, bed_box)

        # Reset movement history when person leaves bed
        if not person_found and state_machine.state == STATE_EMPTY:
            movement_detector.reset()

        # ── State machine ─────────────────────────────────────────────────────
        state_machine.update(person_found, movement_score, is_large)

        # ── Draw ──────────────────────────────────────────────────────────────
        draw_ui(
            frame,
            state           = state_machine.state,
            log             = log,
            movement_score  = movement_score,
            sleep_prog      = state_machine.sleep_progress(),
            wake_prog       = state_machine.wake_progress(),
            bed_detector    = bed_detector,
            person_detector = person_detector,
            person_found    = person_found,
        )

        # Console
        bed_str = "found" if bed_box else "searching"
        print(f"\r  [{state_machine.state:<12}]  "
              f"bed={bed_str}  person={'YES' if person_found else 'no '}  "
              f"move={movement_score:.5f}  large={'YES' if is_large else 'no '}  "
              f"asleep={SleepLog.fmt(log.current_sleep_duration)}",
              end="", flush=True)

        cv2.imshow("Sleep Monitor", frame)
        if cv2.waitKey(10) & 0xFF == ord('q'):
            break

    # Close open session on quit
    if state_machine.state == STATE_ASLEEP:
        log.end_sleep(reason="monitoring stopped")

    cap.release()
    cv2.destroyAllWindows()

    # Final report
    print("\n\n" + "="*55)
    print("  Final Report")
    print("="*55)
    print(f"  Total sleep : {SleepLog.fmt(log.total_sleep_today)}")
    print(f"  Sessions    : {len(log.sessions)}")
    for i, s in enumerate(log.sessions, 1):
        start = datetime.fromtimestamp(s["start"]).strftime("%I:%M %p")
        end   = datetime.fromtimestamp(s["end"]).strftime("%I:%M %p")
        print(f"    {i}. {start} -> {end}  "
              f"({SleepLog.fmt(s['duration'])})  [{s['reason']}]")
    print("="*55)


if __name__ == "__main__":
    main()