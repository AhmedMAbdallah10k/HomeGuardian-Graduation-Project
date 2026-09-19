"""
Bed exit detection on dashboard JPEG uploads (same path as `/api/laptop-monitor`).

Loads `Bed_exit/main.py` via importlib without modifying that module. Uses the same
Detector (YOLO yolov8s.pt), Pose (MediaPipe pose_landmarker_full.task), and StateMachine
logic as the standalone OpenCV demo.
"""

from __future__ import annotations

import importlib.util
import os
import threading
import time
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

os.environ.setdefault("TF_ENABLE_ONEDNN_OPTS", "0")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")

_MAIN_PATH = Path(__file__).resolve().parent / "Bed_exit" / "main.py"
_BED_EXIT_DIR = _MAIN_PATH.parent.resolve()

# Standalone demo uses YOLO_EVERY=10 at ~15 fps. Dashboard JPEGs arrive ~2–4 fps,
# so run YOLO every frame here for stable person/bed tracking and state-machine counts.
BRIDGE_YOLO_EVERY = 1

_module_lock = threading.Lock()
_cached_module = None
_mp_model_bytes: Optional[bytes] = None

_detector_lock = threading.Lock()
_shared_detector = None

_cache_lock = threading.Lock()
_pipelines: Dict[Tuple[int, str], "_RoomBedExitPipeline"] = {}
_last_diag_ts: Dict[Tuple[int, str], float] = {}


def _get_mp_model_bytes() -> bytes:
    """Load pose_landmarker_full.task once; buffer avoids Windows path bugs in MediaPipe."""
    global _mp_model_bytes
    if _mp_model_bytes is not None:
        return _mp_model_bytes
    mp_task = _BED_EXIT_DIR / "pose_landmarker_full.task"
    if not mp_task.is_file():
        raise FileNotFoundError(
            f"Missing MediaPipe model: {mp_task}\n"
            "Download pose_landmarker_full.task into server/Bed_exit/"
        )
    _mp_model_bytes = mp_task.read_bytes()
    return _mp_model_bytes


