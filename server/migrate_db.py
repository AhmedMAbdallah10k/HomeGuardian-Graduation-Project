import os
import psycopg2
from dotenv import load_dotenv

load_dotenv()

DB_CONFIG = {
    "user": os.getenv("DB_USER", "postgres"),
    "host": os.getenv("DB_HOST", "localhost"),
    "database": os.getenv("DB_NAME", "homeguardian"),
    "password": os.getenv("DB_PASSWORD", "postgres"),
    "port": os.getenv("DB_PORT", "5432"),
}

def migrate():
    print("Connecting to database...")
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        conn.autocommit = True
        cursor = conn.cursor()
        
        print("Checking users table...")
        # Check if column exists
        cursor.execute("""
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_name='users' AND column_name='password_hash';
        """)
        
        if cursor.fetchone():
            print("Column 'password_hash' already exists.")
        else:
            print("Adding 'password_hash' column...")
            cursor.execute("ALTER TABLE users ADD COLUMN password_hash VARCHAR(255);")
            print("Column added successfully.")
            
        cursor.close()
        conn.close()
        print("Migration complete.")
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    migrate()
