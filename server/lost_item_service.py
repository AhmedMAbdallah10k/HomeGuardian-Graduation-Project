"""
Lost item location tracking — sync detections to DB with annotated screenshots.

Saves the full room frame with a yellow box + label on the detected item.
Rules (per user + item class + room):
- First detection → save row + screenshot immediately
- Re-detection within 90s → keep row unchanged
- Re-detection after 90s → update timestamp + new screenshot
- Not detected on current frame → delete row for that item+room
"""

from __future__ import annotations

import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional

import cv2
import psycopg2
from dotenv import load_dotenv
from psycopg2.extras import RealDictCursor

import lost_item_bridge

# Load server/.env before reading DB credentials (main.py imports this module
# before its own load_dotenv(), so defaults would otherwise stick at import time).
load_dotenv(Path(__file__).resolve().parent / ".env")

UPDATE_COOLDOWN_SEC = 90
UPLOAD_SUBDIR = Path("uploads") / "lost_items"


def _db_config() -> dict:
    """Read DB settings at call time so .env is always applied."""
    return {
        "user": os.getenv("DB_USER", "postgres"),
        "host": os.getenv("DB_HOST", "localhost"),
        "database": os.getenv("DB_NAME", "homeguardian"),
        "password": os.getenv("DB_PASSWORD", "postgres"),
        "port": os.getenv("DB_PORT", "5432"),
    }


def _conn():
    return psycopg2.connect(**_db_config())


