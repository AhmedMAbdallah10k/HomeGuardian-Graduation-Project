from ultralytics import YOLO
from pathlib import Path
from typing import Dict, List, Optional, Any
import numpy as np
import cv2
from base_ai_service import BaseAIService

class WindowDetectionService(BaseAIService):
    """Service for window state detection (open/closed) using YOLO model"""
    
    def __init__(self, model_path: Optional[str] = None):
        """Initialize the window detection service with YOLO model"""
        if model_path is None:
            # We assume the model will be placed in server/models/window_best.pt
            SCRIPT_DIR = Path(__file__).parent
            model_path = str(SCRIPT_DIR / "models" / "window_best.pt")
        
        path = Path(model_path)
        
        if not path.exists():
            print(f"Error: Window model path does not exist: {model_path}")
            self.model = None
            return

        try:
            self.model = YOLO(model_path)
            print(f"Window Detection model loaded successfully from {model_path}")
        except Exception as e:
            print(f"Error loading Window Detection model: {e}")
            self.model = None
        
        # Confidence threshold for detection
        # Lowered to 0.4 to improve sensitivity for sliding and casement windows
        self.confidence_threshold = 0.4
    
    def detect(self, image_bytes: bytes, **kwargs) -> Dict[str, Any]:
        """Implementation of BaseAIService.detect"""
        result = self.detect_state(image_bytes)
        return {
            "success": result.get("success", False),
            "event_detected": result.get("window_open_detected", False),
            "detections": result.get("detections", []),
            "type": "window"
        }

    def detect_state(self, image_bytes: bytes) -> Dict:
        """
        Detect window states from image bytes
        """
        if self.model is None:
            return {"success": False, "error": "Model not loaded"}
            
        try:
            # Convert bytes to numpy array
            nparr = np.frombuffer(image_bytes, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if img is None:
                return {"success": False, "error": "Failed to decode image"}
            
            # Run inference
            results = self.model(img, conf=self.confidence_threshold, verbose=False)
            
            # Process results
            detections = []
            window_open_detected = False
            
            for result in results:
                boxes = result.boxes
                if boxes is not None and len(boxes) > 0:
                    for box in boxes:
                        cls = int(box.cls[0])
                        conf = float(box.conf[0])
                        class_name = result.names[cls]
                        
                        # We trigger an event if "open" is in the class name
                        if "open" in class_name.lower():
                            window_open_detected = True
                        
                        # Get bounding box coordinates
                        x1, y1, x2, y2 = box.xyxy[0].tolist()
                        
                        detections.append({
                            "class": class_name,
                            "confidence": round(conf, 3),
                            "bbox": {
                                "x1": round(x1, 2),
                                "y1": round(y1, 2),
                                "x2": round(x2, 2),
                                "y2": round(y2, 2)
                            }
                        })
            
            return {
                "success": True,
                "window_open_detected": window_open_detected,
                "detections": detections,
                "detection_count": len(detections)
            }
            
        except Exception as e:
            return {"success": False, "error": str(e)}

# Global instance
_window_detection_service: Optional[WindowDetectionService] = None

def get_window_detection_service() -> WindowDetectionService:
    """Get or create the global window detection service instance"""
    global _window_detection_service
    if _window_detection_service is None:
        _window_detection_service = WindowDetectionService()
    return _window_detection_service
