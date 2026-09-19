import psycopg2
from psycopg2.extras import RealDictCursor
import os
from pathlib import Path

def run_diag():
    try:
        conn = psycopg2.connect(
            user='postgres', 
            password='123456', 
            host='localhost', 
            database='homeguardian'
        )
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        print("--- USERS WITH PROFILE IMAGES ---")
        cursor.execute('SELECT id, email, profile_image FROM users WHERE profile_image IS NOT NULL')
        users = cursor.fetchall()
        for u in users:
            path = u['profile_image']
            exists = os.path.exists(path)
            size = os.path.getsize(path) if exists else 0
            print(f"ID: {u['id']}, Email: {u['email']}, Path: {path}, Exists: {exists}, Size: {size} bytes")
            
        print("\n--- MEMBER PHOTOS (FAMILY/TRUSTED) ---")
        cursor.execute('SELECT * FROM member_photos')
        photos = cursor.fetchall()
        for p in photos:
            path = p['photo_path']
            exists = os.path.exists(path)
            size = os.path.getsize(path) if exists else 0
            print(f"ID: {p['id']}, MemberID: {p['member_id']}, Type: {p['member_type']}, Path: {path}, Exists: {exists}, Size: {size} bytes")
            
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    run_diag()
