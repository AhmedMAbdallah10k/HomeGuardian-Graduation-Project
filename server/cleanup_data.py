import os
import shutil
import psycopg2
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Database configuration
DB_CONFIG = {
    "user": os.getenv("DB_USER", "postgres"),
    "host": os.getenv("DB_HOST", "localhost"),
    "database": os.getenv("DB_NAME", "homeguardian"),
    "password": os.getenv("DB_PASSWORD", "postgres"),
    "port": os.getenv("DB_PORT", "5432"),
}

def cleanup_files():
    print("--- Cleaning up files ---")
    folders_to_clear = ["uploads", "profile_images", "recordings", "known_faces"]
    
    for folder in folders_to_clear:
        folder_path = Path(folder)
        if folder_path.exists():
            print(f"Clearing folder: {folder}")
            for item in folder_path.iterdir():
                try:
                    if item.is_file():
                        item.unlink()
                    elif item.is_dir():
                        shutil.rmtree(item)
                    print(f"  Deleted: {item.name}")
                except Exception as e:
                    print(f"  Error deleting {item}: {e}")
        else:
            print(f"Folder not found: {folder}")

def cleanup_database():
    print("\n--- Cleaning up database ---")
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cursor = conn.cursor()
        
        # Tables to truncate
        tables = ["user_events", "user_options", "users"]
        
        for table in tables:
            print(f"Truncating table: {table}")
            cursor.execute(f"TRUNCATE TABLE {table} RESTART IDENTITY CASCADE;")
            
        conn.commit()
        cursor.close()
        conn.close()
        print("Database cleanup successful.")
    except Exception as e:
        print(f"Database error: {e}")

if __name__ == "__main__":
    confirm = input("Are you sure you want to delete ALL users and ALL uploaded files? (y/n): ")
    if confirm.lower() == 'y':
        cleanup_files()
        cleanup_database()
        print("\nCleanup complete!")
    else:
        print("Cleanup cancelled.")
