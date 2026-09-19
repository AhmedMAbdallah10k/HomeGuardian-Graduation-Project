import cv2
import time
import math
import numpy as np
from ultralytics import YOLO
from pathlib import Path
from typing import Dict, List, Optional, Any
from base_ai_service import BaseAIService

class StillnessDetectionService(BaseAIService):
    """Service for detecting prolonged stillness (e.g. falls or unresponsiveness) using YOLO tracking"""
    
    def __init__(self, model_path: Optional[str] = None, tracker_config: Optional[str] = None):
        """Initialize the stillness detection service with YOLO model and tracker"""
        SCRIPT_DIR = Path(__file__).parent
        
        if model_path is None:
            # Using yolov8s.pt as specified in the original script
            model_path = str(SCRIPT_DIR / "models" / "yolov8s.pt")
        
        if tracker_config is None:
            tracker_config = str(SCRIPT_DIR / "models" / "bytetrack.yaml")
            
        self.model = None
        try:
            if Path(model_path).exists():
                self.model = YOLO(model_path)
                print(f"Stillness Detection: Model loaded from {model_path}")
            else:
                print(f"Stillness Detection Error: Model not found at {model_path}")
        except Exception as e:
            print(f"Stillness Detection Error loading model: {e}")

        self.tracker_config = tracker_config
        if not Path(self.tracker_config).exists():
            print(f"Stillness Detection Warning: Tracker config not found at {self.tracker_config}")

        # Thresholds - Refined for better movement detection
        self.movement_threshold = 20  # pixels (back to original, more sensitive)
        self.still_time_threshold = 20  # seconds
        self.max_still_time = 300  # 5 minutes - after this, we assume it's a static object (like a chair)
        
        # State tracking: user_id -> {room_name -> {track_id -> {"anchor_center": (x,y), "still_start_time": float}}}
        self.user_states = {}

    def detect(self, image_bytes: bytes, **kwargs) -> Dict[str, Any]:
        """Implementation of BaseAIService.detect"""
        user_id = kwargs.get("user_id", 0)
        room_name = kwargs.get("room_name", "Unknown")
        
        if self.model is None:
            return {"success": False, "error": "Model not loaded"}

        try:
            nparr = np.frombuffer(image_bytes, np.uint8)
            frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            if frame is None:
                return {"success": False, "error": "Failed to decode image"}

            # Initialize user/room state if not exists
            if user_id not in self.user_states:
                self.user_states[user_id] = {}
            if room_name not in self.user_states[user_id]:
                self.user_states[user_id][room_name] = {}
            
            person_states = self.user_states[user_id][room_name]

            # Run tracking (classes=[0] for person)
            results = self.model.track(
                frame,
                persist=True,
                tracker=self.tracker_config,
                classes=[0],
                conf=0.5, # Increased back to 0.5 to reduce ghost detections of static objects
                iou=0.5,
                verbose=False
            )

            active_ids = set()
            stillness_detected = False
            max_elapsed = 0.0

            if len(results) > 0 and results[0].boxes is not None and results[0].boxes.id is not None:
                for box, track_id in zip(results[0].boxes, results[0].boxes.id.int().cpu().tolist()):
                    active_ids.add(track_id)
                    x1, y1, x2, y2 = map(int, box.xyxy[0])
                    cx, cy = int((x1 + x2) / 2), int((y1 + y2) / 2)
                    center = (cx, cy)

                    if track_id not in person_states:
                        person_states[track_id] = {
                            "anchor_center": center,
                            "prev_center": center,
                            "still_start_time": time.time(),
                            "total_movement": 0.0
                        }
                        print(f"[DEBUG STILLNESS] Person {track_id} first seen at {room_name}")

                    state = person_states[track_id]
                    anchor_center = state["anchor_center"]
                    still_start_time = state["still_start_time"]
                    
                    # Calculate distance from the ANCHOR
                    dist_from_anchor = math.sqrt((center[0] - anchor_center[0])**2 + (center[1] - anchor_center[1])**2)
                    
                    # Also calculate distance from PREVIOUS frame
                    prev_center = state.get("prev_center", center)
                    dist_from_prev = math.sqrt((center[0] - prev_center[0])**2 + (center[1] - prev_center[1])**2)
                    state["prev_center"] = center
                    state["total_movement"] += dist_from_prev

                    # If moved significantly from anchor OR suddenly from previous frame
                    # We use a lower threshold for frame-to-frame movement to catch slow walking
                    if dist_from_anchor > self.movement_threshold or dist_from_prev > 5.0:
                        # Person is MOVING
                        state["anchor_center"] = center
                        state["still_start_time"] = time.time()
                        state["total_movement"] = 0.0
                    else:
                        # Person is STILL
                        elapsed = time.time() - still_start_time
                        
                        # Filter out static objects (chairs, etc.)
                        # Real humans always have some microscopic movement (pixel jitter)
                        # If total movement over 20 seconds is exactly 0 or extremely low, it's a ghost.
                        if elapsed > 10 and state["total_movement"] < 1.0:
                            # Likely a chair or static object
                            continue

                        if elapsed > self.max_still_time:
                            state["anchor_center"] = center
                            state["still_start_time"] = time.time()
                            state["total_movement"] = 0.0
                            elapsed = 0

                        if int(elapsed) % 5 == 0 and elapsed > 0:
                             print(f"[DEBUG STILLNESS] Person {track_id} still for {round(elapsed, 1)}s at {room_name}")

                        if elapsed > self.still_time_threshold:
                            stillness_detected = True
                            max_elapsed = max(max_elapsed, elapsed)

            # Cleanup gone IDs
            for gone_id in list(person_states.keys()):
                if gone_id not in active_ids:
                    del person_states[gone_id]

            return {
                "success": True,
                "event_detected": stillness_detected,
                "elapsed_time": round(max_elapsed, 1),
                "type": "stillness"
            }

        except Exception as e:
            print(f"Stillness Detection Error: {e}")
            return {"success": False, "error": str(e)}

# Global instance
_stillness_service: Optional[StillnessDetectionService] = None

def get_stillness_detection_service() -> StillnessDetectionService:
    global _stillness_service
    if _stillness_service is None:
        _stillness_service = StillnessDetectionService()
    return _stillness_service
