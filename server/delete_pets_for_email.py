"""
One-off: delete all pets + pet photo files + pet_photos rows for a user by email.
Run from repo:  python delete_pets_for_email.py user@example.com
CWD should be server/ so paths like uploads/... resolve correctly.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent / ".env")

DB_CONFIG = {
    "user": os.getenv("DB_USER", "postgres"),
    "host": os.getenv("DB_HOST", "localhost"),
    "database": os.getenv("DB_NAME", "homeguardian"),
    "password": os.getenv("DB_PASSWORD", "postgres"),
    "port": os.getenv("DB_PORT", "5432"),
}


def _unlink_rel(relative_path: str | None) -> None:
    if not relative_path:
        return
    try:
        p = Path(relative_path)
        if not p.is_absolute():
            p = Path.cwd() / p
        if p.is_file():
            p.unlink()
            print(f"  [file] deleted {p}")
    except Exception as e:
        print(f"  [file] skip {relative_path}: {e}")


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python delete_pets_for_email.py <email>")
        sys.exit(1)
    raw = sys.argv[1].strip()
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    cur.execute(
        "SELECT id, email FROM users WHERE LOWER(TRIM(email)) = LOWER(TRIM(%s))",
        (raw,),
    )
    row = cur.fetchone()
    if not row:
        print(f"No user found for email: {raw!r}")
        cur.close()
        conn.close()
        sys.exit(2)
    uid, email = int(row[0]), row[1]
    print(f"User id={uid} email={email!r}")

    cur.execute(
        """
        SELECT pp.photo_path
        FROM pet_photos pp
        JOIN pets p ON p.id = pp.pet_id
        WHERE p.user_id = %s
        """,
        (uid,),
    )
    paths = [r[0] for r in cur.fetchall()]
    print(f"Photos in DB for this user: {len(paths)}")
    for rel in paths:
        _unlink_rel(rel)

    cur.execute("DELETE FROM pets WHERE user_id = %s RETURNING id", (uid,))
    deleted_ids = cur.fetchall()
    conn.commit()
    cur.close()
    conn.close()
    print(f"Deleted {len(deleted_ids)} pet row(s) (pet_photos CASCADE).")

    try:
        from pet_detection_service import get_pet_detection_service

        get_pet_detection_service().invalidate_user_pet_references(uid)
        print("Invalidated in-memory pet reference cache.")
    except Exception as e:
        print(f"(optional cache clear skipped: {e})")


if __name__ == "__main__":
    main()
