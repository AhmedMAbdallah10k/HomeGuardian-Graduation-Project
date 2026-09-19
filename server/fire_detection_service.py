from ultralytics import YOLO
from pathlib import Path
from typing import Dict, List, Optional, Any
import numpy as np
import cv2
from base_ai_service import BaseAIService

class FireDetectionService(BaseAIService):
    """Service for fire/smoke detection using YOLO model"""
    
    def __init__(self, model_path: Optional[str] = None):
        """Initialize the fire detection service with YOLO model"""
        if model_path is None:
            SCRIPT_DIR = Path(__file__).parent
            model_path = str(SCRIPT_DIR / "models" / "finetuned.pt")
        
        self.model = YOLO(model_path)
        # Threshold for fire/smoke detection
        self.confidence_threshold = 0.75
    
    def detect(self, image_bytes: bytes, **kwargs) -> Dict[str, Any]:
        """Implementation of BaseAIService.detect"""
        result = self.detect_from_image(image_bytes)
        return {
            "success": result.get("success", False),
            "event_detected": result.get("fire_detected", False),
            "detections": result.get("detections", []),
            "confidence": result.get("confidence", 0.0),
            "type": "fire"
        }

    def detect_from_image(self, image_bytes: bytes) -> Dict:
        """
        Detect fire/smoke from image bytes
        
        Args:
            image_bytes: Image file as bytes
            
        Returns:
            Dictionary with detection results
        """
        try:
            # Convert bytes to numpy array
            nparr = np.frombuffer(image_bytes, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if img is None:
                return {
                    "success": False,
                    "error": "Failed to decode image"
                }
            
            # Run inference
            results = self.model(img, conf=self.confidence_threshold, verbose=False)
            
            # Process results
            detections = []
            fire_detected = False
            max_confidence = 0.0
            
            for result in results:
                boxes = result.boxes
                if boxes is not None and len(boxes) > 0:
                    for box in boxes:
                        cls = int(box.cls[0])
                        conf = float(box.conf[0])
                        class_name = result.names[cls]
                        
                        # Check if it's fire or smoke
                        if 'fire' in class_name.lower() or 'smoke' in class_name.lower():
                            fire_detected = True
                            max_confidence = max(max_confidence, conf)
                            
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
                "fire_detected": fire_detected,
                "confidence": round(max_confidence, 3) if fire_detected else 0.0,
                "detections": detections,
                "detection_count": len(detections)
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": str(e)
            }
    
    def detect_from_video_frame(self, frame: np.ndarray) -> Dict:
        """
        Detect fire/smoke from a video frame (numpy array)
        
        Args:
            frame: Video frame as numpy array
            
        Returns:
            Dictionary with detection results
        """
        try:
            # Run inference
            results = self.model(frame, conf=self.confidence_threshold, verbose=False)
            
            # Process results (same as image detection)
            detections = []
            fire_detected = False
            max_confidence = 0.0
            
            for result in results:
                boxes = result.boxes
                if boxes is not None and len(boxes) > 0:
                    for box in boxes:
                        cls = int(box.cls[0])
                        conf = float(box.conf[0])
                        class_name = result.names[cls]
                        
                        if 'fire' in class_name.lower() or 'smoke' in class_name.lower():
                            fire_detected = True
                            max_confidence = max(max_confidence, conf)
                            
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
                "fire_detected": fire_detected,
                "confidence": round(max_confidence, 3) if fire_detected else 0.0,
                "detections": detections,
                "detection_count": len(detections)
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": str(e)
            }

# Global instance (loaded once at startup)
_fire_detection_service: Optional[FireDetectionService] = None

def get_fire_detection_service() -> FireDetectionService:
    """Get or create the global fire detection service instance"""
    global _fire_detection_service
    if _fire_detection_service is None:
        _fire_detection_service = FireDetectionService()
    return _fire_detection_service