def _apply_bridge_patches(mod) -> None:
    """
    Patch model paths after importlib load. MediaPipe on Windows concatenates
    site-packages/ with D:\\ absolute paths (errno 22). Loading from bytes fixes it.
    """
    yolo = _BED_EXIT_DIR / "yolov8s.pt"
    if not yolo.is_file():
        raise FileNotFoundError(f"Missing YOLO model: {yolo}")
    mod.YOLO_MODEL = str(yolo)
    _get_mp_model_bytes()

    orig_pose = mod.Pose
    mp_bytes = _mp_model_bytes

    class _BridgePose(orig_pose):
        def __init__(self):
            from mediapipe.tasks.python import vision as mp_vision
            from mediapipe.tasks.python.core import base_options as mp_base

            opts = mp_vision.PoseLandmarkerOptions(
                base_options=mp_base.BaseOptions(model_asset_buffer=mp_bytes),
                running_mode=mp_vision.RunningMode.VIDEO,
                min_pose_detection_confidence=mod.MEDIAPIPE_CONF,
                min_pose_presence_confidence=mod.MEDIAPIPE_CONF,
                min_tracking_confidence=mod.MEDIAPIPE_CONF,
            )
            self.detector = mp_vision.PoseLandmarker.create_from_options(opts)
            self.ts = 0
            print("MediaPipe ready.")

    mod.Pose = _BridgePose

    # Standalone demo: ~15 fps + OpenCV window. Dashboard JPEGs: ~2–4 fps with
    # noisier pose landmarks. Tune constants + state-0 logic without editing main.py.
    mod.TORSO_MIN_FRAMES = 3   # was 6
    mod.FOOT_MIN_FRAMES = 2    # was 4
    mod.TORSO_ALPHA = 0.012    # was 0.04 — slower baseline drift
    mod.FOOT_BUFFER_PX = -12   # was 20 — narrower "on bed" zone → legs exit sooner

    _BaseStateMachine = mod.StateMachine

    class _MonitorStateMachine(_BaseStateMachine):
        """
        Full state machine tuned for dashboard JPEG streams (~3 fps, wide YOLO bed boxes).
        """

        def _delta_and_threshold(self, rise, mod):
            threshold = self.bed_height * mod.TORSO_RISE_THRESHOLD
            delta = (rise - self.baseline_rise) if rise is not None else 0.0
            return delta, threshold

        def _legs_leaving(self, fxs, kp, bed_box, mod) -> bool:
            left = bed_box["x1"] - mod.FOOT_BUFFER_PX
            right = bed_box["x2"] + mod.FOOT_BUFFER_PX
            if fxs and any(x < left or x > right for x in fxs):
                return True
            mattress_line = bed_box["y2"] - max(12, int(self.bed_height * 0.06))
            for n in ("left_ankle", "right_ankle", "left_knee", "right_knee", "left_foot", "right_foot"):
                p = kp.get(n) if kp else None
                if p and p.get("v") and p["y"] >= mattress_line:
                    return True
            return False

        def update(self, kp, bed_box, caregiver):
            if kp is None or bed_box is None:
                return self.state, "none", ""

            if self.bed_height is None:
                self.bed_height = bed_box["y2"] - bed_box["y1"]

            rise = mod.torso_rise(kp)
            fxs = mod.leg_xs(kp)
            cx = mod.body_center_x(kp)

            if self.baseline_rise is None:
                if rise is not None:
                    self.baseline_rise = rise
                return self.state, "none", ""

            delta, threshold = self._delta_and_threshold(rise, mod)
            patient = mod.PATIENT_NAME

            # ── State 0: Resting ─────────────────────────────────────────────
            if self.state == 0:
                if rise is not None and delta <= threshold * 0.55:
                    self.baseline_rise = (
                        (1 - mod.TORSO_ALPHA) * self.baseline_rise
                        + mod.TORSO_ALPHA * rise
                    )
                    delta, threshold = self._delta_and_threshold(rise, mod)

                if delta > threshold:
                    self.torso_count += 1
                elif delta < threshold * 0.42:
                    self.torso_count = 0

                if self.torso_count >= mod.TORSO_MIN_FRAMES:
                    self.state = 1
                    self.torso_count = 0
                    self.foot_count = 0
                    print(
                        f"[BED-EXIT] → State 1 sitting up "
                        f"(delta={delta:.0f}, threshold={threshold:.0f})"
                    )
                return self.state, "none", ""

            # ── State 1: Sitting up ──────────────────────────────────────────
            if self.state == 1:
                if delta < threshold * 0.35:
                    self.state = 0
                    self.foot_count = 0
                    self.torso_count = 0
                    print("[BED-EXIT] → State 0 lay back down")
                    return self.state, "none", ""

                leaving = self._legs_leaving(fxs, kp, bed_box, mod)
                # Webcam path: strong sustained sit-up (torso clearly elevated)
                strong_sit = delta > threshold * 0.75

                if leaving or strong_sit:
                    self.foot_count += 1
                elif delta < threshold * 0.5:
                    self.foot_count = max(0, self.foot_count - 1)

                if self.foot_count >= mod.FOOT_MIN_FRAMES:
                    if caregiver:
                        return (
                            1,
                            "assisted",
                            f"{patient} getting out of bed — caregiver present.",
                        )
                    self.state = 2
                    self.foot_count = 0
                    reason = "legs leaving bed" if leaving else "sustained sit-up"
                    print(f"[BED-EXIT] → State 2 ALERT ({reason})")
                    return (
                        2,
                        "early_warning",
                        f"ALERT: {patient} leaving bed unassisted ({reason}).",
                    )
                return self.state, "none", ""

            # ── State 2: Legs over edge / exiting ────────────────────────────
            if self.state == 2:
                if caregiver:
                    return (
                        2,
                        "assisted",
                        f"{patient} out of bed — caregiver present.",
                    )
                fully_out = False
                if cx is not None:
                    if cx < bed_box["x1"] - 30 or cx > bed_box["x2"] + 30:
                        fully_out = True
                if delta > threshold * 1.8:
                    fully_out = True
                if fully_out:
                    self.state = 3
                    print("[BED-EXIT] → State 3 CRITICAL fully exited")
                    return (
                        3,
                        "critical",
                        f"CRITICAL: {patient} fully exited the bed unassisted.",
                    )
                return (
                    2,
                    "early_warning",
                    f"ALERT: {patient} legs over bed edge — unassisted.",
                )

            # ── State 3: Fully exited ──────────────────────────────────────
            if self.state == 3:
                if caregiver:
                    return (
                        3,
                        "assisted",
                        f"{patient} out of bed — caregiver present.",
                    )
                return (
                    3,
                    "critical",
                    f"CRITICAL: {patient} fully exited the bed unassisted.",
                )

            return self.state, "none", ""

    mod.StateMachine = _MonitorStateMachine


