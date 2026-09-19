"""
Silver-mode sleep monitoring on dashboard JPEG uploads (`/api/laptop-monitor`).

Loads `Sleep_detection/sleep_detector.py` via importlib without importing `main()`
or modifying sleep_detector.py / yolov8s.pt / pose_landmarker_full.task.

Models (explicit paths):
  - server/Sleep_detection/yolov8s.pt
  - server/Sleep_detection/pose_landmarker_full.task

Requires YOLO to detect a real bed (COCO class "bed") before tracking sleep.
No whole-frame fallback — avoids false "fell asleep" in rooms without a bed.
"""

from __future__ import annotations

import importlib.util
import threading
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

_SLEEP_DIR = Path(__file__).resolve().parent / "Sleep_detection"
_YOLO_PATH = _SLEEP_DIR / "yolov8s.pt"
_POSE_PATH = _SLEEP_DIR / "pose_landmarker_full.task"

# YOLO must confidently see a bed; person must have pose landmarks inside that box.
_BED_MIN_CONF = 0.45
_BED_MIN_AREA_RATIO = 0.04  # bed box must cover at least 4% of frame
_BED_CACHE_MAX_MISS = 20    # keep last bed box across ~10s of sparse JPEG uploads
_PERSON_PAD_RATIO = 0.08    # small padding around bed box for pose landmarks

_module_lock = threading.Lock()
_sleep_mod = None

_models_lock = threading.Lock()
_yolo = None
_pose = None
_pose_lock = threading.Lock()

_pipeline_lock = threading.Lock()
_pipelines: Dict[Tuple[int, str], "_RoomSleepPipeline"] = {}
_last_diag_ts: Dict[Tuple[int, str], float] = {}

_YOLO_IMGSZ = 640


def _apply_bridge_patches(mod) -> None:
    """Match standalone sleep_detector tuning (do not relax thresholds)."""
    mod.YOLO_CONF = 0.40
    mod.LARGE_MOVE_THRESHOLD = 0.010
    mod.SMOOTHING_FRAMES = 8


def _load_sleep_module():
    global _sleep_mod
    if _sleep_mod is not None:
        return _sleep_mod
    with _module_lock:
        if _sleep_mod is not None:
            return _sleep_mod
        script = _SLEEP_DIR / "sleep_detector.py"
        if not script.is_file():
            raise FileNotFoundError(f"Missing sleep detector script: {script}")
        spec = importlib.util.spec_from_file_location("hg_sleep_detector", script)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        _apply_bridge_patches(mod)
        _sleep_mod = mod
        print(f"[SLEEP-BRIDGE] logic={script}")
        return _sleep_mod


def _load_shared_models(mod):
    global _yolo, _pose
    if _yolo is not None and _pose is not None:
        return _yolo, _pose

    with _models_lock:
        if _yolo is not None and _pose is not None:
            return _yolo, _pose

        if not _YOLO_PATH.is_file():
            raise FileNotFoundError(f"Missing YOLO weights: {_YOLO_PATH.resolve()}")
        if not _POSE_PATH.is_file():
            raise FileNotFoundError(f"Missing MediaPipe model: {_POSE_PATH.resolve()}")

        from ultralytics import YOLO
        from mediapipe.tasks.python import vision as mp_vision
        from mediapipe.tasks.python.core import base_options as mp_base

        _yolo = YOLO(str(_YOLO_PATH.resolve()))
        mp_bytes = _POSE_PATH.read_bytes()
        pose_options = mp_vision.PoseLandmarkerOptions(
            base_options=mp_base.BaseOptions(model_asset_buffer=mp_bytes),
            running_mode=mp_vision.RunningMode.IMAGE,
            min_pose_detection_confidence=mod.POSE_CONF,
            min_pose_presence_confidence=mod.POSE_CONF,
            min_tracking_confidence=mod.POSE_CONF,
        )
        _pose = mp_vision.PoseLandmarker.create_from_options(pose_options)
        print(
            f"[SLEEP-BRIDGE] yolo={_YOLO_PATH.resolve()} "
            f"pose={_POSE_PATH.resolve()} ({len(mp_bytes) // 1024}KB)"
        )
        return _yolo, _pose


