"""
Quick test script for face recognition
Tests if the system can load encodings and recognize faces
"""
import os
import pickle
import sys
from pathlib import Path

def quick_test():
    print("\n" + "="*60)
    print("QUICK FACE RECOGNITION TEST")
    print("="*60)
    
    # Check if face_recognition is available
    try:
        import face_recognition
        print("[OK] face_recognition library imported")
        use_face_recognition = True
    except ImportError:
        print("[INFO] face_recognition not available (requires CMake)")
        print("[INFO] Trying DeepFace instead...")
        use_face_recognition = False
        
        # Try DeepFace
        try:
            from deepface import DeepFace
            print("[OK] DeepFace library available - using DeepFace")
            return test_with_deepface()
        except ImportError as e:
            print(f"[ERROR] DeepFace import failed: {e}")
            print("\n[SOLUTION] Install DeepFace dependencies:")
            print("  pip install deepface tensorflow opencv-python pandas")
            print("\nOr if you prefer face-recognition (requires CMake):")
            print("  1. Download CMake from https://cmake.org/download/")
            print("  2. Install and add to PATH")
            print("  3. pip install face-recognition")
            return
        except Exception as e:
            print(f"[ERROR] DeepFace error: {e}")
            print("\n[INFO] DeepFace might need TensorFlow. Try:")
            print("  pip install tensorflow")
            return
    
    # Check encodings file
    encodings_path = "models/encodings.pkl"
    if not os.path.exists(encodings_path):
        print(f"\n[ERROR] Encodings file not found: {encodings_path}")
        print("\n[INFO] You need to:")
        print("  1. Create a 'known_faces' folder")
        print("  2. Add folders for each person (e.g., known_faces/Ahmed/)")
        print("  3. Add face images in each person's folder")
        print("  4. Run: python enroll_faces.py")
        return
    
    # Load encodings
    print(f"\n[TEST] Loading encodings from: {encodings_path}")
    try:
        with open(encodings_path, "rb") as f:
            data = pickle.load(f)
        
        if isinstance(data, dict):
            if "encodings" in data and "names" in data:
                encodings = data["encodings"]
                names = data["names"]
                print(f"[SUCCESS] Loaded {len(encodings)} face encodings")
                print(f"[INFO] Known people: {set(names)}")
                
                # Show statistics
                from collections import Counter
                name_counts = Counter(names)
                print("\n[INFO] Face count per person:")
                for name, count in name_counts.items():
                    print(f"  - {name}: {count} face(s)")
                
            else:
                print(f"[INFO] Encodings file has {len(data)} entries")
                print(f"[INFO] Format: {type(list(data.values())[0]) if data else 'empty'}")
        else:
            print(f"[WARN] Unexpected format")
            return
            
    except Exception as e:
        print(f"[ERROR] Failed to load: {e}")
        return
    
    # Test with an image if provided
    if len(sys.argv) > 1:
        test_image = sys.argv[1]
        if os.path.exists(test_image):
            print(f"\n[TEST] Testing recognition on: {test_image}")
            try:
                image = face_recognition.load_image_file(test_image)
                test_encodings = face_recognition.face_encodings(image)
                
                if len(test_encodings) == 0:
                    print("[ERROR] No face detected in image")
                    return
                
                print(f"[OK] Face detected")
                
                if isinstance(data, dict) and "encodings" in data:
                    matches = face_recognition.compare_faces(data["encodings"], test_encodings[0])
                    face_distances = face_recognition.face_distance(data["encodings"], test_encodings[0])
                    
                    if True in matches:
                        match_idx = matches.index(True)
                        name = data["names"][match_idx]
                        distance = face_distances[match_idx]
                        confidence = (1 - distance) * 100
                        print(f"\n[SUCCESS] ✅ FACE RECOGNIZED!")
                        print(f"  Name: {name}")
                        print(f"  Confidence: {confidence:.1f}%")
                        print(f"  Distance: {distance:.4f}")
                    else:
                        print("\n[INFO] ❌ Face not recognized")
                        if len(face_distances) > 0:
                            import numpy as np
                            best_idx = np.argmin(face_distances)
                            best_name = data["names"][best_idx]
                            best_dist = face_distances[best_idx]
                            print(f"  Closest match: {best_name} (distance: {best_dist:.4f})")
                else:
                    print("[WARN] Cannot test - encodings format not supported")
            except Exception as e:
                print(f"[ERROR] Test failed: {e}")
        else:
            print(f"[ERROR] Image not found: {test_image}")
    else:
        print("\n[INFO] To test recognition, provide an image:")
        print("  python quick_test_face.py path/to/image.jpg")
    
    print("\n" + "="*60)
    print("[DONE] Test completed!")

