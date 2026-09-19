"""
Loads `MODES/Default  Mode/Food Left Out/Food Left Out/app.py` via importlib and
reuses its CONFIG + FoodTracker WITHOUT running the demo's OpenCV webcam / imshow loop.

Food-left-out runs on every laptop-monitor JPEG regardless of the room's modes
(always-on, like fire), feeding frames into a per-(user, room) FoodTracker so the
30-second "left out" timer is independent per room.
"""

from __future__ import annotations

import importlib.util
import pathlib
import threading
from typing import Any, Dict, Tuple

_APP_PATH = (
    pathlib.Path(__file__).resolve().parent
    / "MODES"
    / "Default  Mode"
    / "Food Left Out"
    / "Food Left Out"
    / "app.py"
)

_module_lock = threading.Lock()
_cached_module = None

# Heavy YOLO models — loaded once, shared across all users/rooms.
_models_lock = threading.Lock()
_coco_model = None
_custom_model = None

_tracker_lock = threading.Lock()
_tracker_cache: Dict[Tuple[int, str], Any] = {}
_frame_counter: Dict[Tuple[int, str], int] = {}

# A sustained 30s timer doesn't need every frame; lighten the two-model load.
EVERY_N_FRAMES = 3


def _load_app_module():
    """Dynamic import of the unmodified app.py (CONFIG, COCO_FOOD_CLASSES, FoodTracker)."""
    global _cached_module
    if _cached_module is not None:
        return _cached_module
    if not _APP_PATH.is_file():
        raise FileNotFoundError(f"Missing food module: {_APP_PATH}")
    with _module_lock:
        if _cached_module is None:
            spec = importlib.util.spec_from_file_location("_hg_food_app_impl", _APP_PATH)
            mod = importlib.util.module_from_spec(spec)
            assert spec.loader is not None
            spec.loader.exec_module(mod)
            _cached_module = mod
    return _cached_module


def _ensure_models():
    """Load both YOLO models once, mirroring app.py's run(): COCO yolov8m + custom best.pt."""
    global _coco_model, _custom_model
    if _coco_model is not None and _custom_model is not None:
        return _coco_model, _custom_model
    from ultralytics import YOLO

    mod = _load_app_module()
    with _models_lock:
        if _coco_model is None:
            _coco_model = YOLO("yolov8m.pt")
        if _custom_model is None:
            custom_path = mod._resolve_model_path(mod.CONFIG["CUSTOM_MODEL_PATH"])
            _custom_model = YOLO(custom_path, task="detect")
    return _coco_model, _custom_model


def preload() -> None:
    """Optional startup warmup so the first monitored frame isn't slow."""
    _load_app_module()
    _ensure_models()


def _food_present_for_frame(frame) -> bool:
    """Run both models with app.py's exact CONFIG thresholds + COCO food-class filter."""
    mod = _load_app_module()
    cfg = mod.CONFIG
    coco_food_classes = mod.COCO_FOOD_CLASSES
    coco_model, custom_model = _ensure_models()

    # COCO model: only the food class IDs in app.py's COCO_FOOD_CLASSES count.
    coco_results = coco_model(frame, verbose=False)[0]
    for box in coco_results.boxes:
        class_id = int(box.cls)
        conf = float(box.conf)
        if class_id in coco_food_classes and conf >= cfg["COCO_CONFIDENCE"]:
            return True

    # Custom model: any detection above its confidence threshold counts as food.
    custom_results = custom_model(frame, verbose=False)[0]
    for box in custom_results.boxes:
        conf = float(box.conf)
        if conf >= cfg["CUSTOM_CONFIDENCE"]:
            return True

    return False


def process_upload_jpeg(user_id: int, room_label: str, jpeg_bytes: bytes) -> Tuple[bool, dict]:
    """Decode laptop-monitor JPEG → both models → FoodTracker.update → (alert, info)."""
    import cv2
    import numpy as np

    if not jpeg_bytes or len(jpeg_bytes) < 80:
        return False, {}

    key = (user_id, room_label)
    n = _frame_counter.get(key, 0) + 1
    _frame_counter[key] = n
    if n % EVERY_N_FRAMES != 0:
        return False, {"skipped_throttle": True}

    arr = np.frombuffer(jpeg_bytes, dtype=np.uint8)
    frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if frame is None:
        return False, {}

    food_present = _food_present_for_frame(frame)

    mod = _load_app_module()
    with _tracker_lock:
        tracker = _tracker_cache.get(key)
        if tracker is None:
            tracker = mod.FoodTracker()
            _tracker_cache[key] = tracker

    elapsed, alert_fired = tracker.update(food_present)

    info = {
        "elapsed_seconds": round(float(elapsed), 1),
        "food_present": bool(food_present),
        "alert": bool(alert_fired),
    }
    return bool(alert_fired), info