def _effective_bed_box(bed_box: dict, kp: Optional[dict], fw: int, fh: int) -> dict:
    """
    YOLO 'bed' often spans the whole mattress/frame on webcam shots, so leg X coords
    never fall outside the box. Shrink to the patient's torso width when bed is too wide.
    """
    bb = dict(bed_box)
    bw = bb["x2"] - bb["x1"]
    if bw <= fw * 0.62 or not kp:
        return bb
    xs = []
    for n in ("left_hip", "right_hip", "left_shoulder", "right_shoulder"):
        p = kp.get(n)
        if p and p.get("v"):
            xs.append(p["x"])
    if not xs:
        return bb
    cx = int(sum(xs) / len(xs))
    half_w = max(int(bw * 0.16), 55)
    bb["x1"] = max(0, cx - half_w)
    bb["x2"] = min(fw, cx + half_w)
    # Keep vertical extent but trim excessive height above shoulders
    if kp:
        ys = [
            kp[n]["y"]
            for n in ("left_shoulder", "right_shoulder", "nose")
            if kp.get(n, {}).get("v")
        ]
        if ys:
            bb["y1"] = max(bb["y1"], min(ys) - int(fh * 0.08))
    return bb


def _infer_bed_box(mod, frame, d: dict) -> dict:
    """
    When YOLO misses COCO class 'bed' (common on laptop webcams), infer a bed region
    from the largest person box so the state machine can still run.
    """
    if d.get("bed_box") is not None or d.get("persons", 0) <= 0:
        return d

    h, w = frame.shape[:2]
    results = None
    try:
        det = _get_shared_detector(mod)
        results = det.model(frame, conf=mod.YOLO_CONF, verbose=False)[0]
    except Exception:
        results = None

    person_boxes = []
    if results is not None:
        for box in results.boxes:
            if int(box.cls[0]) == mod.PERSON_CLASS:
                x1, y1, x2, y2 = map(int, box.xyxy[0])
                person_boxes.append((x1, y1, x2, y2))

    out = dict(d)
    if person_boxes:
        x1, y1, x2, y2 = max(person_boxes, key=lambda b: (b[2] - b[0]) * (b[3] - b[1]))
        pw, ph = x2 - x1, y2 - y1
        pad_x = int(pw * 0.45)
        out["bed_box"] = {
            "x1": max(0, x1 - pad_x),
            "y1": max(0, y1 - int(ph * 0.12)),
            "x2": min(w, x2 + pad_x),
            "y2": min(h, y2 + int(ph * 0.35)),
        }
    else:
        # Last resort: lower-center of frame (typical bed-in-view webcam angle)
        out["bed_box"] = {
            "x1": int(w * 0.06),
            "y1": int(h * 0.28),
            "x2": int(w * 0.94),
            "y2": int(h * 0.98),
        }
    out["bed_inferred"] = True
    return out


def _run_detector(mod, detector, frame) -> dict:
    """Same logic as Bed_exit.Detector.run — kept in bridge so we can tune for monitor uploads."""
    results = detector.model(frame, conf=mod.YOLO_CONF, verbose=False)[0]
    persons, bed_box = 0, None
    for box in results.boxes:
        cls = int(box.cls[0])
        x1, y1, x2, y2 = map(int, box.xyxy[0])
        if cls == mod.PERSON_CLASS:
            persons += 1
        if cls == mod.BED_CLASS:
            area = (x2 - x1) * (y2 - y1)
            if bed_box is None or area > (bed_box["x2"] - bed_box["x1"]) * (
                bed_box["y2"] - bed_box["y1"]
            ):
                bed_box = dict(x1=x1, y1=y1, x2=x2, y2=y2)
    d = dict(persons=persons, caregiver=persons >= mod.CAREGIVER_COUNT, bed_box=bed_box)
    return _infer_bed_box(mod, frame, d)


