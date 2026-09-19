import cv2
import time
import numpy as np
from ultralytics import YOLO
from pathlib import Path
from typing import Dict, List, Optional, Any
from base_ai_service import BaseAIService
import os

# Same folder / weights as demo `MODES/Pet Mode/Pets And Unkown Animals/V1.py` — V1.py is not imported; logic aligned here.
_PET_V1_DIR = Path(__file__).resolve().parent / "MODES" / "Pet Mode" / "Pets And Unkown Animals"
_YOLOV8S_WEIGHTS = _PET_V1_DIR / "yolov8s.pt"


class PetDetectionService(BaseAIService):
    """YOLOv8-small COCO pet/animal tray (V1-aligned) + DB photo matching for known vs unknown."""

    def __init__(self, model_path: Optional[str] = None):
        """Load yolov8s.pt from Pets And Unkown Animals if present; else Ultralytics hub name yolov8s.pt."""
        self.model = None

        resolved: Optional[str] = None
        if model_path is not None:
            resolved = str(model_path)
        elif _YOLOV8S_WEIGHTS.is_file():
            resolved = str(_YOLOV8S_WEIGHTS)
            print(f"Pet Detection: using bundled weights {_YOLOV8S_WEIGHTS}")
        else:
            # Matches V1.py string; Ultralytics downloads/caches on first use
            resolved = "yolov8s.pt"
            print(
                f"Pet Detection: {_YOLOV8S_WEIGHTS} not found — loading 'yolov8s.pt' from Ultralytics "
                f"(save a copy next to V1.py for offline use)."
            )

        try:
            self.model = YOLO(resolved)
            print(f"Pet Detection: YOLO model ready ({resolved})")
        except Exception as e:
            print(f"Pet Detection Error loading model: {e}")

        # COCO class ids — same mapping as MODES/Pet Mode/Pets And Unkown Animals/V1.py
        self.ANIMAL_CLASSES = {
            14: "bird",
            15: "cat",
            16: "dog",
        }
        
        # Thresholds
        self.conf_threshold = 0.4
        
        # In-memory cache for pet reference images: user_id -> {"images": [list of cv2 images], "features": [list of descriptors], "last_loaded": float}
        self.pet_references = {}
        self.orb = cv2.ORB_create(nfeatures=500)
        self.bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)

    def invalidate_user_pet_references(self, user_id: int) -> None:
        """Drop cached reference images so the next frame reloads paths from DB."""
        self.pet_references.pop(int(user_id), None)

    def _load_user_pets(self, user_id: int, cursor):
        """Load registered pet photos for a user from the database"""
        now = time.time()
        if user_id in self.pet_references:
            # Refresh cache every 5 minutes
            if now - self.pet_references[user_id].get("last_loaded", 0) < 300:
                return
            
        self.pet_references[user_id] = {"images": [], "features": [], "last_loaded": now}
        
        # Query for pet photos belonging to this user
        cursor.execute("""
            SELECT pp.photo_path 
            FROM pet_photos pp
            JOIN pets p ON pp.pet_id = p.id
            WHERE p.user_id = %s
        """, (user_id,))
        
        rows = cursor.fetchall()
        for row in rows:
            photo_path = row['photo_path']
            if os.path.exists(photo_path):
                img = cv2.imread(photo_path)
                if img is not None:
                    # 1. Store resized image for histogram
                    img_small = cv2.resize(img, (128, 128))
                    self.pet_references[user_id]["images"].append(img_small)
                    
                    # 2. Extract ORB features for pattern matching
                    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
                    kp, des = self.orb.detectAndCompute(gray, None)
                    if des is not None:
                        self.pet_references[user_id]["features"].append(des)
        
        print(f"[DEBUG PET] Loaded {len(self.pet_references[user_id]['images'])} reference photos for user {user_id}")

    def _is_known_pet(self, detected_pet_img, user_id: int) -> bool:
        """Compare detected pet against registered pet photos using multi-modal comparison"""
        if user_id not in self.pet_references or not self.pet_references[user_id]["images"]:
            return False
            
        # --- 1. Histogram Comparison (Color) ---
        # Use HSV color space for better color-based matching (less sensitive to lighting)
        detected_pet_hsv = cv2.cvtColor(detected_pet_img, cv2.COLOR_BGR2HSV)
        h_detected = cv2.calcHist([detected_pet_hsv], [0, 1], None, [180, 256], [0, 180, 0, 256])
        cv2.normalize(h_detected, h_detected, 0, 1, cv2.NORM_MINMAX)
        
        max_hist_score = 0
        for ref_img in self.pet_references[user_id]["images"]:
            ref_hsv = cv2.cvtColor(ref_img, cv2.COLOR_BGR2HSV)
            h_ref = cv2.calcHist([ref_hsv], [0, 1], None, [180, 256], [0, 180, 0, 256])
            cv2.normalize(h_ref, h_ref, 0, 1, cv2.NORM_MINMAX)
            
            score = cv2.compareHist(h_detected, h_ref, cv2.HISTCMP_CORREL)
            max_hist_score = max(max_hist_score, score)
            
        # --- 2. Feature Matching (Patterns) ---
        max_feature_matches = 0
        try:
            gray_detected = cv2.cvtColor(detected_pet_img, cv2.COLOR_BGR2GRAY)
            kp_det, des_det = self.orb.detectAndCompute(gray_detected, None)
            
            if des_det is not None:
                for ref_des in self.pet_references[user_id]["features"]:
                    matches = self.bf.match(des_det, ref_des)
                    # Filter good matches
                    good_matches = [m for m in matches if m.distance < 50]
                    max_feature_matches = max(max_feature_matches, len(good_matches))
        except Exception as e:
            print(f"[DEBUG PET] Feature matching error: {e}")

        # --- 3. Decision Logic ---
        # Combined score: Histogram is good for overall color, ORB is good for textures/patterns.
        # We lower the thresholds slightly to be more inclusive of the user's pet.
        
        # Match if:
        # - Histogram correlation is high (> 0.35)
        # - OR Histogram is decent (> 0.15) AND we have some pattern matches (> 2)
        # - OR Pattern matches are high (> 7)
        
        is_known = (max_hist_score > 0.35) or \
                   (max_hist_score > 0.15 and max_feature_matches > 2) or \
                   (max_feature_matches > 7)
        
        print(f"[DEBUG PET] Comparison for user {user_id}: Hist={round(max_hist_score, 2)}, Matches={max_feature_matches} -> Known={is_known}")
        
        return is_known

    def detect(self, image_bytes: bytes, **kwargs) -> Dict[str, Any]:
        """Implementation of BaseAIService.detect"""
        user_id = kwargs.get("user_id", 0)
        cursor = kwargs.get("cursor", None)
        
        if self.model is None:
            return {"success": False, "error": "Model not loaded"}

        try:
            nparr = np.frombuffer(image_bytes, np.uint8)
            frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            if frame is None:
                return {"success": False, "error": "Failed to decode image"}

            # Load user pets if we have a database cursor
            if cursor and user_id > 0:
                self._load_user_pets(user_id, cursor)

            # Run detection
            results = self.model(frame, verbose=False)
            detections = results[0]
            
            pet_detected = False
            unknown_pet_detected = False
            detected_animals = []
            
            for box in detections.boxes:
                cls_id = int(box.cls[0])
                conf = float(box.conf[0])
                
                if cls_id in self.ANIMAL_CLASSES and conf >= self.conf_threshold:
                    pet_detected = True
                    x1, y1, x2, y2 = map(int, box.xyxy[0])
                    
                    # Extract pet image for identification
                    pet_img = frame[max(0, y1):min(frame.shape[0], y2), max(0, x1):min(frame.shape[1], x2)]
                    
                    is_known = False
                    if user_id > 0:
                        is_known = self._is_known_pet(pet_img, user_id)
                    
                    if not is_known:
                        unknown_pet_detected = True
                        
                    detected_animals.append({
                        "type": self.ANIMAL_CLASSES[cls_id],
                        "confidence": conf,
                        "is_known": is_known,
                        "box": [x1, y1, x2, y2]
                    })

            return {
                "success": True,
                "event_detected": unknown_pet_detected,
                "pet_detected": pet_detected,
                "unknown_pet_detected": unknown_pet_detected,
                "detections": detected_animals
            }

        except Exception as e:
            print(f"Pet Detection Error during processing: {e}")
            return {"success": False, "error": str(e)}

# Singleton instance getter
_pet_service = None
def get_pet_detection_service():
    global _pet_service
    if _pet_service is None:
        _pet_service = PetDetectionService()
    return _pet_service
