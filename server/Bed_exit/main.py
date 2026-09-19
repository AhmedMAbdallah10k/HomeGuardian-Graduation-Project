"""
main.py  —  Home Guardian · Nurse Mode · Bed Exit Detection
Run:  python main.py            (camera preview on by default)
      python main.py --no-show    (headless — no window)
Test: python test.py

MediaPipe model:
https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/1/pose_landmarker_full.task
"""

import cv2, os, time, threading, collections, argparse
from datetime import datetime
import mediapipe as mp
from mediapipe.tasks.python import vision as mp_vision
from mediapipe.tasks.python.core import base_options as mp_base
from ultralytics import YOLO

# Folder this script lives in, so model paths work no matter where you launch from.
_HERE = os.path.dirname(os.path.abspath(__file__))

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIG
# ═══════════════════════════════════════════════════════════════════════════════
CAMERA_SOURCE       = 0
MEDIAPIPE_MODEL     = os.path.join(_HERE, "pose_landmarker_full.task")
MEDIAPIPE_CONF      = 0.4
YOLO_MODEL          = os.path.join(_HERE, "yolov8s.pt")
YOLO_CONF           = 0.4
YOLO_EVERY          = 10
PERSON_CLASS        = 0
BED_CLASS           = 59

# MediaPipe landmark indices (33 total)
LM = {
    "nose":           0,
    "left_shoulder":  11,  "right_shoulder": 12,
    "left_elbow":     13,  "right_elbow":    14,
    "left_wrist":     15,  "right_wrist":    16,
    "left_hip":       23,  "right_hip":      24,
    "left_knee":      25,  "right_knee":     26,
    "left_ankle":     27,  "right_ankle":    28,
    "left_heel":      29,  "right_heel":     30,
    "left_foot":      31,  "right_foot":     32,
}

# Sit-up detection — uses torso rise (hip Y vs shoulder Y)
# More reliable than head Y because rolling in bed moves both together
TORSO_RISE_THRESHOLD = 0.20   # fraction of bed height
TORSO_MIN_FRAMES     = 6      # consecutive frames risen before State 1 triggers
TORSO_ALPHA          = 0.04   # baseline smoothing — lower = slower adaptation

# Exit detection — any leg landmark outside bed box
FOOT_BUFFER_PX       = 20
FOOT_MIN_FRAMES      = 4

# Caregiver
CAREGIVER_COUNT      = 2

ALERT_COOLDOWN_SEC   = 60
CLIP_PRE_SEC         = 20
CLIP_POST_SEC        = 10
CLIP_DIR             = "clips/"
PATIENT_NAME         = "Patient"
ROOM_NAME            = "Room 1"


# ═══════════════════════════════════════════════════════════════════════════════
# KEYPOINT HELPERS
# ═══════════════════════════════════════════════════════════════════════════════
def _avg_y(kp, *names):
    ys = [kp[n]["y"] for n in names if kp.get(n,{}).get("v")]
    return sum(ys)/len(ys) if ys else None

def _avg_x(kp, *names):
    xs = [kp[n]["x"] for n in names if kp.get(n,{}).get("v")]
    return sum(xs)/len(xs) if xs else None

def torso_rise(kp):
    """
    Hip Y minus shoulder Y.
    Lying flat  → both at same height → value near 0.
    Sitting up  → shoulders rise above hips → value becomes POSITIVE.
    Rolling/turning in bed → both move together → value stays near 0.
    This is why torso rise is much better than raw head Y.
    """
    sY = _avg_y(kp, "left_shoulder", "right_shoulder")
    hY = _avg_y(kp, "left_hip",      "right_hip")
    if sY is None or hY is None: return None
    return hY - sY   # positive = shoulders above hips

def leg_xs(kp):
    """X positions of ALL visible leg landmarks — knees, ankles, heels, feet."""
    names = ("left_knee","right_knee","left_ankle","right_ankle",
             "left_heel","right_heel","left_foot", "right_foot")
    return [kp[n]["x"] for n in names if kp.get(n,{}).get("v")]

