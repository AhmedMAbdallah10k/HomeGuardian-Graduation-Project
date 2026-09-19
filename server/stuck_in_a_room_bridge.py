"""
Stuck-in-room detection on dashboard JPEG uploads — Nanny + Pet mode.

Uses the same weights and logic as `stuck_in_a_room/app.py` (best.pt + yolov8m.pt).
The standalone app.py runs a webcam/imshow loop, so it is NOT executed here;
this bridge loads that module for CONFIG/helpers and runs stateful detection
on `/api/laptop-monitor` JPEG frames.
"""

from __future__ import annotations

import importlib.util
import threading
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

_APP_PATH = Path(__file__).resolve().parent / "stuck_in_a_room" / "app.py"
_STUCK_DIR = _APP_PATH.parent.resolve()

# Dashboard JPEGs arrive ~2–4 fps; process every upload (no 1-in-3 skip like the demo).
BRIDGE_PROCESS_EVERY = 1
# MediaPipe pose every N processed frames (child signal 3).
BRIDGE_POSE_EVERY = 10
STUCK_ALERT_COOLDOWN_SEC = 90

_module_lock = threading.Lock()
_cached_module = None

_model_lock = threading.Lock()
_person_model = None
_door_model = None

_pipeline_lock = threading.Lock()
_pipelines: Dict[Tuple[int, str], "_RoomStuckPipeline"] = {}
_last_diag_ts: Dict[Tuple[int, str], float] = {}


def _load_app_module():
    global _cached_module
    if _cached_module is not None:
        return _cached_module
    if not _APP_PATH.is_file():
        raise FileNotFoundError(f"Missing stuck-in-room module: {_APP_PATH}")
    with _module_lock:
        if _cached_module is None:
            spec = importlib.util.spec_from_file_location(
                "_hg_stuck_in_a_room_impl", _APP_PATH
            )
            mod = importlib.util.module_from_spec(spec)
            assert spec.loader is not None
            spec.loader.exec_module(mod)
            _cached_module = mod
            print(f"[STUCK-BRIDGE] loaded {_APP_PATH.name} from {_STUCK_DIR}")
    return _cached_module


def _ensure_models(mod):
    global _person_model, _door_model
    if _person_model is not None and _door_model is not None:
        return _person_model, _door_model

    person_pt = _STUCK_DIR / "yolov8m.pt"
    door_pt = _STUCK_DIR / "best.pt"
    if not person_pt.is_file():
        raise FileNotFoundError(f"Missing person/pet weights: {person_pt}")
    if not door_pt.is_file():
        raise FileNotFoundError(f"Missing door weights: {door_pt}")

    from ultralytics import YOLO

    with _model_lock:
        if _person_model is None:
            _person_model = YOLO(str(person_pt))
            print(f"[STUCK-BRIDGE] person/pet model ready ({person_pt.name})")
        if _door_model is None:
            _door_model = YOLO(str(door_pt), task="detect")
            print(f"[STUCK-BRIDGE] door model ready ({door_pt.name})")
    return _person_model, _door_model


def _active_subjects(run_nanny: bool, run_pet: bool) -> List[str]:
    subjects: List[str] = []
    if run_nanny:
        subjects.append("child")
    if run_pet:
        subjects.extend(["cat", "dog"])
    return subjects


def _maybe_log_diag(key: Tuple[int, str], info: dict) -> None:
    now = time.time()
    if now - _last_diag_ts.get(key, 0.0) < 20.0:
        return
    _last_diag_ts[key] = now
    print(
        "[STUCK-DIAG] "
        f"uid={key[0]} room={key[1]!r} "
        f"frame={info.get('frame_count')} door={info.get('door_state')!r} "
        f"subject={info.get('active_subject')!r} adult={info.get('adult_present')} "
        f"signals={info.get('signals')} score={info.get('score')} "
        f"alert_edge={info.get('alert_edge')}"
    )


