"""
Test script for Face Recognition System
Tests both enrollment and recognition functionality
"""
import os
import pickle
import sys
from pathlib import Path

# Try to import face_recognition (for enroll_faces.py system)
try:
    import face_recognition
    FACE_RECOGNITION_AVAILABLE = True
except ImportError:
    FACE_RECOGNITION_AVAILABLE = False
    print("[INFO] face_recognition library not available")

# Try to import DeepFace (for deepface_stream.py system)
try:
    from deepface import DeepFace
    DEEPFACE_AVAILABLE = True
except ImportError:
    DEEPFACE_AVAILABLE = False
    print("[INFO] DeepFace library not available")

def test_face_recognition_system():
    """Test the face_recognition based system (enroll_faces.py)"""
    print("\n" + "="*60)
    print("TESTING: face_recognition System (enroll_faces.py)")
    print("="*60)
    
    if not FACE_RECOGNITION_AVAILABLE:
        print("[ERROR] face_recognition library not installed")
        print("Install with: pip install face-recognition")
        return False
    
    # Check if encodings file exists
    encodings_path = "models/encodings.pkl"
    if not os.path.exists(encodings_path):
        print(f"[WARN] Encodings file not found at: {encodings_path}")
        print("[INFO] You need to run enroll_faces.py first to create encodings")
        return False
    
    # Load encodings
    try:
        with open(encodings_path, "rb") as f:
            data = pickle.load(f)
        
        if isinstance(data, dict):
            if "encodings" in data and "names" in data:
                encodings = data["encodings"]
                names = data["names"]
                print(f"[OK] Loaded {len(encodings)} face encodings")
                print(f"[INFO] Names in database: {set(names)}")
            else:
                # Different format - might be user_id: encoding format
                print(f"[OK] Loaded encodings file with {len(data)} entries")
                print(f"[INFO] Format: {type(list(data.values())[0]) if data else 'empty'}")
        else:
            print(f"[WARN] Unexpected format in encodings file")
            return False
            
    except Exception as e:
        print(f"[ERROR] Failed to load encodings: {e}")
        return False
    
    # Test recognition on a sample image
    test_image_path = input("\nEnter path to test image (or press Enter to skip): ").strip()
    if test_image_path and os.path.exists(test_image_path):
        try:
            print(f"\n[TEST] Testing recognition on: {test_image_path}")
            test_image = face_recognition.load_image_file(test_image_path)
            test_encodings = face_recognition.face_encodings(test_image)
            
            if len(test_encodings) == 0:
                print("[ERROR] No face detected in test image")
                return False
            
            test_encoding = test_encodings[0]
            print(f"[OK] Face detected and encoded")
            
            # Compare with known faces
            if isinstance(data, dict) and "encodings" in data:
                matches = face_recognition.compare_faces(data["encodings"], test_encoding)
                face_distances = face_recognition.face_distance(data["encodings"], test_encoding)
                
                if True in matches:
                    match_index = matches.index(True)
                    name = data["names"][match_index]
                    distance = face_distances[match_index]
                    confidence = 1 - distance
                    print(f"[SUCCESS] Face recognized!")
                    print(f"  Name: {name}")
                    print(f"  Confidence: {confidence:.2%}")
                    print(f"  Distance: {distance:.4f}")
                    return True
                else:
                    print("[INFO] Face not recognized (no match found)")
                    if len(face_distances) > 0:
                        best_match_idx = face_distances.argmin()
                        best_distance = face_distances[best_match_idx]
                        best_name = data["names"][best_match_idx]
                        print(f"  Closest match: {best_name} (distance: {best_distance:.4f})")
                    return False
            else:
                print("[WARN] Cannot test recognition - encodings format not supported")
                return False
                
        except Exception as e:
            print(f"[ERROR] Recognition test failed: {e}")
            return False
    else:
        print("[SKIP] No test image provided")
        return True

