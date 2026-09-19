"""
Delete a home owner account and related DB rows / files by email.
Usage: python delete_user_by_email.py user@example.com
Run from server/ directory.
"""

from __future__ import annotations

import os
import shutil
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

SERVER = Path(__file__).resolve().parent


def _unlink(rel: str | None) -> None:
    if not rel:
        return
    p = Path(rel)
    if not p.is_absolute():
        p = SERVER / str(rel).lstrip("/")
    if p.is_file():
        p.unlink()
        print(f"  [file] deleted {p.name}")


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python delete_user_by_email.py <email>")
        sys.exit(1)

    email = sys.argv[1].strip()
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    cur.execute(
        "SELECT id, name, email, profile_image FROM users WHERE LOWER(TRIM(email)) = LOWER(TRIM(%s))",
        (email,),
    )
    row = cur.fetchone()
    if not row:
        print(f"No user found for email: {email!r}")
        cur.close()
        conn.close()
        sys.exit(2)

    uid = int(row[0])
    name, db_email, profile = row[1], row[2], row[3]
    print(f"Deleting user_id={uid} name={name!r} email={db_email!r}")

    cur.execute("SELECT id, email FROM users WHERE owner_user_id = %s", (uid,))
    family_users = cur.fetchall()
    print(f"Linked family login accounts: {len(family_users)}")

    cur.execute("SELECT id, video_path FROM user_events WHERE user_id = %s", (uid,))
    events = cur.fetchall()
    print(f"Events: {len(events)}")

    cur.execute("SELECT id FROM family_members WHERE user_id = %s", (uid,))
    fam_ids = [r[0] for r in cur.fetchall()]
    cur.execute("SELECT id FROM trusted_persons WHERE user_id = %s", (uid,))
    trusted_ids = [r[0] for r in cur.fetchall()]

    photo_paths: list[str] = []
    for mid in fam_ids:
        cur.execute(
            "SELECT photo_path FROM member_photos WHERE member_id = %s AND member_type = 'family'",
            (mid,),
        )
        photo_paths.extend(r[0] for r in cur.fetchall())
    for tid in trusted_ids:
        cur.execute(
            "SELECT photo_path FROM member_photos WHERE member_id = %s AND member_type = 'trusted'",
            (tid,),
        )
        photo_paths.extend(r[0] for r in cur.fetchall())

    cur.execute(
        """
        SELECT pp.photo_path FROM pet_photos pp
        JOIN pets p ON p.id = pp.pet_id
        WHERE p.user_id = %s
        """,
        (uid,),
    )
    photo_paths.extend(r[0] for r in cur.fetchall())

    for vp in (r[1] for r in events if r[1]):
        _unlink(vp)
    _unlink(profile)
    for pp in photo_paths:
        _unlink(pp)

    faces = SERVER / "known_faces" / f"user_{uid}"
    if faces.is_dir():
        shutil.rmtree(faces)
        print(f"  [dir] removed {faces}")

    for pkl in (SERVER / "known_faces").glob(f"user_{uid}*.pkl"):
        pkl.unlink(missing_ok=True)

    cur.execute("DELETE FROM otp_codes WHERE LOWER(TRIM(email)) = LOWER(TRIM(%s))", (email,))
    cur.execute("DELETE FROM users WHERE id = %s RETURNING id", (uid,))
    deleted = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()

    if deleted:
        print(f"Done. Deleted user id={deleted[0]}")
    else:
        print("Delete failed — user row not removed.")
        sys.exit(1)


if __name__ == "__main__":
    main()
