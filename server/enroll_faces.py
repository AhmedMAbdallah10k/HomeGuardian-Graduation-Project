import os
import pickle
import face_recognition

KNOWN_FACES_DIR = "known_faces"
ENCODINGS_PATH = "data/encodings.pkl"

all_encodings = []
all_names = []

for person_name in os.listdir(KNOWN_FACES_DIR):
    person_folder = os.path.join(KNOWN_FACES_DIR, person_name)
    if not os.path.isdir(person_folder):
        continue

    for filename in os.listdir(person_folder):
        img_path = os.path.join(person_folder, filename)
        image = face_recognition.load_image_file(img_path)

        # Detect & encode (some images may not contain a face)
        encodings = face_recognition.face_encodings(image)
        if len(encodings) == 0:
            print(f"[WARN] No face found in {img_path}")
            continue

        all_encodings.append(encodings[0])
        all_names.append(person_name)
        print(f"[OK] Added {person_name} from {filename}")

# Save to disk
os.makedirs("data", exist_ok=True)
with open(ENCODINGS_PATH, "wb") as f:
    pickle.dump({"encodings": all_encodings, "names": all_names}, f)

print(f"[DONE] Saved {len(all_encodings)} face encodings.")
