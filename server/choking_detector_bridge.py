"""
Loads `MODES/Nanny Mode/choking_detetction/run.py` via importlib (single shared detector).

Per-room `monitor_modes` (Silver, Nanny, Nurse) feed laptop-monitor JPEG bytes into
ChokingDetector without using the demo's OpenCV webcam loop.
"""

from __future__ import annotations

import importlib.util
import pathlib
import threading
from typing import Any, Dict, Tuple

_RUN_PATH = (
    pathlib.Path(__file__).resolve().parent
    / "MODES"
    / "Nanny Mode"
    / "choking_detetction"
    / "run.py"
)

_module_lock = threading.Lock()
_cached_module = None

_cache_lock = threading.Lock()
_detector_cache: Dict[tuple[int, str], Any] = {}
_frame_counter: Dict[tuple[int, str], int] = {}

# MediaPipe Pose every dashboard frame (~500ms × 2 cams → keep 1 so window fills in ~90s baseline)
EVERY_N_FRAMES = 1


def _load_run_module():
    """Dynamic import — loads current run.py from disk on first use after process start."""
    global _cached_module
    if _cached_module is not None:
        return _cached_module
    if not _RUN_PATH.is_file():
        raise FileNotFoundError(f"Missing choking module: {_RUN_PATH}")
    with _module_lock:
        if _cached_module is None:
            spec = importlib.util.spec_from_file_location("_hg_choking_run_impl", _RUN_PATH)
            mod = importlib.util.module_from_spec(spec)
            assert spec.loader is not None
            spec.loader.exec_module(mod)
            _cached_module = mod
    return _cached_module


def process_upload_jpeg(user_id: int, room_label: str, jpeg_bytes: bytes) -> Tuple[bool, dict]:
    """Decode laptop-monitor JPEG → ChokingDetector.process_frame → (alert, small info dict)."""
    import cv2
    import numpy as np

    if not jpeg_bytes or len(jpeg_bytes) < 80:
        return False, {}

    arr = np.frombuffer(jpeg_bytes, dtype=np.uint8)
    frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if frame is None:
        return False, {}

    # Dash JPEGs are often small / compressed; Pose Landmarker does better when upscaled modestly.
    h, w = frame.shape[:2]
    longest = max(h, w)
    if longest < 640:
        scale = 720.0 / float(longest)
        frame = cv2.resize(
            frame,
            (int(w * scale), int(h * scale)),
            interpolation=cv2.INTER_LINEAR,
        )

    key = (user_id, room_label)
    n = _frame_counter.get(key, 0) + 1
    _frame_counter[key] = n
    if n % EVERY_N_FRAMES != 0:
        return False, {"skipped_throttle": True}

    mod = _load_run_module()
    ChokingDetector = mod.ChokingDetector

    with _cache_lock:
        det = _detector_cache.get(key)
        if det is None:
            det = ChokingDetector()
            _detector_cache[key] = det

    _annotated, alert, info = det.process_frame(frame)

    payload: dict = {}
    if isinstance(info, dict):
        payload["window_ratio"] = info.get("window_ratio")
        payload["score"] = info.get("score")
        payload["pose_detected"] = info.get("pose_detected")
        payload["baseline_ready"] = info.get("baseline_ready")
        sig = info.get("signals")
        if isinstance(sig, dict):
            payload["signals"] = {str(k): bool(v) for k, v in sig.items()}
    payload["alert"] = bool(alert)

    return bool(alert), payload
