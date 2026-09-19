import cv2
import os
import numpy as np
from deepface import DeepFace
from pathlib import Path
from typing import Dict, List, Optional, Any
from base_ai_service import BaseAIService

class FaceRecognitionService(BaseAIService):
    """Service for face recognition using DeepFace based on SFace and SSD"""
    
    def __init__(self, db_path: Optional[str] = None):
        """Initialize the face recognition service.
        `db_path` is the BASE folder; per-user subfolders live at <base>/user_<id>/.
        """
        if db_path is None:
            SCRIPT_DIR = Path(__file__).parent
            db_path = str(SCRIPT_DIR / "known_faces")

        self.base_db_path = db_path
        # Kept for backwards-compat with any external callers that still reference db_path
        self.db_path = db_path
        self.model_name = "SFace"
        self.detector_backend = "ssd"
        self.distance_metric = "cosine"
        self.threshold = 0.7

        # --- Frame Quality Filtering thresholds ---
        # Blur: Laplacian variance. Higher = sharper. Below this = motion blur / out of focus.
        # NOTE: Webcam frames are inherently softer than phone/DSLR (typical range 30-90).
        # Threshold tuned to only reject TRULY blurry frames (motion smear is <20).
        self.blur_threshold = 25.0
        # Brightness: mean grayscale pixel value (0-255). Reject too dark / too bright frames.
        self.brightness_min = 40.0
        self.brightness_max = 220.0
        # Track how often each filter rejects frames (for debug visibility)
        self._reject_counts = {"blur": 0, "dark": 0, "bright": 0, "passed": 0}
        
        if not os.path.exists(self.db_path):
            os.makedirs(self.db_path)
            print(f"[FACE] Created database directory: {self.db_path}")
            
        print(f"[FACE] Service initialized with DB: {self.db_path}")
        print(f"[FACE] Model: {self.model_name}, Detector: {self.detector_backend}")
        print(f"[FACE] Quality filter: blur>={self.blur_threshold}, brightness=[{self.brightness_min},{self.brightness_max}]")

    def _check_frame_quality(self, img: np.ndarray) -> Dict[str, Any]:
        """
        Cheap pre-flight quality check (~1.3ms total) to skip blurry / dark / blown-out frames
        BEFORE running the expensive DeepFace pipeline. Returns:
          { "ok": bool, "reason": str | None, "blur": float, "brightness": float }
        """
        # Convert to grayscale once and reuse for both metrics
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

        # Blur: variance of the Laplacian. Industry-standard sharpness metric.
        blur_score = float(cv2.Laplacian(gray, cv2.CV_64F).var())
        if blur_score < self.blur_threshold:
            return {"ok": False, "reason": "blur", "blur": blur_score, "brightness": float(gray.mean())}

        # Brightness: mean pixel intensity.
        brightness = float(gray.mean())
        if brightness < self.brightness_min:
            return {"ok": False, "reason": "dark", "blur": blur_score, "brightness": brightness}
        if brightness > self.brightness_max:
            return {"ok": False, "reason": "bright", "blur": blur_score, "brightness": brightness}

        return {"ok": True, "reason": None, "blur": blur_score, "brightness": brightness}

    def detect(self, image_bytes: bytes, **kwargs) -> Dict[str, Any]:
        """Standard detect method implementation.
        Accepts optional `user_id` kwarg to scope recognition to that user's known_faces folder.
        """
        user_id = kwargs.get("user_id")
        result = self.recognize_faces(image_bytes, user_id=user_id)
        return {
            "success": result.get("success", False),
            "event_detected": result.get("stranger_detected", False),
            "detections": result.get("detections", []),
            "known_members": result.get("known_members", []),
            "has_faces": result.get("has_faces", False),
            "type": "face_recognition"
        }

    def _resolve_db_path(self, user_id: Optional[int]) -> Optional[str]:
        """Return the per-user DB path if user_id is given, else None.
        Returns None when the user has no enrolled faces yet — caller should treat
        this as 'no known members' rather than running DeepFace on an empty dir.
        """
        if user_id is None:
            return None
        user_dir = Path(self.base_db_path) / f"user_{user_id}"
        # If folder doesn't exist OR has no member subfolders, we have nothing to match against
        if not user_dir.exists():
            return None
        has_members = any(p.is_dir() for p in user_dir.iterdir())
        if not has_members:
            return None
        return str(user_dir)

    def recognize_faces(self, image_bytes: bytes, user_id: Optional[int] = None) -> Dict:
        """
        Recognize faces from image bytes and identify known vs unknown.
        Uses DeepFace.find directly on the full image — it handles
        detection, cropping, and matching against the indexed DB.
        `user_id` scopes recognition to that user's folder; without it, returns no-match.
        """
        try:
            nparr = np.frombuffer(image_bytes, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if img is None:
                return {"success": False, "error": "Failed to decode image"}

            # --- QUALITY GATE ---
            # Skip blurry / too dark / blown-out frames BEFORE the expensive DeepFace call.
            # Returning has_faces=False here makes main.py's smoothing logic ignore the frame
            # (no known streak bump, no stranger vote) — frame is treated as if camera was idle.
            quality = self._check_frame_quality(img)
            if not quality["ok"]:
                self._reject_counts[quality["reason"]] = self._reject_counts.get(quality["reason"], 0) + 1
                total_rejects = sum(v for k, v in self._reject_counts.items() if k != "passed")
                # Log every rejection but throttle summary to every 25 rejects to keep logs clean
                print(f"[FACE] Frame skipped ({quality['reason']}): "
                      f"blur={quality['blur']:.1f}, brightness={quality['brightness']:.1f}")
                if total_rejects > 0 and total_rejects % 25 == 0:
                    print(f"[FACE] Quality reject stats: {self._reject_counts}")
                return {
                    "success": True,
                    "has_faces": False,
                    "stranger_detected": False,
                    "detections": [],
                    "known_members": [],
                    "skipped": True,
                    "skip_reason": quality["reason"],
                }
            self._reject_counts["passed"] = self._reject_counts.get("passed", 0) + 1

            # Resolve per-user DB. If the caller didn't pass user_id, or the user has
            # no enrolled faces yet, we short-circuit and report 'no faces' so the
            # smoothing layer treats this frame as neutral (no stranger alert).
            db_path = self._resolve_db_path(user_id)
            if db_path is None:
                return {
                    "success": True,
                    "has_faces": False,
                    "stranger_detected": False,
                    "detections": [],
                    "known_members": [],
                    "skipped": True,
                    "skip_reason": "no_enrolled_faces" if user_id is not None else "no_user_id",
                }

            # Run DeepFace.find directly on the full image.
            # It will:
            #   1. Detect faces using the configured detector
            #   2. Crop & align each face
            #   3. Compute embeddings with SFace
            #   4. Compare against the indexed DB (.pkl cache)
            try:
                results = DeepFace.find(
                    img_path=img,
                    db_path=db_path,
                    model_name=self.model_name,
                    detector_backend=self.detector_backend,
                    distance_metric=self.distance_metric,
                    enforce_detection=False,
                    align=True,
                    silent=True,
                    threshold=self.threshold,  # Override DeepFace's strict default
                )
            except Exception as e:
                err_str = str(e)
                if "No item found in" in err_str or "no images" in err_str.lower():
                    return {
                        "success": True,
                        "has_faces": False,
                        "stranger_detected": False,
                        "detections": [],
                        "known_members": []
                    }
                print(f"[FACE] Search error: {e}")
                return {"success": False, "error": err_str}

            if not isinstance(results, list) or len(results) == 0:
                return {
                    "success": True,
                    "has_faces": False,
                    "stranger_detected": False,
                    "detections": [],
                    "known_members": []
                }

            detections = []
            known_members = []
            stranger_detected = False
            
            for df in results:
                label = "Unknown person"
                is_known = False
                matched_name = None
                confidence = 0.0

                if not df.empty:
                    best_match = df.iloc[0]
                    distance = float(best_match["distance"])
                    identity_path = best_match["identity"]
                    matched_name = os.path.basename(os.path.dirname(identity_path))
                    
                    if distance <= self.threshold:
                        print(f"[FACE] Match found: {matched_name} (dist: {distance:.3f})")
                        label = f"Known person: {matched_name}"
                        is_known = True
                        confidence = 1.0 - distance
                        known_members.append(matched_name)
                    else:
                        print(f"[FACE] Potential match {matched_name} rejected (dist: {distance:.3f} > {self.threshold})")
                        matched_name = None
                else:
                    print(f"[FACE] No match found in DB for this face")

                if not is_known:
                    stranger_detected = True

                detections.append({
                    "label": label,
                    "is_known": is_known,
                    "name": matched_name,
                    "confidence": round(confidence, 3),
                })

            return {
                "success": True,
                "has_faces": True,
                "stranger_detected": stranger_detected,
                "detections": detections,
                "known_members": list(set(known_members))
            }

        except Exception as e:
            print(f"[FACE] Global error in recognize_faces: {e}")
            return {"success": False, "error": str(e)}


_face_service: Optional[FaceRecognitionService] = None

def get_face_recognition_service() -> FaceRecognitionService:
    """Get or create the global face recognition service instance"""
    global _face_service
    if _face_service is None:
        _face_service = FaceRecognitionService()
    return _face_service