def _maybe_log_diag(key: Tuple[int, str], info: dict) -> None:
    now = time.time()
    if now - _last_diag_ts.get(key, 0.0) < 20.0:
        return
    _last_diag_ts[key] = now
    print(
        "[BED-EXIT-DIAG] "
        f"uid={key[0]} room={key[1]!r} "
        f"frame={info.get('frame_count')} persons={info.get('persons')} "
        f"bed_yolo={info.get('bed_yolo')} bed_inferred={info.get('bed_inferred')} "
        f"pose={info.get('pose_ok')} state={info.get('state')} "
        f"alert_type={info.get('alert_type')!r} caregiver={info.get('caregiver')} "
        f"torso_delta={info.get('torso_delta')} "
        f"torso_thresh={info.get('torso_threshold')} "
        f"torso_count={info.get('torso_count')} foot_count={info.get('foot_count')} "
        f"strong_sit={info.get('strong_sit')}"
    )


class _RoomBedExitPipeline:
    """Stateful bed-exit pipeline for one (user_id, room) monitor stream."""

    __slots__ = (
        "sm",
        "pose",
        "frame_count",
        "d",
        "last_alert_ts",
        "prev_state",
        "recording_armed",
        "recording_armed_at",
    )

    def __init__(self, mod) -> None:
        self.sm = mod.StateMachine()
        self.pose = mod.Pose()
        self.frame_count = 0
        self.d: dict = dict(persons=0, caregiver=False, bed_box=None)
        self.last_alert_ts = 0.0
        self.prev_state = 0
        self.recording_armed = False
        self.recording_armed_at: Optional[float] = None

    def close(self) -> None:
        try:
            self.pose.close()
        except Exception:
            pass


def _load_main_module():
    global _cached_module
    if _cached_module is not None:
        return _cached_module
    if not _MAIN_PATH.is_file():
        raise FileNotFoundError(f"Missing bed exit module: {_MAIN_PATH}")
    with _module_lock:
        if _cached_module is None:
            spec = importlib.util.spec_from_file_location("_hg_bed_exit_impl", _MAIN_PATH)
            mod = importlib.util.module_from_spec(spec)
            assert spec.loader is not None
            spec.loader.exec_module(mod)
            _apply_bridge_patches(mod)
            _cached_module = mod
            print(f"[BED-EXIT-BRIDGE] loaded {_MAIN_PATH.name} from {_MAIN_PATH.parent}")
    return _cached_module


def _get_shared_detector(mod):
    global _shared_detector
    if _shared_detector is not None:
        return _shared_detector
    with _detector_lock:
        if _shared_detector is None:
            _shared_detector = mod.Detector()
            print("[BED-EXIT-BRIDGE] YOLO detector ready.")
        return _shared_detector


def preload() -> None:
    """Eager-load models at server startup."""
    mod = _load_main_module()
    _get_shared_detector(mod)
    pipe = _RoomBedExitPipeline(mod)
    pipe.close()
    print("[BED-EXIT-BRIDGE] preload complete (Nurse mode only).")


