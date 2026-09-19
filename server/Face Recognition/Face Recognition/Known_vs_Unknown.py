import cv2
from deepface import DeepFace
import os

# Get the directory where the script is located
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
# Path to known_faces relative to the script (server/known_faces)
DB_PATH = os.path.join(SCRIPT_DIR, "..", "..", "known_faces")

# Ensure the directory exists
if not os.path.exists(DB_PATH):
    os.makedirs(DB_PATH)
    print(f"Created missing directory: {DB_PATH}")
    print("Please add subfolders with images (e.g., {DB_PATH}/Ahmed/face.jpg) for recognition to work.")

MODEL_NAME = "SFace"         
DETECTOR = "ssd"  # better for turned faces 
DISTANCE_METRIC = "cosine"
THRESHOLD = 0.7              

cap = cv2.VideoCapture(0)    

while True:
    ret, frame = cap.read()
    if not ret:
        break  

    try:
        # detect faces in the frame
        faces = DeepFace.extract_faces(
            img_path=frame,
            detector_backend=DETECTOR,
            enforce_detection=False # avoid crashing if no face is found
        )
    except Exception:
        faces = []

    if len(faces) == 0:
        cv2.imshow("Home Guardian - Face Watch", frame)
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break
        continue

    #process the faces in frame
    for face_obj in faces:
        area = face_obj["facial_area"]
        x, y, w, h = area["x"], area["y"], area["w"], area["h"]

        #crop the face from the frame
        face_crop = frame[y:y+h, x:x+w]

        #compare this face with your known_faces database
        result = DeepFace.find(
            img_path=face_crop,
            db_path=DB_PATH,
            model_name=MODEL_NAME,
            detector_backend=DETECTOR,
            distance_metric=DISTANCE_METRIC,
            enforce_detection=False
        )

        # DeepFace.find returns df in list, so take result[0]
        if isinstance(result, list) and len(result) > 0:  #safety check
            df = result[0]
        else:
            df = None

        label = "Unknown person"
        color = (0, 0, 255)  # red box for strangers

        if df is not None and len(df) > 0:
            best = df.iloc[0]
            distance = best["distance"]
            identity_path = best["identity"]
            name = os.path.basename(os.path.dirname(identity_path))

            if distance <= THRESHOLD:
                label = "Known person"+": "+name
                color = (0, 255, 0)  # green box for known faces

        #draw the box and label on the original frame
        cv2.rectangle(frame, (x, y), (x + w, y + h), color, 2)
        cv2.putText(
            frame, label, (x, y - 10),
            cv2.FONT_HERSHEY_SIMPLEX, 0.8, color, 2, cv2.LINE_AA
        )

    #show the frame
    cv2.imshow("Home Guardian - Face Watch", frame)

    # Press 'q' to quit
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()
