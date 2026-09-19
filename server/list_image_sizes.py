import os
import psycopg2
from psycopg2.extras import RealDictCursor

def list_sizes():
    try:
        conn = psycopg2.connect(user='postgres', password='123456', host='localhost', database='homeguardian')
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute('SELECT email, profile_image FROM users WHERE profile_image IS NOT NULL ORDER BY id ASC')
        users = cursor.fetchall()
        for i, u in enumerate(users):
            path = u['profile_image']
            if os.path.exists(path):
                size = os.path.getsize(path)
                print(f"{i+1}. {u['email']}: {size} bytes")
            else:
                print(f"{i+1}. {u['email']}: FILE NOT FOUND ({path})")
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    list_sizes()