def _maybe_upscale(frame):
    import cv2

    h, w = frame.shape[:2]
    longest = max(h, w)
    if longest >= _YOLO_IMGSZ:
        return frame
    scale = float(_YOLO_IMGSZ) / longest
    return cv2.resize(
        frame,
        (int(w * scale), int(h * scale)),
        interpolation=cv2.INTER_LINEAR,
    )


def _bed_area_ratio(bed: Tuple[int, int, int, int], frame_shape) -> float:
    fh, fw = frame_shape[:2]
    x1, y1, x2, y2 = bed
    return max(0, x2 - x1) * max(0, y2 - y1) / max(fw * fh, 1)


def _run_yolo(
    yolo,
    frame,
    mod,
) -> Tuple[Optional[Tuple[int, int, int, int]], float]:
    """Return best YOLO bed box and confidence, or (None, 0)."""
    best_box: Optional[Tuple[int, int, int, int]] = None
    best_conf = 0.0

    try:
        results = yolo(frame, verbose=False, conf=mod.YOLO_CONF, imgsz=_YOLO_IMGSZ)[0]
        for box in results.boxes:
            name = results.names[int(box.cls)].lower()
            conf = float(box.conf)
            if name != "bed" or conf <= best_conf:
                continue
            x1, y1, x2, y2 = map(int, box.xyxy[0])
            if x2 <= x1 or y2 <= y1:
                continue
            candidate = (x1, y1, x2, y2)
            if _bed_area_ratio(candidate, frame.shape) < _BED_MIN_AREA_RATIO:
                continue
            best_box = candidate
            best_conf = conf
    except Exception as exc:
        print(f"[SLEEP-BRIDGE] YOLO error: {exc}")

    if best_box is not None and best_conf >= _BED_MIN_CONF:
        return best_box, best_conf
    return None, best_conf


def _resolve_bed_box(
    yolo_bed: Optional[Tuple[int, int, int, int]],
    cached_bed: Optional[Tuple[int, int, int, int]],
    bed_miss_count: int,
) -> Tuple[Optional[Tuple[int, int, int, int]], str, int]:
    """
    Use a fresh YOLO bed when available; otherwise reuse cached bed for a short
    window (bed does not move). Never invent a bed from person/default region.
    """
    if yolo_bed is not None:
        return yolo_bed, "yolo_bed", 0

    if cached_bed is not None and bed_miss_count < _BED_CACHE_MAX_MISS:
        return cached_bed, "cached_bed", bed_miss_count + 1

    return None, "no_bed", bed_miss_count + 1


def _landmark_in_bed(px: int, py: int, bed: Tuple[int, int, int, int], pad: int) -> bool:
    x1, y1, x2, y2 = bed
    return (x1 - pad) <= px <= (x2 + pad) and (y1 - pad) <= py <= (y2 + pad)


def _person_in_bed(
    mod,
    pose,
    frame,
    bed_box: Tuple[int, int, int, int],
) -> Tuple[bool, str, int]:
    """
    Strict person-in-bed check — same rule as sleep_detector.PersonDetector:
    at least one pose landmark must fall inside the bed bounding box.
    """
    import cv2
    import numpy as np

    h, w = frame.shape[:2]
    x1, y1, x2, y2 = bed_box
    pad = max(int((x2 - x1) * _PERSON_PAD_RATIO), 12)
    pad = min(pad, int(min(x2 - x1, y2 - y1) * 0.15))

    pose_pts = 0
    try:
        rgb = np.ascontiguousarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
        mp_img = mod.mp.Image(image_format=mod.mp.ImageFormat.SRGB, data=rgb)
        with _pose_lock:
            result = pose.detect(mp_img)

        if result.pose_landmarks:
            for landmarks in result.pose_landmarks:
                for lm in landmarks:
                    pose_pts += 1
                    px = int(lm.x * w)
                    py = int(lm.y * h)
                    if _landmark_in_bed(px, py, bed_box, pad):
                        return True, "pose_in_bed", pose_pts
    except Exception as exc:
        print(f"[SLEEP-BRIDGE] pose error: {exc}")

    return False, "none", pose_pts


