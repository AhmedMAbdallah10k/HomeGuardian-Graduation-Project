"""
Pet Station feeder — YOLO cat/dog detection for ESP32-CAM JPEG uploads.

Uses the same weights and heuristics as `pet server/pet_server_v4 (1) (1).py`.
The standalone pet server is NOT imported here; this bridge loads yolov8n.pt locally.
"""

from __future__ import annotations

import pathlib
import threading
from typing import Any, Dict, Tuple

_YOLO_PT = (
    pathlib.Path(__file__).resolve().parent / "pet server" / "yolov8n.pt"
)

TARGET_CLASSES = {15: "cat", 16: "dog"}
CONFIDENCE_THRESHOLD = 0.4
EATING_REGION_BOTTOM = 0.6

_model_lock = threading.Lock()
_model = None


def _ensure_model():
    global _model
    if _model is not None:
        return _model
    if not _YOLO_PT.is_file():
        raise FileNotFoundError(f"Missing pet-station weights: {_YOLO_PT}")
    from ultralytics import YOLO

    with _model_lock:
        if _model is None:
            _model = YOLO(str(_YOLO_PT))
    return _model


def preload() -> None:
    """Optional startup warmup."""
    _ensure_model()


def process_jpeg(jpeg_bytes: bytes) -> Tuple[Dict[str, Any], dict]:
    """
    Decode JPEG, run YOLO, return (verdict, info).

    verdict: {detected, eating, class}
    info: {confidence, frame_height} for logging
    """
    import cv2
    import numpy as np

    empty = {"detected": False, "eating": False, "class": None}
    if not jpeg_bytes or len(jpeg_bytes) < 80:
        return empty, {}

    arr = np.frombuffer(jpeg_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        return empty, {}

    model = _ensure_model()
    results = model(img, verbose=False)[0]

    detected = False
    eating = False
    best_class = None
    best_conf = 0.0

    h = img.shape[0]
    for box in results.boxes:
        cls_id = int(box.cls[0])
        conf = float(box.conf[0])
        if cls_id in TARGET_CLASSES and conf >= CONFIDENCE_THRESHOLD:
            if conf >= best_conf:
                best_conf = conf
                detected = True
                best_class = TARGET_CLASSES[cls_id]
                y_bottom = float(box.xyxy[0][3])
                eating = (y_bottom / h) > EATING_REGION_BOTTOM

    verdict = {"detected": detected, "eating": eating, "class": best_class}
    info = {"confidence": best_conf, "frame_height": h}
    return verdict, info