def body_center_x(kp):
    """Average X of torso + thigh landmarks — used for full-exit detection."""
    names = ("left_shoulder","right_shoulder","left_hip","right_hip",
             "left_knee",    "right_knee")
    xs = [kp[n]["x"] for n in names if kp.get(n,{}).get("v")]
    return int(sum(xs)/len(xs)) if xs else None

def head_y(kp):
    """Fallback head position for display."""
    for n in ("nose","left_shoulder","right_shoulder"):
        p = kp.get(n)
        if p and p.get("v"): return p["y"]
    return None


# ═══════════════════════════════════════════════════════════════════════════════
# DETECTOR
# ═══════════════════════════════════════════════════════════════════════════════
class Detector:
    def __init__(self):
        self.model = YOLO(YOLO_MODEL)

    def run(self, frame):
        results = self.model(frame, conf=YOLO_CONF, verbose=False)[0]
        persons, bed_box = 0, None
        for box in results.boxes:
            cls        = int(box.cls[0])
            x1,y1,x2,y2 = map(int, box.xyxy[0])
            if cls == PERSON_CLASS:
                persons += 1
            if cls == BED_CLASS:
                area = (x2-x1)*(y2-y1)
                if bed_box is None or area > (bed_box["x2"]-bed_box["x1"])*(bed_box["y2"]-bed_box["y1"]):
                    bed_box = dict(x1=x1,y1=y1,x2=x2,y2=y2)
        return dict(persons=persons, caregiver=persons>=CAREGIVER_COUNT, bed_box=bed_box)


