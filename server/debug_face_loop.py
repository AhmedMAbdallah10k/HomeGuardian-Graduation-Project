import psycopg2
from psycopg2.extras import RealDictCursor
import os

def debug_loop():
    try:
        conn = psycopg2.connect(user='postgres', password='123456', host='localhost', database='homeguardian')
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute("SELECT id, email, profile_image FROM users WHERE profile_image IS NOT NULL ORDER BY id ASC")
        users = cursor.fetchall()
        print(f"DEBUG: Found {len(users)} users in DB")
        for i, user in enumerate(users):
            db_image_path = user['profile_image']
            exists = os.path.exists(db_image_path)
            print(f"{i+1}. User {user['id']} ({user['email']}): Path='{db_image_path}', Exists={exists}")
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"DEBUG ERROR: {e}")

if __name__ == "__main__":
    debug_loop()
