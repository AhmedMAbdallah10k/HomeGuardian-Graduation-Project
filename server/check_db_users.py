import psycopg2
from psycopg2.extras import RealDictCursor
import os

def check_users():
    try:
        conn = psycopg2.connect(user='postgres', password='123456', host='localhost', database='homeguardian')
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute('SELECT id, email, profile_image FROM users WHERE profile_image IS NOT NULL')
        users = cursor.fetchall()
        print(f"Total users in DB with profile_image: {len(users)}")
        for u in users:
            path = u['profile_image']
            exists = os.path.exists(path)
            print(f"ID: {u['id']}, Email: {u['email']}, Path: {path}, Exists: {exists}")
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    check_users()