class _RoomStuckPipeline:
    """Stateful stuck-in-room pipeline for one (user_id, room) monitor stream."""

    __slots__ = (
        "detectors",
        "arm_detector",
        "frame_count",
        "processed_count",
        "s3",
        "last_alert_ts",
    )

    def __init__(self, mod) -> None:
        self.detectors = {
            s: mod.StuckDetector(s) for s in mod.CONFIG["MONITOR_SUBJECTS"]
        }
        self.arm_detector = mod.ArmRaiseDetector()
        self.frame_count = 0
        self.processed_count = 0
        self.s3 = False
        self.last_alert_ts = 0.0

    def close(self) -> None:
        try:
            self.arm_detector.release()
        except Exception:
            pass


def _run_inference(
    mod,
    person_model,
    door_model,
    pipe: _RoomStuckPipeline,
    frame,
    subjects: List[str],
) -> Tuple[bool, dict]:
    pipe.frame_count += 1
    if pipe.frame_count % BRIDGE_PROCESS_EVERY != 0:
        return False, {"skipped_frame": True, "frame_count": pipe.frame_count}

    pipe.processed_count += 1
    import cv2

    h, w = frame.shape[:2]
    small = cv2.resize(frame, (320, 240))
    scale = 2

    person_results = person_model(small, verbose=False, imgsz=320)[0]
    detections: List[tuple] = []
    adult_detected = False
    found_subjects = {s: False for s in subjects}
    subject_in_door_zone = {s: False for s in subjects}

    for box in person_results.boxes:
        if float(box.conf) < mod.CONFIG["PERSON_CONFIDENCE"]:
            continue
        stype = mod.classify_detection(box, h, person_model.names, scale=scale)
        if stype is None:
            continue
        bx1, by1, bx2, by2 = box.xyxy[0].tolist()
        bbox = [bx1 * scale, by1 * scale, bx2 * scale, by2 * scale]
        if stype == "adult":
            adult_detected = True
            detections.append(("adult", bbox))
            continue
        if stype not in subjects:
            continue
        found_subjects[stype] = True
        detections.append((stype, bbox))

    door_state = "unknown"
    door_bbox = None
    best_door_conf = 0.0

    door_results = door_model(
        frame,
        conf=mod.CONFIG["DOOR_CONFIDENCE"],
        iou=0.60,
        imgsz=640,
        verbose=False,
    )[0]
    for box in door_results.boxes:
        conf = float(box.conf)
        if conf >= mod.CONFIG["DOOR_CONFIDENCE"] and conf > best_door_conf:
            cls_name = door_model.names[int(box.cls)]
            if cls_name in mod.CONFIG["DOOR_CLOSED_CLASSES"]:
                door_state = "closed"
                best_door_conf = conf
                bx1, by1, bx2, by2 = box.xyxy[0].tolist()
                door_bbox = [bx1, by1, bx2, by2]
            elif cls_name in mod.CONFIG["DOOR_OPEN_CLASSES"]:
                door_state = "open"
                best_door_conf = conf
                bx1, by1, bx2, by2 = box.xyxy[0].tolist()
                door_bbox = [bx1, by1, bx2, by2]

    door_zone = mod.compute_door_zone(door_bbox, w, h)
    if door_zone is not None:
        for stype, bbox in detections:
            if stype in subject_in_door_zone and mod.is_in_door_zone(bbox, door_zone):
                subject_in_door_zone[stype] = True

    door_closed = door_state == "closed"
    s3 = pipe.s3
    if (
        pipe.processed_count % BRIDGE_POSE_EVERY == 0
        and found_subjects.get("child")
        and "child" in subjects
    ):
        s3 = pipe.arm_detector.detect(frame)
    elif not found_subjects.get("child"):
        s3 = False
    pipe.s3 = s3

    active_subject: Optional[str] = None
    s1 = s2 = False
    elapsed = 0.0
    approach_count = 0
    alert_active = False
    alert_subject: Optional[str] = None
    alert_score = 0

    if adult_detected:
        for det in pipe.detectors.values():
            det.reset_door_open()
        s3 = False
        pipe.s3 = False
    else:
        for stype in subjects:
            det = pipe.detectors[stype]
            if door_state == "open":
                det.reset_door_open()
                continue
            if not found_subjects[stype]:
                if det.in_room_since is not None:
                    det.in_room_since = None
                continue

            _s1, _elapsed = det.update_signal1(True, door_closed)
            _s2, _count = det.update_signal2(subject_in_door_zone[stype])
            _s3 = det.update_signal3(s3) if stype == "child" else False
            _score = sum([_s1, _s2, _s3])

            if _score >= mod.CONFIG["ALERT_SCORE"]:
                active_subject = stype
                alert_subject = stype
                s1, s2, elapsed, approach_count = _s1, _s2, _elapsed, _count
                s3 = _s3
                alert_active = True
                alert_score = _score
                break
            if active_subject is None and found_subjects[stype]:
                active_subject = stype
                s1, s2, elapsed, approach_count = _s1, _s2, _elapsed, _count
                s3 = _s3

    info: Dict[str, Any] = {
        "frame_count": pipe.frame_count,
        "processed_count": pipe.processed_count,
        "door_state": door_state,
        "door_confidence": round(best_door_conf, 3),
        "adult_present": adult_detected,
        "active_subject": active_subject,
        "alert_subject": alert_subject,
        "elapsed_sec": round(elapsed, 1),
        "approach_count": approach_count,
        "signals": [s1, s2, s3],
        "score": alert_score if alert_active else sum([s1, s2, s3]),
        "alert_edge": False,
    }

    if alert_active and alert_subject:
        now = time.time()
        if now - pipe.last_alert_ts >= STUCK_ALERT_COOLDOWN_SEC:
            pipe.last_alert_ts = now
            info["alert_edge"] = True
            line1, line2 = mod.ALERT_MESSAGES.get(
                alert_subject, ("STUCK IN ROOM", "Please check immediately")
            )
            info["title"] = line1
            info["message"] = line2
            info["subject_type"] = alert_subject
            print(
                f"[STUCK-BRIDGE] ALERT subject={alert_subject} score={alert_score}/3 "
                f"door={door_state} elapsed={elapsed:.0f}s approaches={approach_count}"
            )

    return bool(info.get("alert_edge")), info


