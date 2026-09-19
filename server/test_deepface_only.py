"""
Test DeepFace face recognition system (no CMake required)
This tests the system used in deepface_stream.py
"""
import os
import sys
from pathlib import Path

def test_deepface():
    print("\n" + "="*60)
    print("TESTING: DeepFace Face Recognition System")
    print("="*60)
    
    # Check if DeepFace is available
    try:
        from deepface import DeepFace
        print("[OK] DeepFace library imported successfully")
    except ImportError:
        print("[ERROR] DeepFace not installed")
        print("Install with: pip install deepface")
        return False
    
    # Check if known_faces directory exists
    db_path = "known_faces"
    if not os.path.exists(db_path):
        print(f"\n[INFO] Database directory not found: {db_path}")
        print("[INFO] Creating directory structure...")
        os.makedirs(db_path, exist_ok=True)
        print(f"[OK] Created: {db_path}")
        print("\n[INSTRUCTIONS] To enroll faces:")
        print("  1. Create folders for each person:")
        print(f"     {db_path}/Ahmed/")
        print(f"     {db_path}/Arwa/")
        print("  2. Add face images in each folder")
        print("  3. Run this test again")
        return False
    
    # List known faces
    known_faces = []
    face_count = 0
    if os.path.isdir(db_path):
        for item in os.listdir(db_path):
            item_path = os.path.join(db_path, item)
            if os.path.isdir(item_path):
                # Count images in folder
                images = [f for f in os.listdir(item_path) 
                         if f.lower().endswith(('.jpg', '.jpeg', '.png'))]
                known_faces.append((item, len(images)))
                face_count += len(images)
    
    if not known_faces:
        print(f"\n[WARN] No face folders found in {db_path}")
        print("\n[INSTRUCTIONS] To enroll faces:")
        print("  1. Create folders for each person:")
        print(f"     {db_path}/Ahmed/")
        print(f"     {db_path}/Arwa/")
        print("  2. Add face images in each folder")
        print("  3. Run this test again")
        return False
    
    print(f"\n[OK] Found {len(known_faces)} known people:")
    for name, count in known_faces:
        print(f"  - {name}: {count} image(s)")
    print(f"[INFO] Total enrolled faces: {face_count}")
    
    # Test recognition on an image if provided
    if len(sys.argv) > 1:
        test_image = sys.argv[1]
        if os.path.exists(test_image):
            print(f"\n[TEST] Testing recognition on: {test_image}")
            try:
                print("[INFO] Processing... (this may take a moment)")
                result = DeepFace.find(
                    img_path=test_image,
                    db_path=db_path,
                    model_name="Facenet",
                    detector_backend="opencv",
                    enforce_detection=False,  # Don't fail if face not detected
                    silent=True
                )
                
                if result and len(result) > 0 and len(result[0]) > 0:
                    best_match = result[0].iloc[0]
                    identity = best_match['identity']
                    distance = best_match['distance']
                    threshold = best_match.get('threshold', 0.4)
                    
                    # Extract name from path
                    name = os.path.basename(os.path.dirname(identity))
                    confidence = (1 - (distance / threshold)) * 100 if distance < threshold else 0
                    
                    if distance < threshold:
                        print(f"\n[SUCCESS] ✅ FACE RECOGNIZED!")
                        print(f"  Name: {name}")
                        print(f"  Confidence: {confidence:.1f}%")
                        print(f"  Distance: {distance:.4f}")
                        print(f"  Threshold: {threshold:.4f}")
                        return True
                    else:
                        print(f"\n[INFO] ❌ Face not recognized (below threshold)")
                        print(f"  Closest match: {name}")
                        print(f"  Distance: {distance:.4f} (threshold: {threshold:.4f})")
                        return False
                else:
                    print("\n[INFO] ❌ Face not recognized (no match found)")
                    return False
                    
            except Exception as e:
                print(f"\n[ERROR] Recognition test failed: {e}")
                import traceback
                traceback.print_exc()
                return False
        else:
            print(f"[ERROR] Image not found: {test_image}")
            return False
    else:
        print("\n[INFO] To test recognition, provide an image:")
        print("  python test_deepface_only.py path/to/image.jpg")
        print("\n[INFO] Example:")
        print("  python test_deepface_only.py uploads/user_3_profile_20251118_022159.jpg")
        return True

def main():
    print("\n" + "="*60)
    print("DEEPFACE FACE RECOGNITION TEST")
    print("="*60)
    
    success = test_deepface()
    
    print("\n" + "="*60)
    if success:
        print("[DONE] Test completed successfully!")
    else:
        print("[DONE] Test completed (see instructions above)")
    print("="*60)

if __name__ == "__main__":
    # Change to server directory if script is run from project root
    if os.path.exists("server") and not os.path.exists("known_faces"):
        os.chdir("server")
    
    main()

