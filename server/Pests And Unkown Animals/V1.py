import cv2
from ultralytics import YOLO

# Load YOLO model (small & fast)
model = YOLO("yolov8n.pt")   # this will auto-download the first time

# COCO class names (YOLO's default)
# We only care about the animal-related ones
ANIMAL_CLASSES = {
    14: "bird",
    15: "cat",
    16: "dog"
}

cap = cv2.VideoCapture(0)

while True:
    ret, frame = cap.read()
    if not ret:
        break

    # Run YOLO detection on the frame
    results = model(frame, verbose=False)

    # YOLO may return multiple result objects, take the first
    detections = results[0]

    for box in detections.boxes:
        cls_id = int(box.cls[0])      # class index
        conf = float(box.conf[0])     # confidence
        x1, y1, x2, y2 = box.xyxy[0].tolist()  # bounding box

        if cls_id in ANIMAL_CLASSES and conf >= 0.4:
            label = f"Animal intrusion: {ANIMAL_CLASSES[cls_id]} ({conf:.2f})"

            # Draw a red box for animal intrusion
            color = (0, 0, 255)
            x1, y1, x2, y2 = map(int, [x1, y1, x2, y2])
            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)

            # Put label above box
            cv2.putText(
                frame, label, (x1, y1 - 10),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2, cv2.LINE_AA
            )

    cv2.imshow("Home Guardian - Animal Intrusion", frame)

    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()