class _BridgeMovementDetector:
    def __init__(self, mod) -> None:
        self._mod = mod
        self.prev_gray = None
        self.smooth_buf: List[float] = []

    def update(self, frame, bed_box):
        import cv2
        import numpy as np

        h, w = frame.shape[:2]
        x1, y1, x2, y2 = bed_box
        roi = frame[max(0, y1) : min(h, y2), max(0, x1) : min(w, x2)]
        if roi.size == 0:
            return 0.0, False

        gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
        gray = cv2.GaussianBlur(gray, (9, 9), 0)

        if self.prev_gray is None or self.prev_gray.shape != gray.shape:
            self.prev_gray = gray
            return 0.0, False

        diff = cv2.absdiff(self.prev_gray, gray)
        _, thr = cv2.threshold(diff, 15, 255, cv2.THRESH_BINARY)
        total = gray.shape[0] * gray.shape[1]
        score = float(np.count_nonzero(thr) / total)
        self.prev_gray = gray

        self.smooth_buf.append(score)
        cap = self._mod.SMOOTHING_FRAMES
        if len(self.smooth_buf) > cap:
            self.smooth_buf.pop(0)
        smoothed = float(np.mean(self.smooth_buf))
        return smoothed, smoothed > self._mod.LARGE_MOVE_THRESHOLD

    def reset(self) -> None:
        self.prev_gray = None
        self.smooth_buf = []


class _RoomSleepPipeline:
    __slots__ = (
        "user_id",
        "room",
        "yolo",
        "pose",
        "movement",
        "log",
        "sm",
        "frame_count",
        "cached_bed_box",
        "bed_miss_count",
        "last_diag_detail",
    )

    def __init__(self, mod, yolo, pose, user_id: int, room: str) -> None:
        self.user_id = user_id
        self.room = room
        self.yolo = yolo
        self.pose = pose
        self.movement = _BridgeMovementDetector(mod)
        self.log = mod.SleepLog()
        self.sm = mod.SleepStateMachine(self.log)
        self.frame_count = 0
        self.cached_bed_box: Optional[Tuple[int, int, int, int]] = None
        self.bed_miss_count = 0
        self.last_diag_detail: dict = {}
        print(
            f"[SLEEP-BRIDGE] pipeline uid={user_id} room={room!r} "
            f"yolo={_YOLO_PATH.name} pose={_POSE_PATH.name}"
        )

    def _reset_monitoring(self, mod) -> None:
        if self.sm.state == mod.STATE_ASLEEP:
            self.log.end_sleep(reason="bed lost")
        if self.sm.state != mod.STATE_EMPTY:
            print(
                f"[SLEEP-BRIDGE] uid={self.user_id} room={self.room!r} "
                "reset — no bed detected"
            )
        self.sm._reset()
        self.sm.state = mod.STATE_EMPTY
        self.movement.reset()
        self.cached_bed_box = None
        self.bed_miss_count = 0

    def process(self, mod, frame) -> List[dict]:
        self.frame_count += 1
        frame = _maybe_upscale(frame)

        yolo_bed, bed_conf = _run_yolo(self.yolo, frame, mod)
        if yolo_bed is not None:
            self.cached_bed_box = yolo_bed

        bed_box, bed_source, self.bed_miss_count = _resolve_bed_box(
            yolo_bed,
            self.cached_bed_box,
            self.bed_miss_count,
        )

        if bed_box is None:
            self._reset_monitoring(mod)
            key = (self.user_id, self.room)
            _maybe_log_diag(
                key,
                {
                    "frame_count": self.frame_count,
                    "state": mod.STATE_EMPTY,
                    "bed_yolo": False,
                    "bed_source": bed_source,
                    "bed_conf": round(bed_conf, 3),
                    "person": False,
                    "person_via": "no_bed",
                    "yolo_persons": 0,
                    "pose_pts": 0,
                    "move": 0.0,
                    "large": False,
                    "still_prog": 0.0,
                    "wake_prog": 0.0,
                },
            )
            return []

        person_found, person_via, pose_pts = _person_in_bed(
            mod, self.pose, frame, bed_box
        )
        movement_score, is_large = self.movement.update(frame, bed_box)

        if not person_found:
            self.movement.reset()

        old_state = self.sm.state
        self.sm.update(person_found, movement_score, is_large)
        new_state = self.sm.state

        self.last_diag_detail = {
            "bed_source": bed_source,
            "person_via": person_via,
            "pose_pts": pose_pts,
            "bed_conf": round(bed_conf, 3),
        }

        key = (self.user_id, self.room)
        _maybe_log_diag(
            key,
            {
                "frame_count": self.frame_count,
                "state": new_state,
                "bed_yolo": yolo_bed is not None,
                "bed_source": bed_source,
                "bed_conf": round(bed_conf, 3),
                "person": person_found,
                "person_via": person_via,
                "yolo_persons": 0,
                "pose_pts": pose_pts,
                "move": movement_score,
                "large": is_large,
                "still_prog": self.sm.sleep_progress(),
                "wake_prog": self.sm.wake_progress(),
            },
        )

        events: List[dict] = []
        if old_state != new_state:
            if new_state == mod.STATE_ASLEEP:
                events.append(
                    {
                        "event": "fell_asleep",
                        "state": new_state,
                        "movement_score": round(movement_score, 5),
                    }
                )
            elif old_state == mod.STATE_ASLEEP and new_state in (
                mod.STATE_AWAKE,
                mod.STATE_EMPTY,
            ):
                duration_sec = 0.0
                reason = "woke up"
                if self.log.sessions:
                    duration_sec = float(self.log.sessions[-1].get("duration") or 0)
                    reason = str(self.log.sessions[-1].get("reason") or reason)
                events.append(
                    {
                        "event": "woke_up",
                        "state": new_state,
                        "reason": reason,
                        "duration_sec": duration_sec,
                        "duration_label": mod.SleepLog.fmt(duration_sec),
                        "movement_score": round(movement_score, 5),
                    }
                )

        return events


