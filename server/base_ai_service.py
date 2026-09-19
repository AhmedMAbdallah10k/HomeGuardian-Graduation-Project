from abc import ABC, abstractmethod
from typing import Dict, Any

class BaseAIService(ABC):
    """Base class for all AI detection services to ensure a consistent interface."""
    
    @abstractmethod
    def detect(self, image_bytes: bytes, **kwargs) -> Dict[str, Any]:
        """
        Run detection on the provided image bytes.
        Returns a standardized dictionary:
        {
            "success": bool,
            "event_detected": bool,
            "detections": list,
            "confidence": float,
            "metadata": dict
        }
        """
        pass