def test_deepface_system():
    """Test the DeepFace based system (deepface_stream.py)"""
    print("\n" + "="*60)
    print("TESTING: DeepFace System (deepface_stream.py)")
    print("="*60)
    
    if not DEEPFACE_AVAILABLE:
        print("[ERROR] DeepFace library not installed")
        print("Install with: pip install deepface")
        return False
    
    # Check if known_faces directory exists
    db_path = "known_faces"
    if not os.path.exists(db_path):
        print(f"[WARN] Database directory not found: {db_path}")
        print("[INFO] Create this directory and add face images")
        return False
    
    # List known faces
    known_faces = []
    if os.path.isdir(db_path):
        for item in os.listdir(db_path):
            item_path = os.path.join(db_path, item)
            if os.path.isdir(item_path):
                known_faces.append(item)
    
    print(f"[OK] Found {len(known_faces)} known faces in database")
    if known_faces:
        print(f"[INFO] Known faces: {', '.join(known_faces)}")
    
    # Test recognition on a sample image
    test_image_path = input("\nEnter path to test image (or press Enter to skip): ").strip()
    if test_image_path and os.path.exists(test_image_path):
        try:
            print(f"\n[TEST] Testing recognition on: {test_image_path}")
            result = DeepFace.find(
                img_path=test_image_path,
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
                
                # Extract name from path
                name = os.path.basename(os.path.dirname(identity))
                
                print(f"[SUCCESS] Face recognized!")
                print(f"  Name: {name}")
                print(f"  Distance: {distance:.4f}")
                print(f"  Threshold: {threshold:.4f}")
                print(f"  Match: {'Yes' if distance < threshold else 'No (below threshold)'}")
                return distance < threshold
            else:
                print("[INFO] Face not recognized (no match found)")
                return False
                
        except Exception as e:
            print(f"[ERROR] Recognition test failed: {e}")
            return False
    else:
        print("[SKIP] No test image provided")
        return True

def check_dependencies():
    """Check if required dependencies are installed"""
    print("\n" + "="*60)
    print("CHECKING DEPENDENCIES")
    print("="*60)
    
    dependencies = {
        "face_recognition": FACE_RECOGNITION_AVAILABLE,
        "deepface": DEEPFACE_AVAILABLE,
        "opencv-python": True,  # Assume available if we got this far
        "numpy": True,
    }
    
    all_ok = True
    for dep, available in dependencies.items():
        status = "✓" if available else "✗"
        print(f"{status} {dep}")
        if not available:
            all_ok = False
    
    if not all_ok:
        print("\n[INFO] Install missing dependencies:")
        if not FACE_RECOGNITION_AVAILABLE:
            print("  pip install face-recognition")
        if not DEEPFACE_AVAILABLE:
            print("  pip install deepface")
    
    return all_ok

def main():
    print("\n" + "="*60)
    print("FACE RECOGNITION SYSTEM TEST")
    print("="*60)
    
    # Check dependencies
    check_dependencies()
    
    # Check what files exist
    print("\n" + "="*60)
    print("CHECKING FILES")
    print("="*60)
    
    files_to_check = {
        "enroll_faces.py": "server/enroll_faces.py",
        "deepface_stream.py": "server/deepface_stream.py",
        "encodings.pkl": "server/models/encodings.pkl",
        "known_faces/": "server/known_faces",
    }
    
    for name, path in files_to_check.items():
        exists = os.path.exists(path)
        status = "✓" if exists else "✗"
        print(f"{status} {name}: {path}")
    
    # Test both systems
    results = {}
    
    # Test face_recognition system
    if os.path.exists("server/models/encodings.pkl") or os.path.exists("models/encodings.pkl"):
        results['face_recognition'] = test_face_recognition_system()
    
    # Test DeepFace system
    if os.path.exists("server/known_faces") or os.path.exists("known_faces"):
        results['deepface'] = test_deepface_system()
    
    # Summary
    print("\n" + "="*60)
    print("TEST SUMMARY")
    print("="*60)
    
    if not results:
        print("[INFO] No tests were run. Make sure you have:")
        print("  1. encodings.pkl file (for face_recognition system)")
        print("  2. known_faces/ directory (for DeepFace system)")
        print("  3. Run enroll_faces.py first to create encodings")
    else:
        for system, result in results.items():
            status = "PASS" if result else "FAIL"
            print(f"{system}: {status}")
    
    print("\n" + "="*60)

if __name__ == "__main__":
    # Change to server directory if needed
    if os.path.exists("server"):
        os.chdir("server")
    
    main()