def ensure_table() -> None:
    conn = _conn()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS lost_item_locations (
                id SERIAL PRIMARY KEY,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                item_class VARCHAR(100) NOT NULL,
                room_name VARCHAR(100) NOT NULL,
                confidence REAL,
                screenshot_path VARCHAR(500),
                last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(user_id, item_class, room_name)
            )
            """
        )
        conn.commit()
        cur.close()
    finally:
        conn.close()


def preload() -> None:
    ensure_table()
    lost_item_bridge.preload()


def _safe_slug(text: str) -> str:
    s = re.sub(r"[^a-zA-Z0-9_-]+", "_", text.strip())
    return s[:60] or "item"


def _delete_screenshot(relative_path: Optional[str]) -> None:
    if not relative_path:
        return
    cleaned = relative_path.replace("\\", "/").lstrip("/")
    if cleaned.startswith("uploads/"):
        path = Path(cleaned)
    else:
        path = Path("uploads") / cleaned
    try:
        if path.is_file():
            path.unlink()
    except OSError:
        pass


def _clamp_bbox(bbox: List[int], width: int, height: int) -> Optional[tuple]:
    if len(bbox) != 4:
        return None
    x1, y1, x2, y2 = (int(v) for v in bbox)
    x1 = max(0, min(x1, width - 1))
    y1 = max(0, min(y1, height - 1))
    x2 = max(0, min(x2, width))
    y2 = max(0, min(y2, height))
    if x2 <= x1 or y2 <= y1:
        return None
    return x1, y1, x2, y2


def _annotate_frame(frame, item_class: str, confidence: float, bbox: List[int]):
    """Draw yellow detection box + label on a copy of the full room frame."""
    out = frame.copy()
    h, w = out.shape[:2]
    clamped = _clamp_bbox(bbox, w, h)
    if clamped is None:
        return out

    x1, y1, x2, y2 = clamped
    yellow = (0, 255, 255)  # BGR
    cv2.rectangle(out, (x1, y1), (x2, y2), yellow, 3)

    label = f"{item_class} {confidence:.0%}"
    font = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 0.6
    thickness = 2
    (tw, th), baseline = cv2.getTextSize(label, font, font_scale, thickness)
    pad = 4
    by1 = max(y1 - th - pad * 2 - baseline, 0)
    by2 = y1
    bx2 = min(x1 + tw + pad * 2, w)
    cv2.rectangle(out, (x1, by1), (bx2, by2), yellow, -1)
    cv2.putText(
        out,
        label,
        (x1 + pad, by2 - baseline - pad),
        font,
        font_scale,
        (0, 0, 0),
        thickness,
        cv2.LINE_AA,
    )
    return out


def _save_annotated_screenshot(
    frame,
    item_class: str,
    confidence: float,
    bbox: List[int],
    room_name: str,
    user_id: int,
) -> str:
    annotated = _annotate_frame(frame, item_class, confidence, bbox)
    user_dir = UPLOAD_SUBDIR / str(user_id)
    user_dir.mkdir(parents=True, exist_ok=True)
    filename = f"{_safe_slug(item_class)}_{_safe_slug(room_name)}_{uuid.uuid4().hex[:10]}.jpg"
    out_path = user_dir / filename
    ok = cv2.imwrite(str(out_path), annotated, [int(cv2.IMWRITE_JPEG_QUALITY), 90])
    if not ok:
        raise RuntimeError(f"Failed to write screenshot {out_path}")
    return str(out_path).replace("\\", "/")


def _best_per_class(detections: List[dict]) -> Dict[str, dict]:
    best: Dict[str, dict] = {}
    for det in detections:
        cls = str(det.get("class") or "").strip()
        if not cls:
            continue
        conf = float(det.get("confidence") or 0.0)
        prev = best.get(cls)
        if prev is None or conf > float(prev.get("confidence") or 0.0):
            best[cls] = det
    return best


def process_monitor_frame(user_id: int, room_name: str, jpeg_bytes: bytes) -> dict:
    """Detect items in frame and sync DB state for this room."""
    room = (room_name or "").strip()
    if not room or room == "Unknown":
        return {"updated": False, "reason": "invalid_room"}

    detections, frame = lost_item_bridge.detect(jpeg_bytes)
    if frame is None:
        return {"updated": False, "reason": "bad_frame"}

    best = _best_per_class(detections)
    detected_classes = set(best.keys())
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    changed = False

    conn = _conn()
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)

        cur.execute(
            """
            SELECT id, item_class, screenshot_path, last_seen_at
            FROM lost_item_locations
            WHERE user_id = %s AND room_name = %s
            """,
            (user_id, room),
        )
        existing_rows = cur.fetchall()
        existing_by_class = {str(r["item_class"]): r for r in existing_rows}

        for row in existing_rows:
            cls = str(row["item_class"])
            if cls not in detected_classes:
                _delete_screenshot(row.get("screenshot_path"))
                cur.execute("DELETE FROM lost_item_locations WHERE id = %s", (row["id"],))
                changed = True

        for cls, det in best.items():
            bbox = det.get("bbox") or []
            conf = float(det.get("confidence") or 0.0)

            prev = existing_by_class.get(cls)
            if prev is None:
                shot = _save_annotated_screenshot(
                    frame, cls, conf, bbox, room, user_id
                )
                cur.execute(
                    """
                    INSERT INTO lost_item_locations
                        (user_id, item_class, room_name, confidence, screenshot_path, last_seen_at)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    """,
                    (user_id, cls, room, conf, shot, now),
                )
                changed = True
                continue

            last_seen = prev.get("last_seen_at")
            if isinstance(last_seen, datetime):
                elapsed = (now - last_seen).total_seconds()
            else:
                elapsed = UPDATE_COOLDOWN_SEC

            if elapsed >= UPDATE_COOLDOWN_SEC:
                _delete_screenshot(prev.get("screenshot_path"))
                shot = _save_annotated_screenshot(
                    frame, cls, conf, bbox, room, user_id
                )
                cur.execute(
                    """
                    UPDATE lost_item_locations
                    SET confidence = %s, screenshot_path = %s, last_seen_at = %s
                    WHERE id = %s
                    """,
                    (conf, shot, now, prev["id"]),
                )
                changed = True

        conn.commit()
        cur.close()
    finally:
        conn.close()

    return {
        "updated": changed,
        "room": room,
        "detected": sorted(detected_classes),
        "count": len(detected_classes),
    }


def _row_to_api(row: dict) -> dict:
    last_seen = row.get("last_seen_at")
    if isinstance(last_seen, datetime):
        last_seen = last_seen.isoformat()
    shot = row.get("screenshot_path")
    return {
        "id": row["id"],
        "item_class": row["item_class"],
        "room_name": row["room_name"],
        "confidence": row.get("confidence"),
        "screenshot_path": shot,
        "last_seen_at": last_seen,
    }


def list_items(user_id: int) -> List[dict]:
    conn = _conn()
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(
            """
            SELECT id, item_class, room_name, confidence, screenshot_path, last_seen_at
            FROM lost_item_locations
            WHERE user_id = %s
            ORDER BY last_seen_at DESC, item_class ASC, room_name ASC
            """,
            (user_id,),
        )
        rows = cur.fetchall()
        cur.close()
        return [_row_to_api(r) for r in rows]
    finally:
        conn.close()


def get_item(user_id: int, item_id: int) -> Optional[dict]:
    conn = _conn()
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(
            """
            SELECT id, item_class, room_name, confidence, screenshot_path, last_seen_at
            FROM lost_item_locations
            WHERE user_id = %s AND id = %s
            """,
            (user_id, item_id),
        )
        row = cur.fetchone()
        cur.close()
        return _row_to_api(row) if row else None
    finally:
        conn.close()
