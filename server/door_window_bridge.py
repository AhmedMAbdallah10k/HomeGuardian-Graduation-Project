"""
Door / Window OPEN detection for the laptop-monitor stream — HOME ALONE MODE ONLY.

Uses the same trained weights as `Setting_model/realtime_test.py` (best.pt) with the
same inference parameters (conf=0.50, iou=0.60). That script runs an argparse + webcam
loop, so it is NOT imported here; this bridge loads the identical weights file instead
and leaves realtime_test.py unchanged.

Only the OPEN classes raise an event:
    door_opened   -> door_open = True
    window_opened -> window_open = True
Closed classes are ignored (never alert).
"""

from __future__ import annotations

import pathlib
import threading
from typing import Tuple

_BEST_PT = pathlib.Path(__file__).resolve().parent / "Setting_model" / "best.pt"

# Mirror Setting_model/realtime_test.py.
_CONF = 0.50
_IOU = 0.60

_model_lock = threading.Lock()
_model = None


def _ensure_model():
    global _model
    if _model is not None:
        return _model
    if not _BEST_PT.is_file():
        raise FileNotFoundError(f"Missing door/window weights: {_BEST_PT}")
    from ultralytics import YOLO

    with _model_lock:
        if _model is None:
            m = YOLO(str(_BEST_PT))
            m.fuse()
            _model = m
    return _model


def preload() -> None:
    """Optional startup warmup so the first Home-Alone frame isn't slow."""
    _ensure_model()


def process_upload_jpeg(jpeg_bytes: bytes) -> Tuple[bool, bool, dict]:
    """Decode a laptop-monitor JPEG and return (door_open, window_open, info)."""
    import cv2
    import numpy as np

    if not jpeg_bytes or len(jpeg_bytes) < 80:
        return False, False, {"door_detections": [], "window_detections": []}

    arr = np.frombuffer(jpeg_bytes, dtype=np.uint8)
    frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if frame is None:
        return False, False, {"door_detections": [], "window_detections": []}

    model = _ensure_model()
    results = model.predict(
        source=frame,
        conf=_CONF,
        iou=_IOU,
        verbose=False,
        device="cpu",
    )

    door_open = False
    window_open = False
    door_detections: list[dict] = []
    window_detections: list[dict] = []

    for result in results:
        boxes = getattr(result, "boxes", None)
        if boxes is None:
            continue
        names = getattr(result, "names", {}) or {}
        for box in boxes:
            try:
                cls_id = int(box.cls[0])
                conf = float(box.conf[0])
            except Exception:
                continue
            raw = str(names.get(cls_id, "")).lower()
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            det = {
                "class": raw,
                "confidence": round(conf, 3),
                "bbox": {
                    "x1": round(x1, 2),
                    "y1": round(y1, 2),
                    "x2": round(x2, 2),
                    "y2": round(y2, 2),
                },
            }
            # Only OPEN classes raise events.
            if "door" in raw and "open" in raw:
                door_open = True
                door_detections.append(det)
            elif "window" in raw and "open" in raw:
                window_open = True
                window_detections.append(det)

    info = {"door_detections": door_detections, "window_detections": window_detections}
    return door_open, window_open, info
