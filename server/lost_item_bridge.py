"""
Lost item detection on dashboard JPEG uploads (`/api/laptop-monitor`).

Uses `lost item/best(2).pt` with the same settings as `lost item/test.py`
(conf=0.30, imgsz=640). Standalone test.py is NOT imported.
"""

from __future__ import annotations

import pathlib
import threading
from typing import List, Optional, Tuple

_BEST_PT = (
    pathlib.Path(__file__).resolve().parent / "lost item" / "best(2).pt"
)

_CONF = 0.75
_IMGSZ = 640

_model_lock = threading.Lock()
_model = None


def _ensure_model():
    global _model
    if _model is not None:
        return _model
    if not _BEST_PT.is_file():
        raise FileNotFoundError(f"Missing lost-item weights: {_BEST_PT}")
    from ultralytics import YOLO

    with _model_lock:
        if _model is None:
            _model = YOLO(str(_BEST_PT), task="detect")
            print(f"[LOST-ITEM-BRIDGE] model loaded from {_BEST_PT}")
    return _model


def preload() -> None:
    _ensure_model()


def detect(jpeg_bytes: bytes) -> Tuple[List[dict], Optional["object"]]:
    """
    Run inference on a JPEG frame.
    Returns (detections, bgr_frame). Each detection:
      { "class": str, "confidence": float, "bbox": [x1, y1, x2, y2] }
    """
    import cv2
    import numpy as np

    if not jpeg_bytes or len(jpeg_bytes) < 80:
        return [], None

    arr = np.frombuffer(jpeg_bytes, dtype=np.uint8)
    frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if frame is None:
        return [], None

    model = _ensure_model()
    results = model.predict(
        source=frame,
        conf=_CONF,
        imgsz=_IMGSZ,
        verbose=False,
        device="cpu",
    )

    detections: List[dict] = []
    for result in results:
        boxes = getattr(result, "boxes", None)
        if boxes is None:
            continue
        names = result.names or {}
        for box in boxes:
            try:
                cls_id = int(box.cls[0])
                conf_val = float(box.conf[0])
                cls_name = str(names.get(cls_id, cls_id))
                x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
            except Exception:
                continue
            detections.append(
                {
                    "class": cls_name,
                    "confidence": round(conf_val, 3),
                    "bbox": [x1, y1, x2, y2],
                }
            )

    return detections, frame
