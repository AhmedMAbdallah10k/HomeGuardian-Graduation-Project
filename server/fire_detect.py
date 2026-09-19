from ultralytics import YOLO
import cv2
from pathlib import Path

# Get the directory where this script is located
SCRIPT_DIR = Path(__file__).parent

# load pretrained YOLOv8  model
model = YOLO(str(SCRIPT_DIR / "models" / "finetuned.pt"))

#run interferance on the source
video_path = SCRIPT_DIR / "WhatsApp Video 2025-11-18 at 19.00.39_09abbd29.mp4"
results = model(source=str(video_path), show=True, conf=0.4, save=False)