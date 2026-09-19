"""
Fridge open/closed detection for `/api/laptop-monitor`.

Uses the trained model in `server/fridge/fridge/` (same as `fridge/fridge/test.py`):
  - weights: best.pt
  - classes: open_fridge, close_fridge
"""

from __future__ import annotations

import time
from pathlib import Path
from typing import Any, Dict, Optional

import cv2
import numpy as np
from ultralytics import YOLO

from base_ai_service import BaseAIService

# Same folder as fridge/fridge/test.py — this is the only fridge model for the app.
_FRIDGE_DIR = Path(__file__).resolve().parent / "fridge" / "fridge"
_MODEL_PATH = _FRIDGE_DIR / "best.pt"

# Match test.py
CONFIDENCE = 0.80
IMGSZ = 640
OPEN_CLASS = "open_fridge"


def _is_open_class(class_name: str) -> bool:
    name = (class_name or "").lower().strip()
    return name == OPEN_CLASS or name == "open" or "open_fridge" in name


class FridgeDetectionService(BaseAIService):
    """Fridge state detection using server/fridge/fridge/best.pt."""

    def __init__(self, model_path: Optional[str] = None) -> None:
        weights = Path(model_path) if model_path else _MODEL_PATH

        if not weights.is_file():
            print(
                "[FRIDGE] Model missing — place best.pt next to fridge/fridge/test.py:\n"
                f"  {_MODEL_PATH.resolve()}"
            )
            self.model = None
            return

        try:
            self.model = YOLO(str(weights.resolve()))
            print(
                f"[FRIDGE] Loaded {weights.name} from {weights.parent} "
                f"(conf={CONFIDENCE}, imgsz={IMGSZ}, classes={getattr(self.model, 'names', {})})"
            )
        except Exception as exc:
            print(f"[FRIDGE] Failed to load {weights}: {exc}")
            self.model = None

        self.confidence_threshold = CONFIDENCE
        self.imgsz = IMGSZ
        self.open_start_times: dict[int, dict[str, float]] = {}
        self.alert_seconds = 10

    def detect(self, image_bytes: bytes, **kwargs) -> Dict[str, Any]:
        user_id = kwargs.get("user_id")
        room_name = kwargs.get("room_name", "Unknown")

        result = self.detect_state(image_bytes)

        fridge_open_detected = bool(result.get("fridge_open_detected", False))
        is_prolonged_open = False
        elapsed_time = 0.0

        if user_id:
            if fridge_open_detected:
                user_states = self.open_start_times.setdefault(user_id, {})
                if room_name not in user_states:
                    user_states[room_name] = time.time()
                elapsed_time = time.time() - user_states[room_name]
                if elapsed_time > self.alert_seconds:
                    is_prolonged_open = True
            elif user_id in self.open_start_times and room_name in self.open_start_times[user_id]:
                del self.open_start_times[user_id][room_name]

        return {
            "success": result.get("success", False),
            "event_detected": fridge_open_detected,
            "is_prolonged_open": is_prolonged_open,
            "elapsed_time": round(elapsed_time, 1),
            "detections": result.get("detections", []),
            "type": "fridge",
        }

    def detect_state(self, image_bytes: bytes) -> Dict[str, Any]:
        if self.model is None:
            return {"success": False, "error": "Fridge model not loaded"}

        try:
            nparr = np.frombuffer(image_bytes, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            if img is None:
                return {"success": False, "error": "Failed to decode image"}

            results = self.model(
                img,
                conf=self.confidence_threshold,
                imgsz=self.imgsz,
                verbose=False,
            )

            detections = []
            fridge_open_detected = False

            for result in results:
                boxes = result.boxes
                if boxes is None or len(boxes) == 0:
                    continue
                for box in boxes:
                    cls = int(box.cls[0])
                    conf = float(box.conf[0])
                    class_name = str(result.names[cls])
                    if _is_open_class(class_name):
                        fridge_open_detected = True

                    x1, y1, x2, y2 = box.xyxy[0].tolist()
                    detections.append(
                        {
                            "class": class_name,
                            "confidence": round(conf, 3),
                            "bbox": {
                                "x1": round(x1, 2),
                                "y1": round(y1, 2),
                                "x2": round(x2, 2),
                                "y2": round(y2, 2),
                            },
                        }
                    )

            return {
                "success": True,
                "fridge_open_detected": fridge_open_detected,
                "detections": detections,
                "detection_count": len(detections),
            }
        except Exception as exc:
            return {"success": False, "error": str(exc)}


_fridge_detection_service: Optional[FridgeDetectionService] = None


def get_fridge_detection_service() -> FridgeDetectionService:
    global _fridge_detection_service
    if _fridge_detection_service is None:
        _fridge_detection_service = FridgeDetectionService()
    return _fridge_detection_service