def process_upload_jpeg(user_id: int, room_label: str, jpeg_bytes: bytes) -> Tuple[bool, dict]:
    """
    Decode laptop-monitor JPEG and run one bed-exit pipeline step.
    Returns (alert_now, info) when early_warning or critical should fire this upload.
    """
    import cv2
    import numpy as np

    if not jpeg_bytes or len(jpeg_bytes) < 80:
        return False, {}

    arr = np.frombuffer(jpeg_bytes, dtype=np.uint8)
    frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if frame is None:
        return False, {}

    h, w = frame.shape[:2]
    longest = max(h, w)
    if longest < 640:
        scale = 720.0 / float(longest)
        frame = cv2.resize(
            frame,
            (int(w * scale), int(h * scale)),
            interpolation=cv2.INTER_LINEAR,
        )

    mod = _load_main_module()
    detector = _get_shared_detector(mod)

    key = (user_id, room_label.strip())
    with _cache_lock:
        pipe = _pipelines.get(key)
        if pipe is None:
            if len(_pipelines) > 48:
                for k_old, old in list(_pipelines.items())[:20]:
                    old.close()
                    del _pipelines[k_old]
                print("[BED-EXIT-BRIDGE] trimmed old room pipelines cache")
            pipe = _RoomBedExitPipeline(mod)
            _pipelines[key] = pipe

    pipe.frame_count += 1
    info: Dict[str, Any] = {
        "frame_count": pipe.frame_count,
        "persons": pipe.d.get("persons", 0),
        "bed_yolo": pipe.d.get("bed_box") is not None and not pipe.d.get("bed_inferred"),
        "bed_inferred": bool(pipe.d.get("bed_inferred")),
        "state": pipe.sm.state,
        "alert_type": "none",
        "caregiver": pipe.d.get("caregiver", False),
        "pose_ok": False,
    }

    if pipe.frame_count % BRIDGE_YOLO_EVERY == 0:
        pipe.d = _run_detector(mod, detector, frame)
        info["persons"] = pipe.d.get("persons", 0)
        info["caregiver"] = pipe.d.get("caregiver", False)
        info["bed_yolo"] = pipe.d.get("bed_box") is not None and not pipe.d.get("bed_inferred")
        info["bed_inferred"] = bool(pipe.d.get("bed_inferred"))

    alert_now = False
    if pipe.d.get("persons", 0) > 0:
        kp = pipe.pose.run(frame)
        info["pose_ok"] = kp is not None
        bed_box = pipe.d.get("bed_box")
        if bed_box and kp:
            bed_box = _effective_bed_box(bed_box, kp, frame.shape[1], frame.shape[0])
            info["bed_shrunk"] = True
        state, atype, msg = pipe.sm.update(
            kp, bed_box, pipe.d.get("caregiver", False)
        )
        info["state"] = state
        info["alert_type"] = atype
        info["message"] = msg

        # Start clip capture when sit-up begins (state 0→1), not when alert fires.
        if pipe.prev_state == 0 and state == 1 and not pipe.recording_armed:
            pipe.recording_armed = True
            pipe.recording_armed_at = time.time()
            info["arm_recording"] = True
        if state == 0:
            pipe.recording_armed = False
            pipe.recording_armed_at = None
        pipe.prev_state = state

        sm = pipe.sm
        if kp is not None and sm.baseline_rise is not None:
            rise = mod.torso_rise(kp)
            if rise is not None and sm.bed_height:
                info["torso_delta"] = round(rise - sm.baseline_rise, 1)
                info["torso_threshold"] = round(sm.bed_height * mod.TORSO_RISE_THRESHOLD, 1)
        info["torso_count"] = sm.torso_count
        info["foot_count"] = sm.foot_count
        if sm.state >= 1 and kp is not None and sm.baseline_rise is not None:
            rise = mod.torso_rise(kp)
            if rise is not None and sm.bed_height:
                d_chk = rise - sm.baseline_rise
                t_chk = sm.bed_height * mod.TORSO_RISE_THRESHOLD
                info["strong_sit"] = d_chk > t_chk * 0.75

        if atype == "assisted":
            info["assisted"] = True
        elif atype in ("early_warning", "critical"):
            now = time.time()
            if now - pipe.last_alert_ts >= mod.ALERT_COOLDOWN_SEC:
                pipe.last_alert_ts = now
                alert_now = True
                info["alert"] = True
                print(
                    f"[BED-EXIT-BRIDGE] ALERT user={user_id} room={room_label!r} "
                    f"type={atype} state={state} msg={msg!r}"
                )
            else:
                info["alert"] = False
                info["cooldown_remaining"] = round(
                    mod.ALERT_COOLDOWN_SEC - (now - pipe.last_alert_ts), 1
                )
        if alert_now and pipe.recording_armed_at:
            info["finalize_recording"] = True
            info["recording_armed_sec"] = round(
                time.time() - pipe.recording_armed_at, 2
            )
            pipe.recording_armed = False
            pipe.recording_armed_at = None
    else:
        info["state"] = 0
        info["alert_type"] = "none"

    _maybe_log_diag(key, info)
    return alert_now, info
