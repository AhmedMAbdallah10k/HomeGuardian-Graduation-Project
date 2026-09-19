"""
Sharp-objects detection for the laptop-monitor stream — NANNY MODE ONLY.

Uses the same trained weights as `Sharp Objects/app.py` (best.pt) with the same
inference parameters (conf=0.75, iou=0.45, imgsz=320, CPU). The standalone app.py
runs an unguarded webcam/imshow loop at import time, so it is NOT imported here;
this bridge loads the identical weights file instead and leaves app.py unchanged.
"""

from __future__ import annotations

import pathlib
import threading
from typing import Tuple

_BEST_PT = (
    pathlib.Path(__file__).resolve().parent
    / "Sharp Objects"
    / "best.pt"
)

# Mirror Sharp Objects/app.py exactly.
_CONF = 0.75
_IOU = 0.45
_IMGSZ = 320

_model_lock = threading.Lock()
_model = None


def _ensure_model():
    global _model
    if _model is not None:
        return _model
    if not _BEST_PT.is_file():
        raise FileNotFoundError(f"Missing sharp-objects weights: {_BEST_PT}")
    from ultralytics import YOLO

    with _model_lock:
        if _model is None:
            m = YOLO(str(_BEST_PT))
            m.fuse()
            _model = m
    return _model


def preload() -> None:
    """Optional startup warmup so the first nanny-mode frame isn't slow."""
    _ensure_model()


def process_upload_jpeg(jpeg_bytes: bytes) -> Tuple[bool, dict]:
    """Decode a laptop-monitor JPEG and return (sharp_present, info)."""
    import cv2
    import numpy as np

    if not jpeg_bytes or len(jpeg_bytes) < 80:
        return False, {}

    arr = np.frombuffer(jpeg_bytes, dtype=np.uint8)
    frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if frame is None:
        return False, {}

    model = _ensure_model()
    results = model.predict(
        source=frame,
        conf=_CONF,
        iou=_IOU,
        imgsz=_IMGSZ,
        verbose=False,
        device="cpu",
    )

    max_conf = 0.0
    count = 0
    for result in results:
        boxes = getattr(result, "boxes", None)
        if boxes is None:
            continue
        for box in boxes:
            count += 1
            try:
                c = float(box.conf[0])
            except Exception:
                c = 0.0
            if c > max_conf:
                max_conf = c

    sharp_present = count > 0
    info = {"confidence": round(max_conf, 3), "detection_count": count}
    return sharp_present, info