def _maybe_log_diag(key: Tuple[int, str], info: dict) -> None:
    now = time.time()
    if now - _last_diag_ts.get(key, 0.0) < 20.0:
        return
    _last_diag_ts[key] = now
    print(
        "[SLEEP-DIAG] "
        f"uid={key[0]} room={key[1]!r} "
        f"frames={info.get('frame_count')} state={info.get('state')!r} "
        f"bed_yolo={info.get('bed_yolo')} bed_src={info.get('bed_source')} "
        f"bed_conf={info.get('bed_conf')} "
        f"person={info.get('person')} via={info.get('person_via')} "
        f"pose_pts={info.get('pose_pts')} "
        f"move={info.get('move', 0):.4f} large={info.get('large')} "
        f"still={info.get('still_prog', 0):.0%} wake={info.get('wake_prog', 0):.0%}"
    )


def preload() -> None:
    mod = _load_sleep_module()
    _load_shared_models(mod)


def process_upload_jpeg(
    user_id: int,
    room_name: str,
    jpeg_bytes: bytes,
) -> List[dict]:
    import cv2
    import numpy as np

    room = (room_name or "").strip()
    if not room or room == "Unknown":
        return []
    if not jpeg_bytes or len(jpeg_bytes) < 80:
        return []

    arr = np.frombuffer(jpeg_bytes, dtype=np.uint8)
    frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if frame is None:
        return []

    mod = _load_sleep_module()
    yolo, pose = _load_shared_models(mod)

    key = (user_id, room)
    with _pipeline_lock:
        pipe = _pipelines.get(key)
        if pipe is None:
            if len(_pipelines) > 48:
                for k_old in list(_pipelines.keys())[:20]:
                    del _pipelines[k_old]
            pipe = _RoomSleepPipeline(mod, yolo, pose, user_id, room)
            _pipelines[key] = pipe

    try:
        events = pipe.process(mod, frame)
        for ev in events:
            ev["room_name"] = room
            ev["user_id"] = user_id
        if events:
            print(
                f"[SLEEP-BRIDGE] uid={user_id} room={room!r} "
                f"events={[e.get('event') for e in events]} state={pipe.sm.state}"
            )
        return events
    except Exception as exc:
        print(f"[SLEEP-BRIDGE] process uid={user_id} room={room!r}: {exc}")
        import traceback

        traceback.print_exc()
        return []
