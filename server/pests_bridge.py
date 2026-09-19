"""
Pest & wildlife detection on dashboard JPEG uploads (`/api/laptop-monitor`).

Uses the same weights and inference settings as `pests/pests/realtime_detector.py`
(conf=0.80, iou=0.45, imgsz=960, classes Insect/Lizard/Rodent). Runs on every
monitored room in all modes (Silver, Nanny, Nurse, Pet, Home alone). The standalone
realtime_detector.py is NOT imported or modified — only best.pt is loaded here.
"""

from __future__ import annotations

import pathlib
import threading
from typing import Tuple

_BEST_PT = (
    pathlib.Path(__file__).resolve().parent / "pests" / "pests" / "best.pt"
)

# Mirror realtime_detector.py defaults exactly.
_CONF = 0.80
_IOU = 0.45
_IMGSZ = 960

_model_lock = threading.Lock()
_model = None


def _ensure_model():
    global _model
    if _model is not None:
        return _model
    if not _BEST_PT.is_file():
        raise FileNotFoundError(f"Missing pest detector weights: {_BEST_PT}")
    from ultralytics import YOLO

    with _model_lock:
        if _model is None:
            _model = YOLO(str(_BEST_PT))
            print(f"[PESTS-BRIDGE] model loaded from {_BEST_PT}")
    return _model


def preload() -> None:
    _ensure_model()


def process_upload_jpeg(jpeg_bytes: bytes) -> Tuple[bool, dict]:
    """Decode laptop-monitor JPEG; return (pest_detected, info)."""
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

    detections = []
    max_conf = 0.0
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
            except Exception:
                continue
            if conf_val > max_conf:
                max_conf = conf_val
            detections.append({"class": cls_name, "confidence": round(conf_val, 3)})

    pest_detected = len(detections) > 0
    labels = sorted({d["class"] for d in detections})
    info = {
        "confidence": round(max_conf, 3),
        "detection_count": len(detections),
        "detections": detections,
        "labels": labels,
    }
    return pest_detected, info
