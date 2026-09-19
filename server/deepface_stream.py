from deepface import DeepFace

DB_PATH = "known_faces"

if __name__ == "__main__":
    DeepFace.stream(
        db_path=DB_PATH,
        model_name="Facenet",          # recognition backbone
        detector_backend="opencv",     # 🔹 switched from 'mediapipe' to 'opencv'
        enable_face_analysis=False     # no age/gender/emotion, only recognition
    )
