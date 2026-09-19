from ultralytics import YOLO
from pathlib import Path
from typing import Dict, List, Optional, Any
import numpy as np
import cv2
from base_ai_service import BaseAIService

class SharpObjectDetectionService(BaseAIService):
    """Service for sharp object detection using YOLO model"""
    
    def __init__(self, model_path: Optional[str] = None):
        """Initialize the sharp object detection service with YOLO model"""
        if model_path is None:
            SCRIPT_DIR = Path(__file__).parent
            model_path = str(SCRIPT_DIR / "models" / "sharp_objects.pt")
        
        path = Path(model_path)
        
        if not path.exists():
            print(f"Error: Sharp Object model path does not exist: {model_path}")
            self.model = None
            return

        try:
            self.model = YOLO(model_path)
            # model.fuse() # Optional optimization
            print(f"Sharp Object Detection model loaded successfully from {model_path}")
        except Exception as e:
            print(f"Error loading Sharp Object Detection model: {e}")
            self.model = None
        
        # Confidence threshold for detection (increased from 0.25 to 0.65 to reduce false positives)
        self.confidence_threshold = 0.65
        self.iou_threshold = 0.45
        self.min_size = 40  # Minimum width/height in pixels
    
    def detect(self, image_bytes: bytes, **kwargs) -> Dict[str, Any]:
        """Implementation of BaseAIService.detect"""
        result = self.detect_objects(image_bytes)
        return {
            "success": result.get("success", False),
            "event_detected": result.get("sharp_object_detected", False),
            "detections": result.get("detections", []),
            "confidence": result.get("confidence", 0.0),
            "type": "sharp_object"
        }

    def detect_objects(self, image_bytes: bytes) -> Dict:
        """
        Detect sharp objects from image bytes
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
            results = self.model.predict(
                source=img,
                conf=self.confidence_threshold,
                iou=self.iou_threshold,
                imgsz=320,
                verbose=False
            )
            
            # Process results
            detections = []
            sharp_object_detected = False
            max_confidence = 0.0
            
            for result in results:
                boxes = result.boxes
                if boxes is not None and len(boxes) > 0:
                    for box in boxes:
                        cls = int(box.cls[0])
                        conf = float(box.conf[0])
                        class_name = result.names[cls]
                        
                        # Get bounding box coordinates
                        x1, y1, x2, y2 = box.xyxy[0].tolist()
                        width = x2 - x1
                        height = y2 - y1
                        
                        # Apply size filter
                        if width < self.min_size or height < self.min_size:
                            continue

                        sharp_object_detected = True
                        max_confidence = max(max_confidence, conf)
                        
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
                "sharp_object_detected": sharp_object_detected,
                "confidence": round(max_confidence, 3) if sharp_object_detected else 0.0,
                "detections": detections,
                "detection_count": len(detections)
            }
            
        except Exception as e:
            return {"success": False, "error": str(e)}

# Global instance
_sharp_object_service: Optional[SharpObjectDetectionService] = None

def get_sharp_object_service() -> SharpObjectDetectionService:
    """Get or create the global sharp object detection service instance"""
    global _sharp_object_service
    if _sharp_object_service is None:
        _sharp_object_service = SharpObjectDetectionService()
    return _sharp_object_service
