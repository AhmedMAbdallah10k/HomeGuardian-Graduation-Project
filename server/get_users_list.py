import psycopg2
from psycopg2.extras import RealDictCursor

def get_users_list():
    try:
        conn = psycopg2.connect(user='postgres', password='123456', host='localhost', database='homeguardian')
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute('SELECT id, email FROM users WHERE profile_image IS NOT NULL ORDER BY id ASC')
        users = cursor.fetchall()
        for u in users:
            print(f"{u['id']} - {u['email']}")
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    get_users_list()