def preload() -> None:
    mod = _load_app_module()
    _ensure_models(mod)
    pipe = _RoomStuckPipeline(mod)
    pipe.close()
    print("[STUCK-BRIDGE] preload complete (Nanny + Pet mode).")


def process_upload_jpeg(
    user_id: int,
    room_label: str,
    jpeg_bytes: bytes,
    run_nanny: bool,
    run_pet: bool,
) -> Tuple[bool, dict]:
    """
    Decode laptop-monitor JPEG and run one stuck-in-room pipeline step.
    Returns (alert_now, info) when 2+ signals are active for a monitored subject.
    """
    import cv2
    import numpy as np

    if not run_nanny and not run_pet:
        return False, {}
    if not jpeg_bytes or len(jpeg_bytes) < 80:
        return False, {}

    arr = np.frombuffer(jpeg_bytes, dtype=np.uint8)
    frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if frame is None:
        return False, {}

    subjects = _active_subjects(run_nanny, run_pet)
    if not subjects:
        return False, {}

    mod = _load_app_module()
    person_model, door_model = _ensure_models(mod)

    key = (user_id, room_label.strip())
    with _pipeline_lock:
        pipe = _pipelines.get(key)
        if pipe is None:
            if len(_pipelines) > 48:
                for k_old, old in list(_pipelines.items())[:20]:
                    old.close()
                    del _pipelines[k_old]
                print("[STUCK-BRIDGE] trimmed old room pipelines cache")
            pipe = _RoomStuckPipeline(mod)
            _pipelines[key] = pipe

    alert_now, info = _run_inference(
        mod, person_model, door_model, pipe, frame, subjects
    )
    info["run_nanny"] = run_nanny
    info["run_pet"] = run_pet
    _maybe_log_diag(key, info)
    return alert_now, info