def test_with_deepface():
    """Test using DeepFace instead of face_recognition"""
    from deepface import DeepFace
    
    db_path = "known_faces"
    if not os.path.exists(db_path):
        print(f"\n[INFO] Database directory not found: {db_path}")
        print("[INFO] Creating directory...")
        os.makedirs(db_path, exist_ok=True)
        print(f"[OK] Created: {db_path}")
        print("\n[INSTRUCTIONS] To enroll faces:")
        print(f"  1. Create folders: {db_path}/PersonName/")
        print("  2. Add face images in each folder")
        print("  3. Run test again")
        return
    
    # List known faces
    known_faces = []
    if os.path.isdir(db_path):
        for item in os.listdir(db_path):
            item_path = os.path.join(db_path, item)
            if os.path.isdir(item_path):
                images = [f for f in os.listdir(item_path) 
                         if f.lower().endswith(('.jpg', '.jpeg', '.png'))]
                if images:
                    known_faces.append((item, len(images)))
    
    if not known_faces:
        print(f"\n[WARN] No faces enrolled in {db_path}")
        print("\n[INSTRUCTIONS] Create folders and add images")
        return
    
    print(f"\n[OK] Found {len(known_faces)} known people:")
    for name, count in known_faces:
        print(f"  - {name}: {count} image(s)")
    
    # Test with image if provided
    if len(sys.argv) > 1:
        test_image = sys.argv[1]
        if os.path.exists(test_image):
            print(f"\n[TEST] Testing recognition on: {test_image}")
            try:
                print("[INFO] Processing... (this may take 10-30 seconds)")
                result = DeepFace.find(
                    img_path=test_image,
                    db_path=db_path,
                    model_name="Facenet",
                    detector_backend="opencv",
                    enforce_detection=False,
                    silent=True
                )
                
                if result and len(result) > 0 and len(result[0]) > 0:
                    best_match = result[0].iloc[0]
                    identity = best_match['identity']
                    distance = best_match['distance']
                    threshold = best_match.get('threshold', 0.4)
                    name = os.path.basename(os.path.dirname(identity))
                    
                    if distance < threshold:
                        confidence = (1 - (distance / threshold)) * 100
                        print(f"\n[SUCCESS] ✅ FACE RECOGNIZED!")
                        print(f"  Name: {name}")
                        print(f"  Confidence: {confidence:.1f}%")
                        print(f"  Distance: {distance:.4f}")
                    else:
                        print(f"\n[INFO] ❌ Face not recognized")
                        print(f"  Closest: {name} (distance: {distance:.4f}, threshold: {threshold:.4f})")
                else:
                    print("\n[INFO] ❌ Face not recognized (no match)")
            except Exception as e:
                print(f"[ERROR] Test failed: {e}")
        else:
            print(f"[ERROR] Image not found: {test_image}")
    else:
        print("\n[INFO] To test, provide an image:")
        print("  python quick_test_face.py path/to/image.jpg")

if __name__ == "__main__":
    # Change to server directory if script is run from project root
    if os.path.exists("server") and not os.path.exists("models"):
        os.chdir("server")
    
    quick_test()