# ═══════════════════════════════════════════════════════════════════════════════
# POSE
# ═══════════════════════════════════════════════════════════════════════════════
class Pose:
    def __init__(self):
        if not os.path.exists(MEDIAPIPE_MODEL):
            raise RuntimeError(
                f"Model not found: {MEDIAPIPE_MODEL}\n"
                "Download: https://storage.googleapis.com/mediapipe-models/"
                "pose_landmarker/pose_landmarker_full/float16/1/pose_landmarker_full.task"
            )
        opts = mp_vision.PoseLandmarkerOptions(
            base_options=mp_base.BaseOptions(model_asset_path=MEDIAPIPE_MODEL),
            running_mode=mp_vision.RunningMode.VIDEO,
            min_pose_detection_confidence=MEDIAPIPE_CONF,
            min_pose_presence_confidence=MEDIAPIPE_CONF,
            min_tracking_confidence=MEDIAPIPE_CONF,
        )
        self.detector = mp_vision.PoseLandmarker.create_from_options(opts)
        self.ts       = 0
        print("MediaPipe ready.")

    def run(self, frame):
        fh, fw  = frame.shape[:2]
        self.ts += 67
        img    = mp.Image(image_format=mp.ImageFormat.SRGB,
                          data=cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
        result = self.detector.detect_for_video(img, self.ts)
        if not result.pose_landmarks: return None

        lm = result.pose_landmarks[0]
        kp = {}
        for name, idx in LM.items():
            l = lm[idx]
            kp[name] = {
                "x": int(l.x * fw),
                "y": int(l.y * fh),
                "v": l.visibility >= MEDIAPIPE_CONF,
            }
        return kp

    def close(self): self.detector.close()


# ═══════════════════════════════════════════════════════════════════════════════
# STATE MACHINE
# ═══════════════════════════════════════════════════════════════════════════════
class StateMachine:
    def __init__(self):
        self.state          = 0
        self.baseline_rise  = None   # adaptive torso rise baseline
        self.bed_height     = None
        self.torso_count    = 0      # consecutive frames torso has been risen
        self.foot_count     = 0      # consecutive frames legs outside bed

    def update(self, kp, bed_box, caregiver):
        """Returns (state, alert_type, message)"""
        if kp is None or bed_box is None:
            return self.state, "none", ""

        if self.bed_height is None:
            self.bed_height = bed_box["y2"] - bed_box["y1"]

        rise = torso_rise(kp)
        fxs  = leg_xs(kp)
        cx   = body_center_x(kp)

        # First frame — set baseline
        if self.baseline_rise is None:
            if rise is not None: self.baseline_rise = rise
            return self.state, "none", ""

        # ── State 0: Resting ─────────────────────────────────────────────────
        if self.state == 0:
            # Adaptive baseline: follows normal repositioning
            # If torso rise stays near baseline, it just updates.
            # If rise jumps suddenly, baseline lags behind — the difference
            # is what triggers sit-up detection.
            if rise is not None:
                self.baseline_rise = ((1 - TORSO_ALPHA) * self.baseline_rise
                                      + TORSO_ALPHA * rise)

            delta = (rise - self.baseline_rise) if rise is not None else 0
            threshold = self.bed_height * TORSO_RISE_THRESHOLD

            if delta > threshold:
                self.torso_count += 1
            else:
                self.torso_count = 0

            if self.torso_count >= TORSO_MIN_FRAMES:
                self.state = 1; self.torso_count = 0
                print(f"→ State 1: sitting up  "
                      f"(rise={rise:.0f}, baseline={self.baseline_rise:.0f}, "
                      f"delta={delta:.0f}, threshold={threshold:.0f})")

        # ── State 1: Sitting up ──────────────────────────────────────────────
        elif self.state == 1:
            # Lay back — hysteresis band to prevent flicker
            if rise is not None:
                delta     = rise - self.baseline_rise
                threshold = self.bed_height * TORSO_RISE_THRESHOLD
                if delta < threshold * 0.4:
                    self.state = 0; self.foot_count = 0; self.torso_count = 0
                    print("→ State 0: lay back down")
                    return self.state, "none", ""

            # Legs leaving bed — use ALL leg landmarks
            self._tick_feet(fxs, bed_box)
            if self.foot_count >= FOOT_MIN_FRAMES:
                if caregiver:
                    return 1, "assisted", \
                        f"{PATIENT_NAME} getting out of bed — caregiver present."
                self.state = 2
                print("→ State 2: ALERT — legs over edge")
                return 2, "early_warning", \
                    f"ALERT: {PATIENT_NAME} legs over bed edge — unassisted."

        # ── State 2: Legs over edge ──────────────────────────────────────────
        elif self.state == 2:
            self._tick_feet(fxs, bed_box)
            if caregiver:
                return 2, "assisted", \
                    f"{PATIENT_NAME} out of bed — caregiver present."
            # Full exit: body center of mass outside bed
            if cx is not None:
                if cx < bed_box["x1"] - 40 or cx > bed_box["x2"] + 40:
                    self.state = 3
                    print("→ State 3: CRITICAL — fully exited")
                    return 3, "critical", \
                        f"CRITICAL: {PATIENT_NAME} fully exited the bed unassisted."
            return 2, "early_warning", \
                f"ALERT: {PATIENT_NAME} legs over bed edge — unassisted."

        # ── State 3: Fully exited ────────────────────────────────────────────
        elif self.state == 3:
            if caregiver:
                return 3, "assisted", f"{PATIENT_NAME} out of bed — caregiver present."
            return 3, "critical", \
                f"CRITICAL: {PATIENT_NAME} fully exited the bed unassisted."

        return self.state, "none", ""

    def _tick_feet(self, fxs, bed_box):
        left  = bed_box["x1"] - FOOT_BUFFER_PX
        right = bed_box["x2"] + FOOT_BUFFER_PX
        if fxs and any(x < left or x > right for x in fxs):
            self.foot_count += 1
        else:
            self.foot_count = 0

    def reset(self):
        self.state=0; self.baseline_rise=None; self.bed_height=None
        self.torso_count=0; self.foot_count=0


# ═══════════════════════════════════════════════════════════════════════════════
# ALERT MANAGER
# ═══════════════════════════════════════════════════════════════════════════════
class AlertManager:
    def __init__(self):
        os.makedirs(CLIP_DIR, exist_ok=True)
        self.buf        = collections.deque(maxlen=(CLIP_PRE_SEC+CLIP_POST_SEC)*15)
        self.last_alert = 0
        self.active     = False
        self.clip_buf   = []
        self.post_count = 0
        self.recording  = False

    def buffer(self, frame):
        self.buf.append(frame.copy())
        if self.recording:
            self.clip_buf.append(frame.copy())
            self.post_count += 1
            if self.post_count >= CLIP_POST_SEC * 15:
                self._save(); self.recording=False; self.post_count=0

    def handle(self, alert_type, message, caregiver):
        if alert_type in ("none","assisted"): return
        if time.time() - self.last_alert < ALERT_COOLDOWN_SEC: return
        self.last_alert=time.time(); self.active=True
        self.clip_buf=list(self.buf); self.recording=True; self.post_count=0
        ts    = datetime.now().strftime("%H:%M:%S")
        title = f"ALERT — {PATIENT_NAME} — {ROOM_NAME}"
        body  = f"{message} [{ts}]"
        print(f"\n{'!'*60}\n[{alert_type.upper()}] {body}\n{'!'*60}\n")
        threading.Thread(target=self._dispatch,
                         args=(title,body,alert_type), daemon=True).start()

    def _dispatch(self, title, body, alert_type):
        self.push(title, body)
        if alert_type == "critical":
            time.sleep(90)
            if self.active: self.sms(body)

    def _save(self):
        if not self.clip_buf: return
        path = os.path.join(CLIP_DIR,f"bed_exit_{datetime.now():%Y%m%d_%H%M%S}.mp4")
        h,w  = self.clip_buf[0].shape[:2]
        out  = cv2.VideoWriter(path,cv2.VideoWriter_fourcc(*"mp4v"),15,(w,h))
        for f in self.clip_buf: out.write(f)
        out.release(); print(f"[CLIP] {path}"); self.clip_buf=[]

    def push(self, title, body): print(f"[PUSH] {title}: {body}")
    def sms(self, body):         print(f"[SMS]  {body}")


# ═══════════════════════════════════════════════════════════════════════════════
# DISPLAY
# ═══════════════════════════════════════════════════════════════════════════════
SKELETON = [
    ("left_shoulder","right_shoulder"),
    ("left_shoulder","left_elbow"),   ("right_shoulder","right_elbow"),
    ("left_elbow",   "left_wrist"),   ("right_elbow",   "right_wrist"),
    ("left_shoulder","left_hip"),     ("right_shoulder","right_hip"),
    ("left_hip",     "right_hip"),
    ("left_hip",     "left_knee"),    ("right_hip",     "right_knee"),
    ("left_knee",    "left_ankle"),   ("right_knee",    "right_ankle"),
    ("left_ankle",   "left_heel"),    ("right_ankle",   "right_heel"),
    ("left_heel",    "left_foot"),    ("right_heel",    "right_foot"),
]

def draw_skeleton(frame, kp):
    for a, b in SKELETON:
        pa, pb = kp.get(a), kp.get(b)
        if pa and pb and pa["v"] and pb["v"]:
            cv2.line(frame, (pa["x"],pa["y"]), (pb["x"],pb["y"]),
                     (200,200,200), 1, cv2.LINE_AA)
    for name, p in kp.items():
        if p["v"]:
            # Color by body region
            if "hip" in name or "shoulder" in name:
                col = (55, 126, 184)   # blue — torso
            elif "knee" in name or "ankle" in name or "heel" in name or "foot" in name:
                col = (228, 26, 28)    # red — legs
            else:
                col = (217, 95, 14)    # orange — head/arms
            cv2.circle(frame, (p["x"],p["y"]), 6, col, -1)
            cv2.circle(frame, (p["x"],p["y"]), 6, (255,255,255), 1)

def draw_alert_banner(frame, atype):
    h, w = frame.shape[:2]
    if int(time.time()*2) % 2 == 0:
        overlay = frame.copy()
        col = (0,0,180) if atype == "early_warning" else (0,0,220)
        cv2.rectangle(overlay, (0,0), (w,90), col, -1)
        cv2.addWeighted(overlay, 0.75, frame, 0.25, 0, frame)
        text = "⚠  ALERT — BED EXIT  ⚠" if atype=="early_warning" else "⚠  CRITICAL — FULLY OUT OF BED  ⚠"
        cv2.putText(frame, text, (10,58),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.95, (255,255,255), 2)

def draw_status(frame, d, state, atype, kp, sm):
    h, w = frame.shape[:2]
    bar  = h - 80
    cv2.rectangle(frame, (0,bar), (w,h), (15,15,15), -1)

    # Row 1 — detections
    bed_c = (29,158,117) if d["bed_box"] else (80,80,80)
    per_c = (29,158,117) if d["persons"] else (80,80,80)
    cv2.putText(frame, f"Bed: {'YES' if d['bed_box'] else 'not detected'}",
                (10, bar+22), cv2.FONT_HERSHEY_SIMPLEX, 0.55, bed_c, 1)
    cv2.putText(frame, f"Persons: {d['persons']}",
                (200, bar+22), cv2.FONT_HERSHEY_SIMPLEX, 0.55, per_c, 1)
    if d["caregiver"]:
        cv2.putText(frame, "CAREGIVER PRESENT",
                    (360, bar+22), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (29,158,117), 1)

    # Row 2 — state
    LABELS = {0:"Resting",1:"Sitting up",2:"Legs over edge",3:"Fully exited"}
    COLS   = {0:(77,175,74),1:(255,165,0),2:(228,26,28),3:(228,26,28)}
    if d["persons"]==0 or d["bed_box"] is None:
        lbl, col = "Waiting...", (100,100,100)
    elif atype=="assisted":
        lbl, col = "Assisted transfer", (29,158,117)
    else:
        lbl, col = LABELS[state], COLS[state]
    cv2.putText(frame, lbl, (10, bar+54),
                cv2.FONT_HERSHEY_SIMPLEX, 0.8, col, 2)

    # Debug: torso rise
    if sm.baseline_rise is not None and kp:
        rise = torso_rise(kp)
        if rise is not None:
            delta = rise - sm.baseline_rise
            cv2.putText(frame,
                        f"torso delta: {delta:.0f}px  "
                        f"(threshold: {(sm.bed_height or 0)*TORSO_RISE_THRESHOLD:.0f}px)",
                        (10, bar+72),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.38, (120,120,120), 1)


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN LOOP
# ═══════════════════════════════════════════════════════════════════════════════
def run(source, show):
    det    = Detector()
    pose   = Pose()
    sm     = StateMachine()
    alerts = AlertManager()
    cap    = cv2.VideoCapture(source)
    if not cap.isOpened(): raise RuntimeError(f"Cannot open: {source}")

    if show:
        cv2.namedWindow("Nurse Mode", cv2.WINDOW_NORMAL)
        cv2.resizeWindow("Nurse Mode", 1280, 720)
        print("Preview window open — press Q in the window to quit.")
    else:
        print("Running headless (no preview). Use without --no-show to see the camera.")

    frame_count       = 0
    d                 = dict(persons=0, caregiver=False, bed_box=None)
    kp                = None
    state, atype, msg = 0, "none", ""

    while True:
        ret, frame = cap.read()
        if not ret: break
        frame_count += 1
        alerts.buffer(frame)

        if frame_count % YOLO_EVERY == 0:
            d = det.run(frame)

        if d["persons"] > 0:
            kp            = pose.run(frame)
            state, atype, msg = sm.update(kp, d["bed_box"], d["caregiver"])
            alerts.handle(atype, msg, d["caregiver"])
        else:
            kp    = None
            state = 0; atype = "none"; msg = ""

        if show:
            disp = frame.copy()
            if d["bed_box"]:
                bb = d["bed_box"]
                cv2.rectangle(disp,(bb["x1"],bb["y1"]),(bb["x2"],bb["y2"]),
                              (55,126,184), 2)
            if kp:
                draw_skeleton(disp, kp)
            if atype in ("early_warning","critical"):
                draw_alert_banner(disp, atype)
            draw_status(disp, d, state, atype, kp, sm)
            cv2.imshow("Nurse Mode", disp)
            if cv2.waitKey(1) & 0xFF == ord("q"): break

    cap.release(); pose.close()
    if show: cv2.destroyAllWindows()


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--source", default=CAMERA_SOURCE)
    p.add_argument("--show", action="store_true", default=True,
                   help="Show live camera preview (default: on)")
    p.add_argument("--no-show", dest="show", action="store_false",
                   help="Run without opening a preview window")
    args = p.parse_args()
    run(args.source, args.show)