from ultralytics import YOLO
import cv2

# load trained model
model = YOLO("Object_State_Detection_Model.pt")

# open webcam (0 = laptop camera)
cap = cv2.VideoCapture(0)

if not cap.isOpened():
    print("Camera not detected")
    exit()

while True:
    ret, frame = cap.read()
    if not ret:
        break

    # run detection
    results = model(frame)

    # draw predictions
    annotated_frame = results[0].plot()

    # get class name text
    for box in results[0].boxes:
        cls_id = int(box.cls[0])
        conf = float(box.conf[0])
        label = model.names[cls_id]

        print(f"{label} : {conf:.2f}")

    # show window
    cv2.imshow("Home Guardian - Door Detection", annotated_frame)

    # press Q to quit
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()
