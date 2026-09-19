from ultralytics import YOLO
from pathlib import Path
import cv2

# Resolve best.pt relative to THIS script, so it works no matter where you launch from.
_MODEL_PATH = Path(__file__).resolve().parent / "best.pt"
model = YOLO(str(_MODEL_PATH))
model.fuse()

cap = cv2.VideoCapture(0)
cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
cap.set(cv2.CAP_PROP_FPS, 30)
cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

while True:
    ret, frame = cap.read()
    if not ret:
        break

    results = model.predict(
        source=frame,
        conf=0.75,
        iou=0.45,
        imgsz=320,
        verbose=False,
        device="cpu",
    )

    annotated = results[0].plot()
    cv2.imshow("Sharp Objects Detection", annotated)

    if cv2.waitKey(1) & 0xFF == ord("q"):
        break

cap.release()
cv2.destroyAllWindows()