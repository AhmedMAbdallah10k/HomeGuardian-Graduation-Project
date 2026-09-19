from deepface import DeepFace
import os
import psycopg2
from psycopg2.extras import RealDictCursor

def test_fifth_user():
    try:
        conn = psycopg2.connect(user='postgres', password='123456', host='localhost', database='homeguardian')
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute('SELECT id, email, profile_image FROM users WHERE profile_image IS NOT NULL ORDER BY id ASC OFFSET 4 LIMIT 1')
        user = cursor.fetchone()
        cursor.close()
        conn.close()
        
        if not user:
            print("No 5th user found.")
            return

        print(f"Testing 5th user: {user['email']} (File: {user['profile_image']})")
        path = user['profile_image']
        
        if not os.path.exists(path):
            print(f"File does not exist: {path}")
            return

        # Try to extract face to see if it's readable
        print("Attempting face detection...")
        objs = DeepFace.extract_faces(img_path=path, enforce_detection=False)
        print(f"Success! Detected {len(objs)} faces.")
        
    except Exception as e:
        print(f"Error testing 5th user: {e}")

if __name__ == "__main__":
    test_fifth_user()
