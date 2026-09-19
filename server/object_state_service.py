from ultralytics import YOLO
from pathlib import Path
from typing import Dict, List, Optional, Any
import numpy as np
import cv2
from base_ai_service import BaseAIService

class ObjectStateService(BaseAIService):
    """Service for object state detection (e.g. door open/close) using YOLO model"""
    
    def __init__(self, model_path: Optional[str] = None):
        """Initialize the object state service with YOLO model from home folder"""
        if model_path is None:
            SCRIPT_DIR = Path(__file__).parent
            # Use the correct model from the home folder
            model_path = str(SCRIPT_DIR / "home" / "Object_State_Detection_Model.pt")
        
        path = Path(model_path)
        
        if not path.exists():
            print(f"Error: Model path does not exist: {model_path}")
            self.model = None
            return

        try:
            if path.is_file():
                self.model = YOLO(model_path)
                print(f"Object State model loaded successfully from {model_path}")
            else:
                print(f"Error: {model_path} is not a valid file (likely a directory).")
                self.model = None
        except Exception as e:
            print(f"Error loading Object State model: {e}")
            self.model = None
        
        # Confidence threshold for door detection
        self.confidence_threshold = 0.75
    
    def detect(self, image_bytes: bytes, **kwargs) -> Dict[str, Any]:
        """Implementation of BaseAIService.detect"""
        result = self.detect_state(image_bytes)
        return {
            "success": result.get("success", False),
            "event_detected": result.get("event_detected", False),
            "detections": result.get("detections", []),
            "type": "door"
        }

    def detect_state(self, image_bytes: bytes) -> Dict:
        """
        Detect object states from image bytes
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
            # Using 0.75 confidence as per the new door_detect.py logic
            results = self.model(img, conf=0.75, verbose=False)
            
            # Process results
            detections = []
            has_event = False
            
            for result in results:
                boxes = result.boxes
                if boxes is not None and len(boxes) > 0:
                    for box in boxes:
                        cls = int(box.cls[0])
                        conf = float(box.conf[0])
                        raw_label = result.names[cls]
                        
                        # Map raw labels to user-friendly strings
                        label = raw_label
                        if "door_opened" in raw_label.lower() or "opened" in raw_label.lower():
                            label = "opened"
                        elif "door_closed" in raw_label.lower() or "closed" in raw_label.lower():
                            label = "closed"
                        elif "semi" in raw_label.lower():
                            label = "semi opened"
                        
                        # We consider "opened" a security event for HomeAlone mode
                        if label == "opened":
                            has_event = True
                        
                        # Get bounding box coordinates
                        x1, y1, x2, y2 = box.xyxy[0].tolist()
                        
                        detections.append({
                            "class": label,
                            "raw_class": raw_label,
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
                "event_detected": has_event,
                "detections": detections,
                "detection_count": len(detections)
            }
            
        except Exception as e:
            return {"success": False, "error": str(e)}

# Global instance
_object_state_service: Optional[ObjectStateService] = None

def get_object_state_service() -> ObjectStateService:
    """Get or create the global object state service instance"""
    global _object_state_service
    if _object_state_service is None:
        _object_state_service = ObjectStateService()
    return _object_state_service
