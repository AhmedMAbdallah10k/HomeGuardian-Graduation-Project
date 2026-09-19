import cv2
import time
import math
from ultralytics import YOLO


model = YOLO(r"D:\WORKSPACE\Graduation_Project\sleep&Stillness_detection\yolov8s.pt")


cap = cv2.VideoCapture(1)

if not cap.isOpened():
    print("Camera not detected")
    exit()


movement_threshold   = 20  # wa da by3ml allow la space 7rka mo3yn wa msh 7ydetect eno byt7rk
still_time_threshold = 20  # da threshold byshof y3ml detect law mshbyt7rk la seconds mo3yna


person_states = {}

while True:

    ret, frame = cap.read()
    if not ret:
        break

    results = model.track(
        frame,
        persist=True,
        tracker=r"D:\WORKSPACE\Graduation_Project\sleep&Stillness_detection\bytetrack.yaml",
        classes=[0],
        conf=0.5,
        iou=0.5,
        verbose=False
    )

    active_ids = set()

    for r in results:

        if r.boxes is None or r.boxes.id is None:
            continue

        for box, track_id in zip(r.boxes, r.boxes.id.int().cpu().tolist()):

            active_ids.add(track_id)

            x1, y1, x2, y2 = map(int, box.xyxy[0])

            cx = int((x1 + x2) / 2)
            cy = int((y1 + y2) / 2)
            center = (cx, cy)

            cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
            cv2.circle(frame, center, 5, (0, 0, 255), -1)

            if track_id not in person_states:
                person_states[track_id] = {
                    "prev_center":      None,
                    "still_start_time": None
                }

            state            = person_states[track_id]
            prev_center      = state["prev_center"]
            still_start_time = state["still_start_time"]

            # -----------------------------
            # Movement check
            # -----------------------------
            if prev_center is not None:

                dist = math.sqrt(
                    (center[0] - prev_center[0]) ** 2 +
                    (center[1] - prev_center[1]) ** 2
                )

                cv2.putText(
                    frame,
                    f"ID:{track_id}  dist:{dist:.1f}px",
                    (x1, y1 - 10),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.55, (200, 200, 0), 1
                )

                if dist < movement_threshold:

                    if still_start_time is None:
                        still_start_time = time.time()

                    elapsed = time.time() - still_start_time

                    still_text = f"ID{track_id} Still: {int(elapsed)} sec"
                    (tw, th), _ = cv2.getTextSize(still_text, cv2.FONT_HERSHEY_SIMPLEX, 0.8, 2)
                    tr_x = frame.shape[1] - tw - 10
                    tr_y = 35 + track_id * 45

                    cv2.putText(
                        frame,
                        still_text,
                        (tr_x, tr_y),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.8, (0, 255, 255), 2
                    )

                    if elapsed > still_time_threshold:
                        alert_text = f"ID{track_id} PROLONGED STILLNESS"
                        (aw, _), _ = cv2.getTextSize(alert_text, cv2.FONT_HERSHEY_SIMPLEX, 0.8, 3)
                        ar_x = frame.shape[1] - aw - 10

                        cv2.putText(
                            frame,
                            alert_text,
                            (ar_x, tr_y + 30),
                            cv2.FONT_HERSHEY_SIMPLEX,
                            0.8, (0, 0, 255), 3
                        )

                else:
                    still_start_time = None

            # write state back into the dict
            state["prev_center"]      = center
            state["still_start_time"] = still_start_time

    # clean up people who left the frame
    for gone_id in list(person_states.keys()):
        if gone_id not in active_ids:
            del person_states[gone_id]

    cv2.imshow("Real-Time Stillness Detection", frame)

    if cv2.waitKey(1) & 0xFF == 27:
        break

cap.release()
cv2.destroyAllWindows()