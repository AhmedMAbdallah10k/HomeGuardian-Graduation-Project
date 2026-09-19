from fastapi import BackgroundTasks, FastAPI, HTTPException, UploadFile, File, Form, WebSocket, WebSocketDisconnect, Depends, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse, FileResponse, Response
from pydantic import BaseModel, validator
from typing import Dict, List, Optional, Set, Tuple
import hashlib
import secrets
from contextlib import asynccontextmanager
import psycopg2
from psycopg2.extras import Json, RealDictCursor
from datetime import datetime
import os
import base64
import json
import asyncio
import time
from passlib.context import CryptContext
from jose import JWTError, jwt
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from datetime import timedelta
from dotenv import load_dotenv
from pathlib import Path
import subprocess
from fire_detection_service import get_fire_detection_service
from exit_detection_service import get_exit_detection_service
from stillness_detection_service import get_stillness_detection_service
from pet_detection_service import get_pet_detection_service
from fridge_detection_service import get_fridge_detection_service
from face_recognition_service import get_face_recognition_service
from deepface import DeepFace

try:
    import choking_detector_bridge as choking_bridge  # noqa: F401 — Silver/Nanny/Nurse choking
except Exception as _ceb:
    print(f"[CHOKING-BRIDGE] Optional module unavailable: {_ceb}")
    choking_bridge = None

try:
    import silver_fall_detection_bridge as silver_fall_bridge  # noqa: E402 — Fall on monitor JPEG (Silver/Nanny/Nurse)
except Exception as _sfb_e:
    print(f"[SILVER-FALL-BRIDGE] Optional module unavailable: {_sfb_e}")
    silver_fall_bridge = None

try:
    import food_left_out_bridge as food_bridge  # noqa: E402 — Food left out (always-on, any/no mode)
except Exception as _flb_e:
    print(f"[FOOD-BRIDGE] Optional module unavailable: {_flb_e}")
    food_bridge = None

try:
    import sharp_objects_bridge as sharp_bridge  # noqa: E402 — Sharp objects (Nanny mode only)
except Exception as _shb_e:
    print(f"[SHARP-BRIDGE] Optional module unavailable: {_shb_e}")
    sharp_bridge = None

try:
    import door_window_bridge as door_window_bridge_mod  # noqa: E402 — Door/Window OPEN (Home Alone only)
except Exception as _dwb_e:
    print(f"[DOORWIN-BRIDGE] Optional module unavailable: {_dwb_e}")
    door_window_bridge_mod = None

try:
    import pet_station_bridge as pet_station_bridge_mod  # noqa: E402 — IoT pet feeder (independent)
except Exception as _psb_e:
    print(f"[PET-STATION-BRIDGE] Optional module unavailable: {_psb_e}")
    pet_station_bridge_mod = None

try:
    import bed_exit_bridge  # noqa: E402 — Bed exit (Nurse mode only)
except Exception as _beb_e:
    print(f"[BED-EXIT-BRIDGE] Optional module unavailable: {_beb_e}")
    bed_exit_bridge = None

try:
    import pests_bridge  # noqa: E402 — Pest/wildlife (Insect, Lizard, Rodent)
except Exception as _pest_e:
    print(f"[PESTS-BRIDGE] Optional module unavailable: {_pest_e}")
    pests_bridge = None

try:
    import lost_item_service  # noqa: E402 — Lost item tracker (all modes)
except Exception as _li_e:
    print(f"[LOST-ITEM] Optional module unavailable: {_li_e}")
    lost_item_service = None

try:
    import hazard_area_bridge  # noqa: E402 — Hazard proximity (Nanny + Pet, COCO)
except Exception as _hab_e:
    print(f"[HAZARD-BRIDGE] Optional module unavailable: {_hab_e}")
    hazard_area_bridge = None

try:
    import stuck_in_a_room_bridge  # noqa: E402 — Stuck in room (Nanny + Pet)
except Exception as _sir_e:
    print(f"[STUCK-BRIDGE] Optional module unavailable: {_sir_e}")
    stuck_in_a_room_bridge = None

try:
    import sleep_detection_bridge  # noqa: E402 — Sleep/wake (Silver mode only)
except Exception as _sdb_e:
    print(f"[SLEEP-BRIDGE] Optional module unavailable: {_sdb_e}")
    sleep_detection_bridge = None

import shutil
import requests
from collections import deque
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

# Security configuration
SECRET_KEY = os.getenv("SECRET_KEY", "your-secret-key-please-change-in-production")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

# Password hashing
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="api/login")
oauth2_scheme_optional = OAuth2PasswordBearer(tokenUrl="api/login", auto_error=False)

# Load environment variables from server/.env (same folder as this file)
load_dotenv(Path(__file__).resolve().parent / ".env")

# Startup and shutdown events
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    # Initialize database
    try:
        # Load all AI models at startup to avoid delay during first request
        print("[STARTUP] Pre-loading AI models...")
        get_fire_detection_service()
        get_exit_detection_service()
        get_stillness_detection_service()
        get_pet_detection_service()
        get_fridge_detection_service()
        get_face_recognition_service()
        if food_bridge is not None:
            try:
                food_bridge.preload()
                print("[FOOD] startup: ENABLED — always-on food-left-out (any/no mode).")
            except Exception as _food_pre_e:
                print(f"[FOOD] startup: preload failed: {_food_pre_e}")
        else:
            print("[FOOD] startup: DISABLED — import failed (see earlier [FOOD-BRIDGE] line).")
        if sharp_bridge is not None:
            try:
                sharp_bridge.preload()
                print("[SHARP] startup: ENABLED — sharp-objects (Nanny mode only).")
            except Exception as _sharp_pre_e:
                print(f"[SHARP] startup: preload failed: {_sharp_pre_e}")
        else:
            print("[SHARP] startup: DISABLED — import failed (see earlier [SHARP-BRIDGE] line).")
        if door_window_bridge_mod is not None:
            try:
                door_window_bridge_mod.preload()
                print("[DOORWIN] startup: ENABLED — door/window OPEN (Home Alone only).")
            except Exception as _dw_pre_e:
                print(f"[DOORWIN] startup: preload failed: {_dw_pre_e}")
        else:
            print("[DOORWIN] startup: DISABLED — import failed (see earlier [DOORWIN-BRIDGE] line).")
        if pet_station_bridge_mod is not None:
            try:
                pet_station_bridge_mod.preload()
                print("[PET-STATION] startup: ENABLED — IoT feeder cat/dog detection.")
            except Exception as _ps_pre_e:
                print(f"[PET-STATION] startup: preload failed: {_ps_pre_e}")
        else:
            print("[PET-STATION] startup: DISABLED — import failed (see earlier [PET-STATION-BRIDGE] line).")
        if bed_exit_bridge is not None:
            try:
                bed_exit_bridge.preload()
                print("[BED-EXIT] startup: ENABLED — bed exit detection (Nurse mode only).")
            except Exception as _be_pre_e:
                print(f"[BED-EXIT] startup: preload failed: {_be_pre_e}")
        else:
            print("[BED-EXIT] startup: DISABLED — import failed (see earlier [BED-EXIT-BRIDGE] line).")
        if pests_bridge is not None:
            try:
                pests_bridge.preload()
                print("[PESTS] startup: ENABLED — all modes (Silver/Nanny/Nurse/Pet/Home alone).")
            except Exception as _pest_pre_e:
                print(f"[PESTS] startup: preload failed: {_pest_pre_e}")
        else:
            print("[PESTS] startup: DISABLED — import failed (see earlier [PESTS-BRIDGE] line).")
        if lost_item_service is not None:
            try:
                lost_item_service.preload()
                print("[LOST-ITEM] startup: ENABLED — all modes (item location + screenshots).")
            except Exception as _li_pre_e:
                print(f"[LOST-ITEM] startup: preload failed: {_li_pre_e}")
        else:
            print("[LOST-ITEM] startup: DISABLED — import failed (see earlier [LOST-ITEM] line).")
        if hazard_area_bridge is not None:
            try:
                hazard_area_bridge.preload()
                print("[HAZARD] startup: ENABLED — COCO hazards on Nanny + Pet monitor streams.")
            except Exception as _hab_pre_e:
                print(f"[HAZARD] startup: preload failed: {_hab_pre_e}")
        else:
            print("[HAZARD] startup: DISABLED — import failed (see earlier [HAZARD-BRIDGE] line).")
        if stuck_in_a_room_bridge is not None:
            try:
                stuck_in_a_room_bridge.preload()
                print("[STUCK] startup: ENABLED — stuck-in-room on Nanny + Pet monitor streams.")
            except Exception as _sir_pre_e:
                print(f"[STUCK] startup: preload failed: {_sir_pre_e}")
        else:
            print("[STUCK] startup: DISABLED — import failed (see earlier [STUCK-BRIDGE] line).")
        if sleep_detection_bridge is not None:
            try:
                sleep_detection_bridge.preload()
                print("[SLEEP] startup: ENABLED — fell asleep / woke up (Silver mode only).")
            except Exception as _sdb_pre_e:
                print(f"[SLEEP] startup: preload failed: {_sdb_pre_e}")
        else:
            print("[SLEEP] startup: DISABLED — import failed (see earlier [SLEEP-BRIDGE] line).")
        print("[STARTUP] All AI models loaded.")
        if choking_bridge is None:
            print(
                "[CHOKING] startup: DISABLED — import failed (see earlier [CHOKING-BRIDGE] line)."
            )
        else:
            print(
                "[CHOKING] startup: ENABLED — logs when gates pass appear as [CHOKING-DIAG] every ~20s."
            )
        _ff = _resolve_ffmpeg_bin()
        if _ff:
            print(f"[STARTUP] ffmpeg: {_ff}")
        else:
            print(
                "[STARTUP] ffmpeg: NOT FOUND — clips may stay as WebM; "
                "set FFMPEG_PATH in server/.env to ffmpeg.exe"
            )
        if not _CLIP_CRYPTO_READY:
            print(
                "[STARTUP] pycryptodome missing — install with: pip install pycryptodome "
                "(needed to decode mobile-encrypted clips on the server)"
            )
        conn = get_db_connection()
        cursor = conn.cursor()
        # Create table with profile_image column
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id SERIAL PRIMARY KEY,
                name VARCHAR(255) NOT NULL,
                email VARCHAR(255) UNIQUE,
                phone VARCHAR(50),
                password_hash VARCHAR(255),
                profile_image VARCHAR(500),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        # Add profile_image column if it doesn't exist (for existing tables)
        cursor.execute("""
            DO $$ 
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns 
                    WHERE table_name='users' AND column_name='profile_image'
                ) THEN
                    ALTER TABLE users ADD COLUMN profile_image VARCHAR(500);
                END IF;
            END $$;
        """)
        # Add password_hash column if it doesn't exist (for existing tables)
        cursor.execute("""
            DO $$ 
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns 
                    WHERE table_name='users' AND column_name='password_hash'
                ) THEN
                    ALTER TABLE users ADD COLUMN password_hash VARCHAR(255);
                END IF;
            END $$;
        """)
        # Add email unique constraint if it doesn't exist
        try:
            cursor.execute("""
                ALTER TABLE users ADD CONSTRAINT users_email_key UNIQUE (email);
            """)
        except psycopg2.errors.DuplicateTable:
            conn.rollback()
        except Exception:
            conn.rollback()

        # Add is_verified column if it doesn't exist
        cursor.execute("""
            DO $$ 
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns 
                    WHERE table_name='users' AND column_name='is_verified'
                ) THEN
                    ALTER TABLE users ADD COLUMN is_verified BOOLEAN DEFAULT FALSE;
                END IF;
            END $$;
        """)

        # Create otp_codes table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS otp_codes (
                id SERIAL PRIMARY KEY,
                email VARCHAR(255) NOT NULL,
                code VARCHAR(6) NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        conn.commit()

        # Add role column if it doesn't exist
        cursor.execute("""
            DO $$ 
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns 
                    WHERE table_name='users' AND column_name='role'
                ) THEN
                    ALTER TABLE users ADD COLUMN role VARCHAR(50) DEFAULT 'user';
                END IF;
            END $$;
        """)

        # Create user_options table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS user_options (
                id SERIAL PRIMARY KEY,
                user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
                theme VARCHAR(50) DEFAULT 'light',
                notifications_enabled BOOLEAN DEFAULT TRUE,
                language VARCHAR(10) DEFAULT 'en',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(user_id)
            )
        """)

        # Create user_events table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS user_events (
                id SERIAL PRIMARY KEY,
                user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
                title VARCHAR(255) NOT NULL,
                description TEXT,
                event_type VARCHAR(50),
                video_path VARCHAR(500),
                room_name VARCHAR(100),
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # Add video_path and room_name columns if they don't exist
        cursor.execute("""
            DO $$ 
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns 
                    WHERE table_name='user_events' AND column_name='video_path'
                ) THEN
                    ALTER TABLE user_events ADD COLUMN video_path VARCHAR(500);
                END IF;
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns 
                    WHERE table_name='user_events' AND column_name='room_name'
                ) THEN
                    ALTER TABLE user_events ADD COLUMN room_name VARCHAR(100);
                END IF;
            END $$;
        """)

        # --- NEW ONBOARDING TABLES ---
        
        # 1. Family Members Table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS family_members (
                id SERIAL PRIMARY KEY,
                user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
                name VARCHAR(255) NOT NULL,
                relationship VARCHAR(100),
                phone VARCHAR(50),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        cursor.execute("""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'family_members' AND column_name = 'invite_code_hash'
                ) THEN
                    ALTER TABLE family_members ADD COLUMN invite_code_hash VARCHAR(128);
                END IF;
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'family_members' AND column_name = 'invite_consumed_at'
                ) THEN
                    ALTER TABLE family_members ADD COLUMN invite_consumed_at TIMESTAMP;
                END IF;
            END $$;
        """)

        cursor.execute("""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'owner_user_id'
                ) THEN
                    ALTER TABLE users ADD COLUMN owner_user_id INTEGER REFERENCES users(id) ON DELETE CASCADE;
                END IF;
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'family_member_id'
                ) THEN
                    ALTER TABLE users ADD COLUMN family_member_id INTEGER;
                END IF;
            END $$;
        """)

        # 2. Trusted Persons Table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS trusted_persons (
                id SERIAL PRIMARY KEY,
                user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
                name VARCHAR(255) NOT NULL,
                relationship VARCHAR(100),
                phone VARCHAR(50),
                email VARCHAR(255),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        cursor.execute("""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public'
                      AND table_name = 'trusted_persons'
                      AND column_name = 'email'
                ) THEN
                    ALTER TABLE trusted_persons ADD COLUMN email VARCHAR(255);
                END IF;
            END $$;
        """)

        # 3. Member Photos Table (for AI recognition)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS member_photos (
                id SERIAL PRIMARY KEY,
                member_id INTEGER NOT NULL,
                member_type VARCHAR(20) NOT NULL, -- 'family', 'trusted', or 'pet'
                photo_path VARCHAR(500) NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # 4. Pets Table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS pets (
                id SERIAL PRIMARY KEY,
                user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
                name VARCHAR(255) NOT NULL,
                age VARCHAR(50),
                breed VARCHAR(100),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # 5. Pet Photos Table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS pet_photos (
                id SERIAL PRIMARY KEY,
                pet_id INTEGER REFERENCES pets(id) ON DELETE CASCADE,
                photo_path VARCHAR(500) NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # 6. Enhance user_options for monitoring modes and skips
        cursor.execute("""
            DO $$ 
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns 
                    WHERE table_name='user_options' AND column_name='selected_modes'
                ) THEN
                    ALTER TABLE user_options ADD COLUMN selected_modes JSONB DEFAULT '[]';
                END IF;
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns 
                    WHERE table_name='user_options' AND column_name='onboarding_skips'
                ) THEN
                    ALTER TABLE user_options ADD COLUMN onboarding_skips JSONB DEFAULT '[]';
                END IF;
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns 
                    WHERE table_name='user_options' AND column_name='email_notifications_enabled'
                ) THEN
                    ALTER TABLE user_options ADD COLUMN email_notifications_enabled BOOLEAN DEFAULT FALSE;
                END IF;
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns 
                    WHERE table_name='user_options' AND column_name='in_app_alerts_enabled'
                ) THEN
                    ALTER TABLE user_options ADD COLUMN in_app_alerts_enabled BOOLEAN DEFAULT TRUE;
                END IF;
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns 
                    WHERE table_name='user_options' AND column_name='recording_retention_days'
                ) THEN
                    ALTER TABLE user_options ADD COLUMN recording_retention_days INTEGER DEFAULT 30;
                END IF;
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name='user_options' AND column_name='network_route_mode'
                ) THEN
                    ALTER TABLE user_options ADD COLUMN network_route_mode VARCHAR(20) DEFAULT 'home';
                END IF;
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name='user_options' AND column_name='api_base_home_url'
                ) THEN
                    ALTER TABLE user_options ADD COLUMN api_base_home_url TEXT;
                END IF;
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name='user_options' AND column_name='api_base_tunnel_url'
                ) THEN
                    ALTER TABLE user_options ADD COLUMN api_base_tunnel_url TEXT;
                END IF;
            END $$;
        """)

        # 7. Create user_camera_assignments table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS user_camera_assignments (
                id SERIAL PRIMARY KEY,
                user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
                room_name VARCHAR(100) NOT NULL,
                camera_id VARCHAR(255) NOT NULL,
                camera_name VARCHAR(255),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(user_id, room_name)
            )
        """)
        # Migrate legacy single-row-per-user constraint to per-(user, room) uniqueness
        cursor.execute("""
            DO $$ BEGIN
                IF EXISTS (
                    SELECT 1 FROM pg_constraint
                    WHERE conname = 'user_camera_assignments_user_id_key'
                ) THEN
                    ALTER TABLE user_camera_assignments
                    DROP CONSTRAINT user_camera_assignments_user_id_key;
                END IF;
            EXCEPTION WHEN undefined_object THEN NULL;
            END $$;
        """)
        cursor.execute("""
            DO $$ BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM pg_constraint
                    WHERE conname = 'user_camera_assignments_user_id_room_name_key'
                ) THEN
                    ALTER TABLE user_camera_assignments
                    ADD CONSTRAINT user_camera_assignments_user_id_room_name_key
                    UNIQUE (user_id, room_name);
                END IF;
            EXCEPTION WHEN duplicate_object THEN NULL;
            END $$;
        """)
        cursor.execute("""
            DO $$ BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public'
                      AND table_name = 'user_camera_assignments'
                      AND column_name = 'monitor_modes'
                ) THEN
                    ALTER TABLE user_camera_assignments
                    ADD COLUMN monitor_modes JSONB DEFAULT '[]'::jsonb;
                END IF;
            END $$;
        """)

        # FCM device tokens (owner + family accounts that use the mobile app)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS user_fcm_tokens (
                id SERIAL PRIMARY KEY,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                token TEXT NOT NULL,
                platform VARCHAR(20),
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(user_id, token)
            )
        """)

        # IoT Pet Station (ESP32 feeder + ESP32-CAM) — one row per home owner
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS pet_station_devices (
                id SERIAL PRIMARY KEY,
                user_id INTEGER NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
                device_token VARCHAR(64) NOT NULL UNIQUE,
                cam_ip VARCHAR(45),
                main_ip VARCHAR(45),
                last_seen TIMESTAMP,
                last_detection JSONB DEFAULT '{}'::jsonb,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        conn.commit()
        cursor.close()
        conn.close()
        print("Users table ready")
    except psycopg2.Error as e:
        print(f"Error creating table: {e}")
    
    # Initialize fire detection service (load model)
    try:
        service = get_fire_detection_service()
        print("Fire detection model loaded successfully")
    except Exception as e:
        print(f"Warning: Failed to load fire detection model: {e}")
    
    # Door/window OPEN detection (HomeAlone mode) is preloaded via door_window_bridge_mod above.

    # One-time migration: lift any legacy flat known_faces/<name>/ folders
    # into per-user namespaced known_faces/user_<id>/<name>/ folders.
    try:
        migrate_known_faces_to_per_user()
    except Exception as e:
        print(f"[MIGRATION] Unexpected failure (continuing anyway): {e}")

    try:
        init_firebase_messaging()
    except Exception as e:
        print(f"[FCM] init skipped: {e}")

    yield
    
    # Shutdown
    pass

app = FastAPI(title="HomeGuardian API", lifespan=lifespan)

# Create uploads directory if it doesn't exist
UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)

# Serve uploaded images
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

# WebSocket connection manager for mobile clients
import json

# Version marker to verify update
SERVER_VERSION = "2.3.0-SPAM-PROTECTION"
print(f"!!! STARTING HOMEGUARDIAN SERVER VERSION: {SERVER_VERSION} !!!")

# Track active monitoring sessions (user_id -> dict of room_name -> camera_id)
active_monitoring_sessions: dict[int, dict[str, str]] = {}

# Track active cameras per user (user_id -> dict of camera_id -> info)
# camera info: {"name": str, "last_seen": datetime}
active_user_cameras: dict[int, dict[str, dict]] = {}

# Cooldown management to prevent event spam
# user_id -> last_event_timestamp
event_cooldowns: dict[int, datetime] = {}
COOLDOWN_SECONDS = 10  # Wait 10 seconds before allowing another event for the same user

# Choking heuristic (Silver / Nanny / Nurse): min time between websocket/persisted alerts per user+room
last_choking_alert_ts: Dict[Tuple[int, str], datetime] = {}
CHOKING_ALERT_MIN_INTERVAL_SEC = 90

# Fall on laptop-monitor stream (Silver/Nanny/Nurse); one throttle per (user, room)
last_silver_fall_alert_ts: Dict[Tuple[int, str], datetime] = {}
SILVER_FALL_ALERT_MIN_INTERVAL_SEC = 90

# Food left out (always-on, any/no mode); one throttle per (user, room)
last_food_alert_ts: Dict[Tuple[int, str], datetime] = {}
FOOD_ALERT_MIN_INTERVAL_SEC = 90

# Bed exit (Nurse mode); bridge also applies model ALERT_COOLDOWN_SEC per room
last_bed_exit_alert_ts: Dict[Tuple[int, str], datetime] = {}
BED_EXIT_ALERT_MIN_INTERVAL_SEC = 60
bed_exit_recording_armed: Dict[Tuple[int, str], datetime] = {}

# Pest detection (always-on when monitoring); throttle per (user, room)
last_pest_alert_ts: Dict[Tuple[int, str], datetime] = {}
PEST_ALERT_MIN_INTERVAL_SEC = 90

# Stuck in room (Nanny + Pet); throttle per (user, room)
last_stuck_in_room_alert_ts: Dict[Tuple[int, str], datetime] = {}
STUCK_IN_ROOM_ALERT_MIN_INTERVAL_SEC = 90

PET_STATION_ROOM = "Pet Station"
pet_station_event_history: Dict[int, deque] = {}
PET_STATION_EVENT_HISTORY_MAX = 30
_pet_station_snapshot_lock = asyncio.Lock()

# Periodic laptop-monitor heartbeat for troubleshooting choking / exit (no spam).
_choking_live_last_diag: datetime = datetime.min
_exit_live_last_diag: datetime = datetime.min
LEGACY_SILVER_CACHE_SEC = 45
_legacy_user_silver_from_options: Dict[int, tuple[bool, datetime]] = {}
_legacy_user_nanny_from_options: Dict[int, tuple[bool, datetime]] = {}
_legacy_user_nurse_from_options: Dict[int, tuple[bool, datetime]] = {}


def user_has_legacy_silver_in_options(user_id: int) -> bool:
    """True if user saved Silver Mode in app settings (selected_modes titles)."""
    now = datetime.now()
    tup = _legacy_user_silver_from_options.get(user_id)
    if tup is not None and (now - tup[1]).total_seconds() < LEGACY_SILVER_CACHE_SEC:
        return tup[0]
    picked = False
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "SELECT selected_modes FROM user_options WHERE user_id = %s", (user_id,)
        )
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        if row and row.get("selected_modes"):
            modes = row["selected_modes"]
            if isinstance(modes, str):
                try:
                    modes = json.loads(modes)
                except Exception:
                    modes = []
            if isinstance(modes, list):
                for mode in modes:
                    title = ""
                    if isinstance(mode, str):
                        title = mode
                    elif isinstance(mode, dict):
                        title = str(mode.get("title") or "")
                    if "silver" in title.lower():
                        picked = True
                        break
    except Exception as e:
        print(f"[CHOKING] legacy silver lookup failed: {e}")
    _legacy_user_silver_from_options[user_id] = (picked, now)
    return picked


def user_has_legacy_nanny_in_options(user_id: int) -> bool:
    """True if user saved Nanny Mode in app settings (selected_modes titles)."""
    now = datetime.now()
    tup = _legacy_user_nanny_from_options.get(user_id)
    if tup is not None and (now - tup[1]).total_seconds() < LEGACY_SILVER_CACHE_SEC:
        return tup[0]
    picked = False
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "SELECT selected_modes FROM user_options WHERE user_id = %s", (user_id,)
        )
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        if row and row.get("selected_modes"):
            modes = row["selected_modes"]
            if isinstance(modes, str):
                try:
                    modes = json.loads(modes)
                except Exception:
                    modes = []
            if isinstance(modes, list):
                for mode in modes:
                    title = ""
                    if isinstance(mode, str):
                        title = mode
                    elif isinstance(mode, dict):
                        title = str(mode.get("title") or "")
                    if "nanny" in title.lower():
                        picked = True
                        break
    except Exception as e:
        print(f"[CHOKING] legacy nanny lookup failed: {e}")
    _legacy_user_nanny_from_options[user_id] = (picked, now)
    return picked


def user_has_legacy_nurse_in_options(user_id: int) -> bool:
    """True if user saved Nurse Mode in app settings (selected_modes titles)."""
    now = datetime.now()
    tup = _legacy_user_nurse_from_options.get(user_id)
    if tup is not None and (now - tup[1]).total_seconds() < LEGACY_SILVER_CACHE_SEC:
        return tup[0]
    picked = False
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "SELECT selected_modes FROM user_options WHERE user_id = %s", (user_id,)
        )
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        if row and row.get("selected_modes"):
            modes = row["selected_modes"]
            if isinstance(modes, str):
                try:
                    modes = json.loads(modes)
                except Exception:
                    modes = []
            if isinstance(modes, list):
                for mode in modes:
                    title = ""
                    if isinstance(mode, str):
                        title = mode
                    elif isinstance(mode, dict):
                        title = str(mode.get("title") or "")
                    if "nurse" in title.lower():
                        picked = True
                        break
    except Exception as e:
        print(f"[CHOKING] legacy nurse lookup failed: {e}")
    _legacy_user_nurse_from_options[user_id] = (picked, now)
    return picked


# Multi-frame validation for sharp objects
# user_id -> dict of room_name -> consecutive_detections
sharp_object_frames: dict[int, dict[str, int]] = {}
SHARP_OBJECT_THRESHOLD = 1  # Single confident frame is enough (faster detection)

# Face Recognition Smoothing
# user_id -> dict of room_name -> consecutive_stranger_detections
stranger_frame_counts: dict[int, dict[str, int]] = {}
STRANGER_ALERT_THRESHOLD = 3 # Must see stranger for 3 frames

# user_id -> dict of room_name -> dict[member_name -> consecutive_known_detections]
# Used to require multiple consecutive frames before "locking" identity to a known member
known_member_frame_counts: dict[int, dict[str, dict[str, int]]] = {}
KNOWN_MEMBER_CONSENSUS_THRESHOLD = 2 # Need 2 frames in a row to confirm a known match

# user_id -> dict of room_name -> last_time_known_member_seen
room_last_known_seen: dict[int, dict[str, datetime]] = {}
KNOWN_MEMBER_STICKINESS_SECONDS = 15 # 15s window where ambiguous frames are treated as "still known"

# Family 'At Home' status tracking
# user_id -> dict of member_name -> {"last_seen": datetime, "status": str}
family_home_status: dict[int, dict[str, dict]] = {}
HOME_TIMEOUT_MINUTES = 5 # If not seen for 5 mins, they are 'Away'

# Throttle WebSocket pushes when laptop/video monitoring updates at-home presence
presence_ws_last_sent: dict[int, datetime] = {}
PRESENCE_WS_MIN_INTERVAL_SEC = 2.0

# Recording state management
recording_tasks: dict[int, asyncio.Task] = {}

async def record_event_clip(user_id: int, event_id: int, initial_frame: bytes):
    """
    This function now only handles the 'wait' period.
    The actual video recording is done by the laptop browser for high quality.
    """
    print(f"[RECORDING] Waiting 5s for laptop to finish video capture for event {event_id}")
    
    try:
        # Wait for the laptop to finish its 5s recording
        await asyncio.sleep(7) # 5s recording + 2s upload buffer
        
        # Check if the video was uploaded
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute("SELECT video_path FROM user_events WHERE id = %s", (event_id,))
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        
        if row and row['video_path']:
            print(f"[RECORDING] Video confirmed for event {event_id}: {row['video_path']}")
            # Notify mobile client that the real video is ready
            await manager.broadcast_to_user(user_id, {
                "type": "recording_ready",
                "event_id": event_id,
                "video_url": row['video_path']
            })
        else:
            print(f"[RECORDING] Warning: No video uploaded by laptop for event {event_id}")
        
    except Exception as e:
        print(f"[RECORDING] Error: {e}")
    finally:
        recording_tasks.pop(event_id, None)

class ConnectionManager:
    def __init__(self):
        # Map user_id to a set of active WebSockets for that user
        self.active_connections: dict[int, set[WebSocket]] = {}
    
    async def send_json_safe(self, websocket: WebSocket, message: dict):
        """Helper to send JSON safely even if it contains datetime objects"""
        def datetime_handler(obj):
            if isinstance(obj, datetime):
                return obj.isoformat()
            raise TypeError(f"Object of type {type(obj)} is not JSON serializable")
            
        json_data = json.dumps(message, default=datetime_handler)
        await websocket.send_text(json_data)

    async def connect_socket(self, websocket: WebSocket, user_id: int):
        if user_id not in self.active_connections:
            self.active_connections[user_id] = set()
        self.active_connections[user_id].add(websocket)
        print(f"[{SERVER_VERSION}] User {user_id} connected via WebSocket. Active User Devices: {len(self.active_connections[user_id])}")
    
    def disconnect(self, websocket: WebSocket, user_id: int):
        if user_id in self.active_connections:
            self.active_connections[user_id].discard(websocket)
            if not self.active_connections[user_id]:
                del self.active_connections[user_id]
        print(f"[{SERVER_VERSION}] User {user_id} disconnected.")
    
    async def broadcast_to_user(self, user_id: int, message: dict):
        """Broadcast message to all devices belonging to a specific user"""
        if user_id in self.active_connections:
            user_sockets = self.active_connections[user_id]
            disconnected = set()
            print(f"[{SERVER_VERSION}] Broadcasting to {len(user_sockets)} device(s) for user {user_id}")
            for connection in list(user_sockets):
                try:
                    await self.send_json_safe(connection, message)
                except Exception as e:
                    print(f"[{SERVER_VERSION}] Error sending to device for user {user_id}: {e}")
                    disconnected.add(connection)
            
            # Remove disconnected clients
            for conn in disconnected:
                self.disconnect(conn, user_id)

    async def broadcast_fire_alert(self, message: dict):
        """Broadcast fire detection alert to ALL connected mobile clients (Legacy/Global)"""
        for uid in list(self.active_connections.keys()):
            await self.broadcast_to_user(uid, message)

manager = ConnectionManager()

# Mobile live preview only (WebSocket). Full /api/laptop-monitor path is unchanged for the dashboard.
remote_frame_last_sent: dict[tuple[int, str], float] = {}
remote_preview_frame_last_sent: dict[tuple[int, str], float] = {}
REMOTE_FRAME_MIN_INTERVAL_SEC = 0.25  # coarser throttle for full JPEGs from /api/laptop-monitor
REMOTE_PREVIEW_MIN_INTERVAL_SEC = 0.1  # faster throttle for small previews from /api/laptop-preview


async def maybe_broadcast_remote_preview(
    user_id: int, room_label: str, jpeg_bytes: bytes, *, preview_lane: bool = False
) -> None:
    try:
        now = time.time()
        key = (user_id, room_label)
        if preview_lane:
            last_map = remote_preview_frame_last_sent
            min_interval = REMOTE_PREVIEW_MIN_INTERVAL_SEC
        else:
            last_map = remote_frame_last_sent
            min_interval = REMOTE_FRAME_MIN_INTERVAL_SEC
        last = last_map.get(key, 0.0)
        if now - last < min_interval:
            return
        last_map[key] = now
        preview_b64 = base64.b64encode(jpeg_bytes).decode("ascii")
        await manager.broadcast_to_user(
            user_id,
            {
                "type": "remote_frame",
                "room_name": room_label,
                "frame": preview_b64,
            },
        )
    except Exception as e:
        print(f"[remote_frame] broadcast skipped: {e}")

# Request logging middleware
@app.middleware("http")
async def log_requests(request, call_next):
    print(f"[DEBUG] Incoming: {request.method} {request.url.path}")
    response = await call_next(request)
    print(f"[DEBUG] Response: {response.status_code} for {request.url.path}")
    return response

# CORS middleware to allow Flutter app to connect
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify your Flutter app's origin
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Database configuration
DB_CONFIG = {
    "user": os.getenv("DB_USER", "postgres"),
    "host": os.getenv("DB_HOST", "localhost"),
    "database": os.getenv("DB_NAME", "homeguardian"),
    "password": os.getenv("DB_PASSWORD", "postgres"),
    "port": os.getenv("DB_PORT", "5432"),
}

# Pydantic models for request/response
class UserCreate(BaseModel):
    name: str
    email: str
    password: str
    phone: Optional[str] = None
    profile_images: list[str] = [] # Changed from profile_image to profile_images
    is_dashboard: Optional[bool] = False # Flag to trigger OTP flow

    @validator('password')
    def password_length(cls, v):
        if len(v.encode('utf-8')) > 72:
            raise ValueError('Password must be less than 72 bytes')
        return v

class OTPVerify(BaseModel):
    email: str
    otp: str

class UserLogin(BaseModel):
    email: str
    password: str
    is_dashboard: Optional[bool] = False # Flag to trigger OTP flow

class FamilyInviteLookupRequest(BaseModel):
    code: str

class FamilyJoinRequest(BaseModel):
    code: str
    email: str
    password: str

    @validator('password')
    def password_length(cls, v):
        if len(v.encode('utf-8')) > 72:
            raise ValueError('Password must be less than 72 bytes')
        return v

class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str

    @validator('new_password')
    def new_password_rules(cls, v):
        if len(v.encode('utf-8')) > 72:
            raise ValueError('Password must be less than 72 bytes')
        if len(v) < 8:
            raise ValueError('Password must be at least 8 characters')
        return v


class VerifyPasswordRequest(BaseModel):
    password: str


class SetFaceLoginPhotoRequest(BaseModel):
    image_base64: str


class ClearFaceLoginRequest(BaseModel):
    password: str


class FcmTokenRegister(BaseModel):
    token: str
    platform: Optional[str] = "android"


class Token(BaseModel):
    access_token: str
    token_type: str
    user: dict

class UserResponse(BaseModel):
    id: int
    name: str
    email: Optional[str]
    phone: Optional[str]
    profile_image: Optional[str]
    created_at: datetime
    is_verified: Optional[bool] = True
    role: Optional[str] = "user"
    owner_user_id: Optional[int] = None
    family_member_id: Optional[int] = None

class FamilyMemberCreate(BaseModel):
    name: str
    relationship: str
    phone: str
    photos: list[str] = [] # list of base64 images

class FamilyMemberUpdate(BaseModel):
    name: Optional[str] = None
    relationship: Optional[str] = None
    phone: Optional[str] = None

class TrustedPersonCreate(BaseModel):
    name: str
    relationship: str
    phone: str
    email: str
    photos: list[str] = []  # optional legacy face-enrollment photos

class TrustedPersonUpdate(BaseModel):
    name: Optional[str] = None
    relationship: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None

class PetCreate(BaseModel):
    name: str
    age: str
    breed: Optional[str] = None
    photos: list[str] = [] # list of base64 images

# Email configuration
EMAIL_HOST = os.getenv("EMAIL_HOST", "smtp.gmail.com")
EMAIL_PORT = int(os.getenv("EMAIL_PORT", "587"))
EMAIL_HOST_USER = os.getenv("EMAIL_HOST_USER")
EMAIL_HOST_PASSWORD = os.getenv("EMAIL_HOST_PASSWORD")

def send_otp_email(recipient_email: str, otp_code: str):
    """Send a real email with the OTP code"""
    if not EMAIL_HOST_USER or not EMAIL_HOST_PASSWORD:
        print(f"\n[WARNING] Email credentials not set! OTP for {recipient_email} is: {otp_code}\n")
        return False

    try:
        # Create message
        message = MIMEMultipart()
        message["From"] = f"HomeGuardian <{EMAIL_HOST_USER}>"
        message["To"] = recipient_email
        message["Subject"] = "Your HomeGuardian Verification Code"

        body = f"""
        <html>
        <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
            <div style="max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #ddd; border-radius: 10px;">
                <h2 style="color: #4CAF50; text-align: center;">Welcome to HomeGuardian!</h2>
                <p>Hello,</p>
                <p>Thank you for choosing HomeGuardian. To complete your dashboard setup, please use the following 6-digit verification code:</p>
                <div style="background: #f4f4f4; padding: 20px; text-align: center; font-size: 32px; font-weight: bold; letter-spacing: 5px; margin: 20px 0; border-radius: 5px; color: #000;">
                    {otp_code}
                </div>
                <p>This code will expire shortly. If you did not request this code, please ignore this email.</p>
                <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;">
                <p style="font-size: 12px; color: #888; text-align: center;">
                    &copy; 2024 HomeGuardian Security Systems. All rights reserved.
                </p>
            </div>
        </body>
        </html>
        """
        message.attach(MIMEText(body, "html"))

        # Connect and send
        server = smtplib.SMTP(EMAIL_HOST, EMAIL_PORT)
        server.starttls() # Secure the connection
        server.login(EMAIL_HOST_USER, EMAIL_HOST_PASSWORD)
        server.send_message(message)
        server.quit()
        
        print(f"[SUCCESS] OTP email sent to {recipient_email}")
        return True
    except Exception as e:
        print(f"[ERROR] Failed to send email to {recipient_email}: {e}")
        return False


def send_owner_alert_email(
    owner_user_id: int,
    title: str,
    body: str,
    event_type: Optional[str] = None,
    room_name: Optional[str] = None,
) -> bool:
    """Send a security/event alert to the home owner's email only (not family accounts)."""
    if not EMAIL_HOST_USER or not EMAIL_HOST_PASSWORD:
        print("[EMAIL] Alert skipped: EMAIL_HOST_USER / EMAIL_HOST_PASSWORD not set")
        return False
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            """
            SELECT u.email AS email, o.email_notifications_enabled AS email_notifications_enabled
            FROM users u
            LEFT JOIN user_options o ON o.user_id = u.id
            WHERE u.id = %s
            """,
            (owner_user_id,),
        )
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        if not row or not row.get("email"):
            print(f"[EMAIL] Alert skipped: no owner email for user_id={owner_user_id}")
            return False
        if not bool(row.get("email_notifications_enabled")):
            print(
                f"[EMAIL] Alert skipped: email_notifications_enabled off for owner_user_id={owner_user_id}"
            )
            return False

        recipient = row["email"]
        safe_title = (title or "HomeGuardian Alert").replace("<", "")
        safe_body = (body or safe_title).replace("<", "")
        et = (event_type or "").replace("<", "")
        rn = (room_name or "").replace("<", "")

        message = MIMEMultipart()
        message["From"] = f"HomeGuardian <{EMAIL_HOST_USER}>"
        message["To"] = recipient
        message["Subject"] = safe_title[:200]

        html = f"""
        <html>
        <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
            <div style="max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #ddd;
                        border-radius: 10px;">
                <h2 style="color: #c62828;">{safe_title}</h2>
                <p>{safe_body}</p>
                <p style="font-size: 14px; color: #666;">
                  <strong>Type:</strong> {et or "—"}<br/>
                  <strong>Room:</strong> {rn or "—"}
                </p>
                <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;">
                <p style="font-size: 12px; color: #888;">
                  This message was sent to the home owner account only.
                </p>
            </div>
        </body>
        </html>
        """
        message.attach(MIMEText(html, "html"))

        server = smtplib.SMTP(EMAIL_HOST, EMAIL_PORT)
        server.starttls()
        server.login(EMAIL_HOST_USER, EMAIL_HOST_PASSWORD)
        server.send_message(message)
        server.quit()
        print(f"[EMAIL] Owner alert sent to {recipient}")
        return True
    except Exception as e:
        print(f"[EMAIL] Owner alert failed for user_id={owner_user_id}: {e}")
        return False


def _normalize_trusted_email(email: str) -> Optional[str]:
    e = (email or "").strip().lower()
    if not e or "@" not in e:
        return None
    return e


def send_trusted_person_alert_emails(
    owner_user_id: int,
    title: str,
    body: str,
    event_type: Optional[str] = None,
    room_name: Optional[str] = None,
) -> int:
    """Email all trusted contacts for this home owner on critical/emergency events."""
    if not EMAIL_HOST_USER or not EMAIL_HOST_PASSWORD:
        print("[EMAIL] Trusted alerts skipped: EMAIL_HOST_USER / EMAIL_HOST_PASSWORD not set")
        return 0

    et = (event_type or "").strip().lower()
    if et not in ("emergency", "critical"):
        return 0

    sent = 0
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "SELECT name FROM users WHERE id = %s",
            (owner_user_id,),
        )
        owner_row = cursor.fetchone()
        owner_name = (owner_row or {}).get("name") or "HomeGuardian user"

        cursor.execute(
            """
            SELECT name, email, relationship
            FROM trusted_persons
            WHERE user_id = %s AND email IS NOT NULL AND TRIM(email) <> ''
            ORDER BY id ASC
            """,
            (owner_user_id,),
        )
        contacts = cursor.fetchall() or []
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"[EMAIL] Trusted lookup failed for user_id={owner_user_id}: {e}")
        return 0

    if not contacts:
        return 0

    safe_title = (title or "HomeGuardian Emergency Alert").replace("<", "")
    safe_body = (body or safe_title).replace("<", "")
    rn = (room_name or "").replace("<", "")

    for row in contacts:
        recipient = _normalize_trusted_email(row.get("email") or "")
        if not recipient:
            continue
        contact_name = (row.get("name") or "Trusted contact").replace("<", "")
        relationship = (row.get("relationship") or "").replace("<", "")

        try:
            message = MIMEMultipart()
            message["From"] = f"HomeGuardian <{EMAIL_HOST_USER}>"
            message["To"] = recipient
            message["Subject"] = safe_title[:200]

            rel_line = (
                f"<strong>Your relationship:</strong> {relationship}<br/>"
                if relationship
                else ""
            )
            html = f"""
            <html>
            <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
                <div style="max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #ddd;
                            border-radius: 10px;">
                    <h2 style="color: #c62828;">Emergency alert from {owner_name}</h2>
                    <p>Hello {contact_name},</p>
                    <p>{owner_name} has a trusted contact alert from HomeGuardian:</p>
                    <p><strong>{safe_title}</strong></p>
                    <p>{safe_body}</p>
                    <p style="font-size: 14px; color: #666;">
                      <strong>Room:</strong> {rn or "—"}<br/>
                      {rel_line}
                    </p>
                    <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;">
                    <p style="font-size: 12px; color: #888;">
                      You received this because you are listed as a trusted contact.
                      Please check on {owner_name} if you can.
                    </p>
                </div>
            </body>
            </html>
            """
            message.attach(MIMEText(html, "html"))

            server = smtplib.SMTP(EMAIL_HOST, EMAIL_PORT)
            server.starttls()
            server.login(EMAIL_HOST_USER, EMAIL_HOST_PASSWORD)
            server.send_message(message)
            server.quit()
            sent += 1
            print(f"[EMAIL] Trusted alert sent to {recipient} (owner={owner_user_id})")
        except Exception as e:
            print(f"[EMAIL] Trusted alert failed for {recipient}: {e}")

    return sent


# Database connection helper
def get_db_connection():
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        return conn
    except psycopg2.Error as e:
        print(f"Error connecting to database: {e}")
        raise

# Mode Gating Logic (extracted for unit testing)
def get_mode_gating_config(room_modes: Set[str]) -> Dict:
    """
    Decides which AI services and bridges should run based on the active room modes.
    """
    is_home_alone = "home_alone" in room_modes
    is_silver_mode = "silver" in room_modes
    is_nanny_mode = "nanny" in room_modes
    is_nurse_mode = "nurse" in room_modes
    is_pet_mode = "pet" in room_modes
    
    # Services that run in the parallel detection loop
    parallel_services = ["fire", "fridge", "face"]
    if is_silver_mode:
        parallel_services.append("exit")
    if is_nurse_mode or is_silver_mode or is_nanny_mode:
        parallel_services.append("stillness")
    if is_pet_mode:
        parallel_services.append("pet")
        
    # Bridges that run sequentially
    choking_active = is_silver_mode or is_nanny_mode or is_nurse_mode
    sharp_active = is_nanny_mode
    door_window_active = is_home_alone
    food_active = True  # Always on — all modes
    pests_active = True  # Always on — Silver, Nanny, Nurse, Pet, Home alone, or none
    lost_items_active = True  # Always on — track item locations + cropped screenshots
    sleep_monitor_active = is_silver_mode  # Silver only — fell asleep / woke up
    stuck_in_room_active = is_nanny_mode or is_pet_mode
    
    return {
        "is_home_alone": is_home_alone,
        "is_silver_mode": is_silver_mode,
        "is_nanny_mode": is_nanny_mode,
        "is_nurse_mode": is_nurse_mode,
        "is_pet_mode": is_pet_mode,
        "parallel_services": parallel_services,
        "choking_active": choking_active,
        "sharp_active": sharp_active,
        "door_window_active": door_window_active,
        "food_active": food_active,
        "pests_active": pests_active,
        "lost_items_active": lost_items_active,
        "sleep_monitor_active": sleep_monitor_active,
        "stuck_in_room_active": stuck_in_room_active,
    }

def validate_user_options(data: dict) -> dict:
    """
    Validates and filters user options data.
    """
    valid_columns = [
        'theme',
        'notifications_enabled',
        'email_notifications_enabled',
        'in_app_alerts_enabled',
        'language',
        'selected_modes',
        'onboarding_skips',
        'recording_retention_days',
        'network_route_mode',
        'api_base_home_url',
        'api_base_tunnel_url',
    ]
    update_data = {k: v for k, v in data.items() if k in valid_columns}

    if "network_route_mode" in update_data and update_data["network_route_mode"] is not None:
        m = str(update_data["network_route_mode"]).lower().strip()
        if m not in ("home", "tunnel"):
            raise HTTPException(
                status_code=400,
                detail="network_route_mode must be 'home' or 'tunnel'",
            )
        update_data["network_route_mode"] = m
    
    for _url_key in ("api_base_home_url", "api_base_tunnel_url"):
        if _url_key in update_data and update_data[_url_key] is not None:
            s = str(update_data[_url_key]).strip()
            update_data[_url_key] = s if s else None
            
    if "recording_retention_days" in update_data and update_data["recording_retention_days"] is not None:
        try:
            days = int(update_data["recording_retention_days"])
            if days < 0:
                raise ValueError("Must be non-negative")
            update_data["recording_retention_days"] = days
        except (ValueError, TypeError):
             raise HTTPException(
                status_code=400,
                detail="recording_retention_days must be a non-negative integer",
            )
            
    return update_data

# Security Utils
def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password):
    return pwd_context.hash(password)


def hash_invite_code(raw_code: str) -> str:
    return hashlib.sha256(f"{raw_code.strip()}:{SECRET_KEY}".encode()).hexdigest()


def generate_family_invite_code() -> str:
    return secrets.token_urlsafe(12)


def effective_owner_id(user: dict) -> int:
    if user.get("role") == "family" and user.get("owner_user_id"):
        return int(user["owner_user_id"])
    return int(user["id"])


def require_home_owner(user: dict):
    if user.get("role") == "family":
        raise HTTPException(
            status_code=403,
            detail="This action is only available to the home owner.",
        )


def _pet_station_history(user_id: int) -> deque:
    if user_id not in pet_station_event_history:
        pet_station_event_history[user_id] = deque(maxlen=PET_STATION_EVENT_HISTORY_MAX)
    return pet_station_event_history[user_id]


def _generate_pet_station_device_token() -> str:
    return secrets.token_urlsafe(32)


def _lookup_pet_station_device(token: str) -> Optional[dict]:
    if not token or not token.strip():
        return None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "SELECT * FROM pet_station_devices WHERE device_token = %s",
            (token.strip(),),
        )
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        return dict(row) if row else None
    except Exception as e:
        print(f"[PET-STATION] device lookup failed: {e}")
        return None


def _get_pet_station_row(owner_id: int) -> Optional[dict]:
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "SELECT * FROM pet_station_devices WHERE user_id = %s",
            (owner_id,),
        )
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        return dict(row) if row else None
    except Exception as e:
        print(f"[PET-STATION] row lookup failed: {e}")
        return None


async def _pet_station_device_from_request(request: Request) -> dict:
    token = (
        request.headers.get("X-Device-Token")
        or request.headers.get("x-device-token")
        or request.query_params.get("device_token")
    )
    if not token:
        raise HTTPException(status_code=401, detail="Missing X-Device-Token header")
    device = _lookup_pet_station_device(token)
    if not device:
        raise HTTPException(status_code=401, detail="Invalid device token")
    return device


async def _broadcast_pet_station_ws(
    user_id: int,
    ws_type: str,
    message: str,
    event_id: Optional[int] = None,
):
    payload = {
        "type": ws_type,
        "room_name": PET_STATION_ROOM,
        "message": message,
    }
    if event_id is not None:
        payload["event_id"] = event_id
    await manager.broadcast_to_user(user_id, payload)


async def _handle_pet_station_esp32_event(user_id: int, data: dict) -> dict:
    """Persist feeder event + push dashboard websocket alert."""
    event_name = str(data.get("event") or "?")
    state = str(data.get("state") or "?")
    ts = datetime.now().strftime("%H:%M:%S")
    event_str = f"{ts} | {event_name} | state={state}"
    _pet_station_history(user_id).appendleft(event_str)

    lower = event_name.lower()
    if "dispense" in lower:
        ws_type = "food_dispensed"
        title = "Pet food dispensed"
        desc = f"Pet Station dispensed food (state={state})."
    elif "cancel" in lower:
        ws_type = "food_cancelled"
        title = "Pet feeding cancelled"
        desc = f"Pet Station cancelled feeding (state={state})."
    elif "not_eating" in lower or (("eating" in lower) and "not" in lower):
        ws_type = "pet_station_alert"
        title = "Pet not eating"
        desc = f"Pet detected but not eating at the feeder (state={state})."
    elif "eating" in lower:
        ws_type = "pet_station_alert"
        title = "Pet is eating"
        desc = f"Pet is eating at the feeder (state={state})."
    else:
        ws_type = "pet_station_alert"
        title = "Pet Station event"
        desc = f"{event_name} (state={state})"

    new_event = await save_and_broadcast_event(
        user_id=user_id,
        title=title,
        description=desc,
        event_type="pet_station",
        room_name=PET_STATION_ROOM,
    )
    event_id = new_event["id"] if new_event else None
    await _broadcast_pet_station_ws(user_id, ws_type, event_str, event_id)
    return {"ok": True, "logged": event_str}


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=15)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

# Dependency to get current user from JWT
async def get_current_user(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=401,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        email: str = payload.get("sub")
        user_id: int = payload.get("id")
        if email is None or user_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception
        
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
        user = cursor.fetchone()
        cursor.close()
        conn.close()
        
        if user is None:
            raise credentials_exception
        return user
    except Exception:
        raise HTTPException(status_code=500, detail="Database error during authentication")

async def get_current_user_optional(token: Optional[str] = Depends(oauth2_scheme_optional)):
    if not token:
        return None
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: int = payload.get("id")
        if user_id is None:
            return None
            
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
        user = cursor.fetchone()
        cursor.close()
        conn.close()
        
        return user
    except Exception:
        return None

async def get_current_active_admin(current_user: dict = Depends(get_current_user)):
    if current_user.get('role') != 'admin':
        raise HTTPException(status_code=403, detail="The user doesn't have enough privileges")
    return current_user

# User Profile endpoint
@app.get("/api/me", response_model=UserResponse)
async def read_users_me(current_user: dict = Depends(get_current_user)):
    safe = dict(current_user)
    safe.pop("password_hash", None)
    # Family logins: surface enrolled member photo + phone (users row may omit these).
    if safe.get("role") == "family" and safe.get("family_member_id"):
        try:
            conn = get_db_connection()
            cursor = conn.cursor(cursor_factory=RealDictCursor)
            cursor.execute(
                """
                SELECT fm.phone AS fm_phone,
                       (SELECT photo_path FROM member_photos
                        WHERE member_id = fm.id AND member_type = 'family'
                        ORDER BY id ASC LIMIT 1) AS member_photo
                FROM family_members fm
                WHERE fm.id = %s
                """,
                (safe["family_member_id"],),
            )
            row = cursor.fetchone()
            cursor.close()
            conn.close()
            if row:
                if row.get("fm_phone"):
                    safe["phone"] = row["fm_phone"]
                if not safe.get("profile_image") and row.get("member_photo"):
                    safe["profile_image"] = row["member_photo"]
        except Exception as e:
            print(f"[ME] Could not enrich family profile: {e}")
    return safe


@app.post("/api/change-password")
async def change_password(body: ChangePasswordRequest, current_user: dict = Depends(get_current_user)):
    """Verify current password and persist a new password_hash (owners and family accounts)."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute("SELECT password_hash FROM users WHERE id = %s", (current_user["id"],))
        row = cursor.fetchone()
        if not row or not row.get("password_hash"):
            cursor.close()
            conn.close()
            raise HTTPException(
                status_code=400,
                detail="No password is set for this account.",
            )
        if not verify_password(body.current_password, row["password_hash"]):
            cursor.close()
            conn.close()
            raise HTTPException(status_code=401, detail="Current password is incorrect")
        if verify_password(body.new_password, row["password_hash"]):
            cursor.close()
            conn.close()
            raise HTTPException(
                status_code=400,
                detail="New password must be different from your current password",
            )
        new_hash = get_password_hash(body.new_password)
        cursor.execute(
            "UPDATE users SET password_hash = %s WHERE id = %s",
            (new_hash, current_user["id"]),
        )
        conn.commit()
        cursor.close()
        conn.close()
        return {"success": True, "message": "Password updated successfully"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/verify-password")
async def verify_password_route(
    body: VerifyPasswordRequest, current_user: dict = Depends(get_current_user)
):
    """Confirm the home owner's password before sensitive actions (e.g. changing Face ID)."""
    require_home_owner(current_user)
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "SELECT password_hash FROM users WHERE id = %s", (current_user["id"],)
        )
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        if not row or not row.get("password_hash"):
            raise HTTPException(
                status_code=400,
                detail="No password is set for this account.",
            )
        if not verify_password(body.password, row["password_hash"]):
            raise HTTPException(status_code=401, detail="Password is incorrect")
        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/me/face-login-photo")
async def set_face_login_photo(
    body: SetFaceLoginPhotoRequest, current_user: dict = Depends(get_current_user)
):
    """Save a new profile photo, validate a detectable face, and re-enroll for face login."""
    require_home_owner(current_user)
    if not body.image_base64 or not str(body.image_base64).strip():
        raise HTTPException(status_code=400, detail="Image is required")

    user_id = int(current_user["id"])
    owner_name = (current_user.get("name") or "").strip() or "owner"
    old_path = current_user.get("profile_image")

    new_path = save_image_from_base64(body.image_base64, user_id)
    if not new_path:
        raise HTTPException(status_code=500, detail="Could not save image")

    abs_img = Path(new_path)
    if not abs_img.is_absolute():
        abs_img = Path.cwd() / abs_img

    try:
        results = DeepFace.represent(
            img_path=str(abs_img),
            model_name="Facenet512",
            enforce_detection=True,
            align=True,
        )
        if not results:
            raise ValueError("No face detected")
    except Exception as e:
        _delete_local_profile_image_if_any(new_path)
        err = str(e)
        if "Face could not be detected" in err or "could not detect" in err.lower():
            raise HTTPException(
                status_code=400,
                detail="No face detected in your photo. Please try again with a clearer picture.",
            )
        raise HTTPException(
            status_code=400,
            detail="Could not validate face in image.",
        )

    enrolled = enroll_face_photo(
        body.image_base64, owner_name, index=0, user_id=user_id
    )
    if not enrolled:
        _delete_local_profile_image_if_any(new_path)
        raise HTTPException(
            status_code=500, detail="Could not enroll face for recognition"
        )

    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "UPDATE users SET profile_image = %s WHERE id = %s",
            (new_path, user_id),
        )
        conn.commit()
        cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
        row = cursor.fetchone()
        cursor.close()
        conn.close()
    except Exception as e:
        _delete_local_profile_image_if_any(new_path)
        raise HTTPException(status_code=500, detail=str(e))

    if old_path and old_path != new_path:
        _delete_local_profile_image_if_any(old_path)

    return {"success": True, "user": _user_dict_for_response(row)}


@app.post("/api/me/clear-face-login")
async def clear_face_login(
    body: ClearFaceLoginRequest, current_user: dict = Depends(get_current_user)
):
    """Remove enrolled face login photo (home owner only); requires password."""
    require_home_owner(current_user)
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "SELECT password_hash, profile_image, name FROM users WHERE id = %s",
            (current_user["id"],),
        )
        row = cursor.fetchone()
        if not row:
            cursor.close()
            conn.close()
            raise HTTPException(status_code=404, detail="User not found")
        if not row.get("password_hash"):
            cursor.close()
            conn.close()
            raise HTTPException(
                status_code=400,
                detail="No password is set for this account.",
            )
        if not verify_password(body.password, row["password_hash"]):
            cursor.close()
            conn.close()
            raise HTTPException(status_code=401, detail="Password is incorrect")

        old_path = row.get("profile_image")
        member_name = (row.get("name") or "").strip() or "owner"
        user_id = int(current_user["id"])

        cursor.execute(
            "UPDATE users SET profile_image = NULL WHERE id = %s",
            (user_id,),
        )
        conn.commit()
        cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
        updated = cursor.fetchone()
        cursor.close()
        conn.close()

        _delete_local_profile_image_if_any(old_path)
        clear_owner_known_face_folders(user_id, member_name)

        return {"success": True, "user": _user_dict_for_response(updated)}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/me/fcm-token")
async def register_fcm_token_route(
    body: FcmTokenRegister, current_user: dict = Depends(get_current_user)
):
    """Register or refresh this device's FCM token for the logged-in user."""
    raw = (body.token or "").strip()
    if not raw:
        raise HTTPException(status_code=400, detail="token is required")
    uid = int(current_user["id"])
    platform = ((body.platform or "android").strip()[:20] or "android")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT INTO user_fcm_tokens (user_id, token, platform, updated_at)
            VALUES (%s, %s, %s, CURRENT_TIMESTAMP)
            ON CONFLICT (user_id, token) DO UPDATE SET
                platform = EXCLUDED.platform,
                updated_at = CURRENT_TIMESTAMP
            """,
            (uid, raw, platform),
        )
        conn.commit()
        cursor.close()
        conn.close()
        return {"success": True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/me/fcm-token")
async def delete_fcm_token_route(
    token: str = Query(..., description="FCM token to remove for this user"),
    current_user: dict = Depends(get_current_user),
):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "DELETE FROM user_fcm_tokens WHERE user_id = %s AND token = %s",
            (int(current_user["id"]), token.strip()),
        )
        conn.commit()
        deleted = cursor.rowcount
        cursor.close()
        conn.close()
        return {"success": True, "removed": deleted}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# Health check endpoint
@app.get("/api/health")
def health_check():
    return {"status": "OK", "message": "Server is running"}

# Helper function to save image from base64
def save_image_from_base64(base64_string: str, user_id: int) -> Optional[str]:
    """Save base64 image to file and return the file path"""
    try:
        # Remove data URL prefix if present (e.g., "data:image/jpeg;base64,")
        if ',' in base64_string:
            base64_string = base64_string.split(',')[1]
        
        # Decode base64 to bytes
        image_data = base64.b64decode(base64_string)
        
        # Generate filename
        filename = f"user_{user_id}_profile_{datetime.now().strftime('%Y%m%d_%H%M%S')}.jpg"
        filepath = UPLOAD_DIR / filename
        
        # Save image
        with open(filepath, 'wb') as f:
            f.write(image_data)
        
        # Return relative path for database storage
        return f"uploads/{filename}"
    except Exception as e:
        print(f"Error saving image: {e}")
        return None


def delete_upload_relative(relative_path: Optional[str]) -> None:
    """Remove a file stored via save_image_from_base64 (paths like uploads/....jpg)."""
    if not relative_path:
        return
    try:
        p = Path(relative_path)
        if not p.is_absolute():
            p = Path.cwd() / p
        if p.is_file():
            p.unlink()
            print(f"[UPLOAD] Removed file: {p}")
    except Exception as e:
        print(f"[UPLOAD] Could not delete {relative_path}: {e}")


def _invalidate_pet_reference_cache(owner_id: int) -> None:
    try:
        get_pet_detection_service().invalidate_user_pet_references(owner_id)
    except Exception:
        pass


def _user_dict_for_response(row: dict) -> dict:
    d = dict(row)
    d.pop("password_hash", None)
    if d.get("created_at") is not None and hasattr(d["created_at"], "isoformat"):
        d["created_at"] = d["created_at"].isoformat()
    return d


def _delete_local_profile_image_if_any(relative_path: Optional[str]) -> None:
    if not relative_path:
        return
    try:
        p = Path(relative_path)
        if not p.is_absolute():
            p = Path.cwd() / p
        if p.is_file():
            p.unlink()
            print(f"[FACE] Removed old profile file: {p}")
    except Exception as e:
        print(f"[FACE] Could not delete old profile file {relative_path}: {e}")


def clear_owner_known_face_folders(user_id: int, member_name: str) -> None:
    """Remove face enrollment folder + DeepFace cache for the home owner under known_faces."""
    user_dir = Path("known_faces") / f"user_{user_id}"
    member_dir = user_dir / member_name
    if member_dir.exists():
        try:
            shutil.rmtree(member_dir)
            print(f"[FACE] Cleared known_faces for user {user_id} / {member_name}")
        except Exception as e:
            print(f"[FACE] Could not rmtree {member_dir}: {e}")
    for cache_file in user_dir.glob("*.pkl"):
        try:
            cache_file.unlink()
            print(f"[FACE] Deleted DeepFace cache: {cache_file.name}")
        except Exception:
            pass


def migrate_known_faces_to_per_user():
    """
    One-time migration of legacy flat `known_faces/<name>/` folders into
    per-user `known_faces/user_<id>/<name>/` folders.

    Safe to run on every startup — only acts if a flat folder exists.
    Ownership is resolved from the database by looking up the folder name in:
      1. users.name (main account holder)
      2. family_members.name (joined with user_id)
      3. trusted_persons.name (joined with user_id)
    Earliest-created record wins on ties. Unowned folders are skipped with a warning.
    """
    base = Path("known_faces")
    if not base.exists():
        return

    flat_folders = [p for p in base.iterdir() if p.is_dir() and not p.name.startswith("user_")]
    if not flat_folders:
        return

    print(f"[MIGRATION] Found {len(flat_folders)} legacy known_faces folder(s) to migrate")

    name_to_user: dict[str, int] = {}
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)

        cursor.execute("SELECT id, name FROM users ORDER BY id ASC")
        for row in cursor.fetchall():
            if row.get("name") and row["name"] not in name_to_user:
                name_to_user[row["name"]] = row["id"]

        try:
            cursor.execute("SELECT user_id, name FROM family_members ORDER BY id ASC")
            for row in cursor.fetchall():
                if row.get("name") and row["name"] not in name_to_user:
                    name_to_user[row["name"]] = row["user_id"]
        except Exception as e:
            print(f"[MIGRATION] Skipping family_members lookup: {e}")

        try:
            cursor.execute("SELECT user_id, name FROM trusted_persons ORDER BY id ASC")
            for row in cursor.fetchall():
                if row.get("name") and row["name"] not in name_to_user:
                    name_to_user[row["name"]] = row["user_id"]
        except Exception as e:
            print(f"[MIGRATION] Skipping trusted_persons lookup: {e}")

        cursor.close()
        conn.close()
    except Exception as e:
        print(f"[MIGRATION] DB lookup failed, aborting: {e}")
        return

    import shutil
    migrated = 0
    skipped = 0
    for folder in flat_folders:
        owner_id = name_to_user.get(folder.name)
        if owner_id is None:
            print(f"[MIGRATION] WARNING: No owner found for '{folder.name}' — leaving in place")
            skipped += 1
            continue

        target_user_dir = base / f"user_{owner_id}"
        target_user_dir.mkdir(parents=True, exist_ok=True)
        target = target_user_dir / folder.name

        if target.exists():
            print(f"[MIGRATION] Target {target} already exists, skipping '{folder.name}'")
            skipped += 1
            continue

        try:
            shutil.move(str(folder), str(target))
            print(f"[MIGRATION] Moved '{folder.name}' -> user_{owner_id}/{folder.name}")
            migrated += 1
        except Exception as e:
            print(f"[MIGRATION] ERROR moving '{folder.name}': {e}")
            skipped += 1

    # Wipe legacy global .pkl caches (they referenced old paths and are now stale)
    for pkl in base.glob("*.pkl"):
        try:
            pkl.unlink()
            print(f"[MIGRATION] Removed stale global cache: {pkl.name}")
        except Exception:
            pass

    print(f"[MIGRATION] Complete. Migrated {migrated}, skipped {skipped}, total {len(flat_folders)}.")


def enroll_face_photo(base64_string: str, member_name: str, index: int = 0, user_id: Optional[int] = None) -> Optional[str]:
    """Saves a base64 image to known_faces/user_<id>/<Name>/ for recognition.
    user_id is REQUIRED for multi-account isolation. If omitted, the call is rejected
    to prevent accidental cross-account leakage.
    """
    if user_id is None:
        print(f"[FACE] REFUSED enrollment for '{member_name}': user_id is required (multi-tenant safety)")
        return None
    try:
        if "," in base64_string:
            base64_string = base64_string.split(",")[1]
        
        image_data = base64.b64decode(base64_string)
        
        # Per-user namespaced path
        user_dir = Path("known_faces") / f"user_{user_id}"
        member_dir = user_dir / member_name
        
        # On the first photo, clear ONLY this user's copy of the folder (safe — won't touch other accounts)
        if index == 0 and member_dir.exists():
            import shutil
            shutil.rmtree(member_dir)
            print(f"[FACE] Cleared old profile for user {user_id} / {member_name}")
            
        member_dir.mkdir(parents=True, exist_ok=True)
        
        filename = f"face_{index + 1}.jpg"
        filepath = member_dir / filename
        
        with open(filepath, 'wb') as f:
            f.write(image_data)
            
        # Invalidate ONLY this user's DeepFace cache so the next recognition re-indexes them.
        # Other users' caches stay intact — their cameras keep working without re-index latency.
        for cache_file in user_dir.glob("*.pkl"):
            try:
                cache_file.unlink()
                print(f"[FACE] Deleted cache for user {user_id}: {cache_file.name}")
            except Exception:
                pass
            
        return str(filepath)
    except Exception as e:
        print(f"Error enrolling face: {e}")
        return None

# User Options Endpoints
@app.get("/api/options")
async def get_user_options(current_user: dict = Depends(get_current_user)):
    try:
        owner_id = effective_owner_id(current_user)
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute("SELECT * FROM user_options WHERE user_id = %s", (owner_id,))
        options = cursor.fetchone()
        
        if not options:
            # Create default options if none exist (home owner row only)
            if current_user.get("role") == "family":
                cursor.close()
                conn.close()
                return {
                    "user_id": owner_id,
                    "theme": "light",
                    "notifications_enabled": True,
                    "email_notifications_enabled": False,
                    "in_app_alerts_enabled": True,
                    "language": "en",
                    "selected_modes": None,
                    "onboarding_skips": None,
                    "recording_retention_days": 30,
                    "network_route_mode": "home",
                    "api_base_home_url": None,
                    "api_base_tunnel_url": None,
                }
            cursor.execute(
                "INSERT INTO user_options (user_id) VALUES (%s) RETURNING *",
                (owner_id,)
            )
            options = cursor.fetchone()
            conn.commit()
            
        cursor.close()
        conn.close()
        return options
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/options")
async def update_user_options(data: dict, current_user: dict = Depends(get_current_user)):
    require_home_owner(current_user)
    try:
        update_data = validate_user_options(data)

        if not update_data:
             return await get_user_options(current_user)

        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        user_id = effective_owner_id(current_user)
        columns = list(update_data.keys())
        values = list(update_data.values())
        
        insert_cols = ["user_id"] + columns
        insert_placeholders = ["%s"] * len(insert_cols)
        update_cols = [f"{col} = EXCLUDED.{col}" for col in columns]
        
        query = f"""
            INSERT INTO user_options ({", ".join(insert_cols)})
            VALUES ({", ".join(insert_placeholders)})
            ON CONFLICT (user_id) 
            DO UPDATE SET {", ".join(update_cols)}
            RETURNING *
        """
        
        # Serialize JSON if necessary
        proc_values = [user_id]
        for v in values:
            if isinstance(v, (list, dict)):
                proc_values.append(json.dumps(v))
            else:
                proc_values.append(v)

        cursor.execute(query, proc_values)
        updated_options = cursor.fetchone()
        
        conn.commit()
        cursor.close()
        conn.close()
        return updated_options
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error updating options: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# Onboarding Skip Endpoint
@app.post("/api/onboarding/skip")
async def track_onboarding_skip(data: dict, current_user: dict = Depends(get_current_user)):
    require_home_owner(current_user)
    try:
        step_name = data.get('step_name')
        if not step_name:
            raise HTTPException(status_code=400, detail="step_name is required")
            
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        # Get current skips
        cursor.execute("SELECT onboarding_skips FROM user_options WHERE user_id = %s", (effective_owner_id(current_user),))
        row = cursor.fetchone()
        
        skips = []
        if row and row['onboarding_skips']:
            skips = list(row['onboarding_skips'])
            
        if step_name not in skips:
            skips.append(step_name)
            
            cursor.execute(
                "UPDATE user_options SET onboarding_skips = %s WHERE user_id = %s",
                (json.dumps(skips), effective_owner_id(current_user))
            )
            conn.commit()
            
        cursor.close()
        conn.close()
        return {"success": True, "skips": skips}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Family Member Registration
@app.post("/api/family")
async def add_family_member(member: FamilyMemberCreate, current_user: dict = Depends(get_current_user)):
    require_home_owner(current_user)
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        cursor.execute(
            "INSERT INTO family_members (user_id, name, relationship, phone) VALUES (%s, %s, %s, %s) RETURNING id",
            (current_user['id'], member.name, member.relationship, member.phone)
        )
        member_id = cursor.fetchone()['id']

        raw_invite = generate_family_invite_code()
        invite_hash = hash_invite_code(raw_invite)
        cursor.execute(
            "UPDATE family_members SET invite_code_hash = %s, invite_consumed_at = NULL WHERE id = %s",
            (invite_hash, member_id),
        )
        
        # Save photos if any
        for photo_base64 in member.photos:
            # Save to general uploads
            photo_path = save_image_from_base64(photo_base64, f"family_{member_id}")
            if photo_path:
                cursor.execute(
                    "INSERT INTO member_photos (member_id, member_type, photo_path) VALUES (%s, %s, %s)",
                    (member_id, 'family', photo_path)
                )
        
        # Enroll for face recognition (outside the loop)
        for i, photo_base64 in enumerate(member.photos):
            enroll_face_photo(photo_base64, member.name, index=i, user_id=current_user['id'])
        
        conn.commit()
        cursor.close()
        conn.close()
        return {"success": True, "member_id": member_id, "invite_code": raw_invite}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/family")
async def list_family_members(current_user: dict = Depends(get_current_user)):
    """List all family members enrolled by the home owner, with their primary avatar photo path."""
    require_home_owner(current_user)
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)

        cursor.execute(
            """
            SELECT fm.id, fm.name, fm.relationship, fm.phone, fm.created_at,
                   (SELECT photo_path FROM member_photos
                      WHERE member_id = fm.id AND member_type = 'family'
                      ORDER BY id ASC LIMIT 1) AS photo_path,
                   EXISTS(
                     SELECT 1 FROM users u
                     WHERE u.family_member_id = fm.id AND u.role = 'family'
                   ) AS has_account,
                   (fm.invite_code_hash IS NOT NULL AND fm.invite_consumed_at IS NULL) AS invite_pending
            FROM family_members fm
            WHERE fm.user_id = %s
            ORDER BY fm.id ASC
            """,
            (current_user['id'],),
        )
        rows = cursor.fetchall()
        cursor.close()
        conn.close()

        members = []
        for r in rows:
            members.append({
                "id": r["id"],
                "name": r["name"],
                "relationship": r["relationship"],
                "phone": r["phone"],
                "created_at": r["created_at"].isoformat() if r.get("created_at") else None,
                "photo_path": r.get("photo_path"),
                "has_account": bool(r.get("has_account")),
                "invite_pending": bool(r.get("invite_pending")),
            })
        return {"success": True, "members": members}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.put("/api/family/{member_id}")
async def update_family_member(member_id: int, update: FamilyMemberUpdate, current_user: dict = Depends(get_current_user)):
    """Update a family member's name / relationship / phone.
    If name changes, also rename their known_faces folder and invalidate the user's .pkl cache.
    """
    require_home_owner(current_user)
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)

        cursor.execute(
            "SELECT id, name FROM family_members WHERE id = %s AND user_id = %s",
            (member_id, current_user['id']),
        )
        member = cursor.fetchone()
        if not member:
            cursor.close()
            conn.close()
            raise HTTPException(status_code=404, detail="Family member not found")

        old_name = member["name"]
        new_name = (update.name or old_name).strip() or old_name

        cursor.execute(
            "UPDATE family_members SET name = COALESCE(%s, name), relationship = COALESCE(%s, relationship), phone = COALESCE(%s, phone) WHERE id = %s",
            (new_name if update.name is not None else None, update.relationship, update.phone, member_id),
        )
        conn.commit()
        cursor.close()
        conn.close()

        # If name changed, rename the per-user known_faces folder so recognition keeps working
        if update.name is not None and new_name != old_name:
            user_dir = Path("known_faces") / f"user_{current_user['id']}"
            old_folder = user_dir / old_name
            new_folder = user_dir / new_name
            if old_folder.exists():
                try:
                    if new_folder.exists():
                        # Avoid clobbering an existing same-named folder
                        import shutil
                        shutil.rmtree(new_folder)
                    old_folder.rename(new_folder)
                    print(f"[FACE] Renamed known_faces folder: {old_name} -> {new_name} for user {current_user['id']}")
                except Exception as e:
                    print(f"[FACE] Could not rename folder {old_folder} -> {new_folder}: {e}")
            # Invalidate this user's .pkl so DeepFace re-indexes with the new label
            for pkl in user_dir.glob("*.pkl"):
                try:
                    pkl.unlink()
                except Exception:
                    pass

        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/family/{member_id}")
async def delete_family_member(member_id: int, current_user: dict = Depends(get_current_user)):
    """Fully remove a family member: DB row + member_photos + uploaded files +
    known_faces folder + per-user .pkl cache + linked family login user."""
    require_home_owner(current_user)
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)

        cursor.execute(
            "SELECT id, name FROM family_members WHERE id = %s AND user_id = %s",
            (member_id, current_user['id']),
        )
        member = cursor.fetchone()
        if not member:
            cursor.close()
            conn.close()
            raise HTTPException(status_code=404, detail="Family member not found")

        member_name = member["name"]

        cursor.execute(
            "DELETE FROM users WHERE family_member_id = %s AND role = 'family'",
            (member_id,),
        )

        # Collect their photo paths from member_photos so we can delete the actual files
        cursor.execute(
            "SELECT photo_path FROM member_photos WHERE member_id = %s AND member_type = 'family'",
            (member_id,),
        )
        photo_rows = cursor.fetchall()

        cursor.execute(
            "DELETE FROM member_photos WHERE member_id = %s AND member_type = 'family'",
            (member_id,),
        )
        cursor.execute("DELETE FROM family_members WHERE id = %s", (member_id,))
        conn.commit()
        cursor.close()
        conn.close()

        # Filesystem cleanup
        for row in photo_rows:
            path = row.get("photo_path")
            if not path:
                continue
            f = Path(path)
            if f.exists():
                try:
                    f.unlink()
                except Exception as e:
                    print(f"[DELETE] Could not remove upload {f}: {e}")

        # Remove their known_faces subfolder under this user's namespace
        user_dir = Path("known_faces") / f"user_{current_user['id']}"
        member_face_dir = user_dir / member_name
        if member_face_dir.exists():
            import shutil
            try:
                shutil.rmtree(member_face_dir)
                print(f"[FACE] Removed known_faces folder for user {current_user['id']} / {member_name}")
            except Exception as e:
                print(f"[FACE] Could not remove {member_face_dir}: {e}")

        # Invalidate user's .pkl so DeepFace re-indexes without the removed face
        for pkl in user_dir.glob("*.pkl"):
            try:
                pkl.unlink()
            except Exception:
                pass

        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/family/join/lookup")
def lookup_family_invite_code(body: FamilyInviteLookupRequest):
    code = (body.code or "").strip()
    if len(code) < 8:
        raise HTTPException(status_code=400, detail="Invalid or expired invite code")
    digest = hash_invite_code(code)
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            """
            SELECT fm.id, fm.name,
                   EXISTS(
                     SELECT 1 FROM users u
                     WHERE u.family_member_id = fm.id AND u.role = 'family'
                   ) AS has_account
            FROM family_members fm
            WHERE fm.invite_code_hash = %s AND fm.invite_consumed_at IS NULL
            """,
            (digest,),
        )
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        if not row or row.get("has_account"):
            raise HTTPException(status_code=400, detail="Invalid or expired invite code")
        return {"success": True, "name": row["name"], "member_id": row["id"]}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/family/join", response_model=dict, status_code=201)
def join_family_account(body: FamilyJoinRequest):
    code = (body.code or "").strip()
    email = (body.email or "").strip().lower()
    if len(code) < 8 or not email:
        raise HTTPException(status_code=400, detail="Invalid request")
    digest = hash_invite_code(code)
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            """
            SELECT fm.id, fm.name, fm.user_id AS owner_id,
                   EXISTS(
                     SELECT 1 FROM users u
                     WHERE u.family_member_id = fm.id AND u.role = 'family'
                   ) AS has_account
            FROM family_members fm
            WHERE fm.invite_code_hash = %s AND fm.invite_consumed_at IS NULL
            """,
            (digest,),
        )
        row = cursor.fetchone()
        if not row or row.get("has_account"):
            cursor.close()
            conn.close()
            raise HTTPException(status_code=400, detail="Invalid or expired invite code")

        cursor.execute("SELECT id FROM users WHERE LOWER(email) = LOWER(%s)", (email,))
        if cursor.fetchone():
            cursor.close()
            conn.close()
            raise HTTPException(
                status_code=400,
                detail="This email is already registered. Use login with your email and password.",
            )

        hashed_password = get_password_hash(body.password)
        owner_id = row["owner_id"]
        member_id = row["id"]
        member_name = row["name"]

        cursor.execute(
            """
            INSERT INTO users (
              name, email, password_hash, role, owner_user_id,
              family_member_id, is_verified
            )
            VALUES (%s, %s, %s, 'family', %s, %s, TRUE)
            RETURNING id
            """,
            (member_name, email, hashed_password, owner_id, member_id),
        )
        new_id = cursor.fetchone()["id"]

        cursor.execute(
            """
            UPDATE family_members
            SET invite_code_hash = NULL, invite_consumed_at = CURRENT_TIMESTAMP
            WHERE id = %s
            """,
            (member_id,),
        )

        cursor.execute(
            "INSERT INTO user_options (user_id) VALUES (%s) ON CONFLICT (user_id) DO NOTHING",
            (new_id,),
        )

        conn.commit()
        cursor.execute("SELECT * FROM users WHERE id = %s", (new_id,))
        user = cursor.fetchone()
        cursor.close()
        conn.close()

        access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
        access_token = create_access_token(
            data={"sub": user["email"], "id": user["id"]}, expires_delta=access_token_expires
        )
        user_data = dict(user)
        user_data.pop("password_hash", None)
        return {
            "success": True,
            "access_token": access_token,
            "token_type": "bearer",
            "user": user_data,
        }
    except HTTPException:
        raise
    except psycopg2.Error as e:
        raise HTTPException(status_code=500, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/family/{member_id}/invite-code")
async def create_or_refresh_family_invite(
    member_id: int, current_user: dict = Depends(get_current_user)
):
    require_home_owner(current_user)
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            """
            SELECT fm.id,
                   EXISTS(
                     SELECT 1 FROM users u
                     WHERE u.family_member_id = fm.id AND u.role = 'family'
                   ) AS has_account
            FROM family_members fm
            WHERE fm.id = %s AND fm.user_id = %s
            """,
            (member_id, current_user["id"]),
        )
        row = cursor.fetchone()
        if not row:
            cursor.close()
            conn.close()
            raise HTTPException(status_code=404, detail="Family member not found")
        if row.get("has_account"):
            cursor.close()
            conn.close()
            raise HTTPException(
                status_code=400, detail="This member already has a mobile login.",
            )

        raw = generate_family_invite_code()
        cursor.execute(
            """
            UPDATE family_members
            SET invite_code_hash = %s, invite_consumed_at = NULL
            WHERE id = %s
            """,
            (hash_invite_code(raw), member_id),
        )
        conn.commit()
        cursor.close()
        conn.close()
        return {"success": True, "invite_code": raw}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# Trusted Person Registration
@app.post("/api/trusted")
async def add_trusted_person(person: TrustedPersonCreate, current_user: dict = Depends(get_current_user)):
    require_home_owner(current_user)
    email = _normalize_trusted_email(person.email)
    if not email:
        raise HTTPException(status_code=400, detail="A valid email address is required")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        cursor.execute(
            "INSERT INTO trusted_persons (user_id, name, relationship, phone, email) VALUES (%s, %s, %s, %s, %s) RETURNING id",
            (current_user['id'], person.name.strip(), person.relationship.strip(), person.phone.strip(), email)
        )
        person_id = cursor.fetchone()['id']
        
        # Save photos if any (optional legacy face enrollment)
        for photo_base64 in person.photos:
            photo_path = save_image_from_base64(photo_base64, f"trusted_{person_id}")
            if photo_path:
                cursor.execute(
                    "INSERT INTO member_photos (member_id, member_type, photo_path) VALUES (%s, %s, %s)",
                    (person_id, 'trusted', photo_path)
                )
        
        for i, photo_base64 in enumerate(person.photos):
            enroll_face_photo(photo_base64, person.name, index=i, user_id=current_user['id'])
        
        conn.commit()
        cursor.close()
        conn.close()
        return {"success": True, "person_id": person_id}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/trusted")
async def list_trusted_persons(current_user: dict = Depends(get_current_user)):
    require_home_owner(current_user)
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            """
            SELECT id, name, relationship, phone, email, created_at
            FROM trusted_persons
            WHERE user_id = %s
            ORDER BY id ASC
            """,
            (current_user["id"],),
        )
        rows = cursor.fetchall() or []
        cursor.close()
        conn.close()
        out = []
        for row in rows:
            item = dict(row)
            if isinstance(item.get("created_at"), datetime):
                item["created_at"] = item["created_at"].isoformat()
            out.append(item)
        return {"success": True, "trusted_persons": out}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.put("/api/trusted/{person_id}")
async def update_trusted_person(
    person_id: int,
    person: TrustedPersonUpdate,
    current_user: dict = Depends(get_current_user),
):
    require_home_owner(current_user)
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "SELECT id FROM trusted_persons WHERE id = %s AND user_id = %s",
            (person_id, current_user["id"]),
        )
        if not cursor.fetchone():
            cursor.close()
            conn.close()
            raise HTTPException(status_code=404, detail="Trusted person not found")

        fields = []
        values = []
        if person.name is not None:
            fields.append("name = %s")
            values.append(person.name.strip())
        if person.relationship is not None:
            fields.append("relationship = %s")
            values.append(person.relationship.strip())
        if person.phone is not None:
            fields.append("phone = %s")
            values.append(person.phone.strip())
        if person.email is not None:
            email = _normalize_trusted_email(person.email)
            if not email:
                raise HTTPException(status_code=400, detail="A valid email address is required")
            fields.append("email = %s")
            values.append(email)

        if not fields:
            cursor.close()
            conn.close()
            return {"success": True}

        values.extend([person_id, current_user["id"]])
        cursor.execute(
            f"UPDATE trusted_persons SET {', '.join(fields)} WHERE id = %s AND user_id = %s",
            tuple(values),
        )
        conn.commit()
        cursor.close()
        conn.close()
        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/trusted/{person_id}")
async def delete_trusted_person(
    person_id: int,
    current_user: dict = Depends(get_current_user),
):
    require_home_owner(current_user)
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "DELETE FROM trusted_persons WHERE id = %s AND user_id = %s RETURNING id",
            (person_id, current_user["id"]),
        )
        deleted = cursor.fetchone()
        conn.commit()
        cursor.close()
        conn.close()
        if not deleted:
            raise HTTPException(status_code=404, detail="Trusted person not found")
        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Pet Registration
@app.post("/api/pets")
async def add_pet(pet: PetCreate, current_user: dict = Depends(get_current_user)):
    require_home_owner(current_user)
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        cursor.execute(
            "INSERT INTO pets (user_id, name, age, breed) VALUES (%s, %s, %s, %s) RETURNING id",
            (current_user['id'], pet.name, pet.age, pet.breed)
        )
        pet_id = cursor.fetchone()['id']
        
        # Save photos if any
        for photo_base64 in pet.photos:
            photo_path = save_image_from_base64(photo_base64, f"pet_{pet_id}")
            if photo_path:
                cursor.execute(
                    "INSERT INTO pet_photos (pet_id, photo_path) VALUES (%s, %s)",
                    (pet_id, photo_path)
                )
        
        conn.commit()
        cursor.close()
        conn.close()
        _invalidate_pet_reference_cache(int(current_user["id"]))
        return {"success": True, "pet_id": pet_id}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/pets")
async def list_my_pets(current_user: dict = Depends(get_current_user)):
    """List pets registered by the home owner (with pet_photos ids)."""
    require_home_owner(current_user)
    oid = int(current_user["id"])
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            """
            SELECT id, name, age, breed, created_at
            FROM pets
            WHERE user_id = %s
            ORDER BY id ASC
            """,
            (oid,),
        )
        pets = cursor.fetchall()
        out = []
        for pet in pets:
            pid = pet["id"]
            cursor.execute(
                "SELECT id, photo_path FROM pet_photos WHERE pet_id = %s ORDER BY id ASC",
                (pid,),
            )
            photos = cursor.fetchall()
            pet_d = dict(pet)
            if pet_d.get("created_at") is not None and hasattr(
                pet_d["created_at"], "isoformat"
            ):
                pet_d["created_at"] = pet_d["created_at"].isoformat()
            pet_d["photos"] = [dict(ph) for ph in photos]
            out.append(pet_d)
        cursor.close()
        conn.close()
        return {"success": True, "pets": out}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/pets/photos/{photo_id}")
async def delete_pet_photo(photo_id: int, current_user: dict = Depends(get_current_user)):
    """Delete one stored pet photo row and its uploads/… file."""
    require_home_owner(current_user)
    oid = int(current_user["id"])
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            """
            SELECT pp.photo_path, p.user_id
            FROM pet_photos pp
            JOIN pets p ON p.id = pp.pet_id
            WHERE pp.id = %s
            """,
            (photo_id,),
        )
        row = cursor.fetchone()
        if not row:
            cursor.close()
            conn.close()
            raise HTTPException(status_code=404, detail="Photo not found")
        if row["user_id"] != oid:
            cursor.close()
            conn.close()
            raise HTTPException(status_code=403, detail="Not your pet photo")
        rel_path = row["photo_path"]
        cursor.execute("DELETE FROM pet_photos WHERE id = %s", (photo_id,))
        conn.commit()
        cursor.close()
        conn.close()
        delete_upload_relative(rel_path)
        _invalidate_pet_reference_cache(oid)
        return {"success": True, "deleted_photo_id": photo_id}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/pets/{pet_id}")
async def delete_pet(pet_id: int, current_user: dict = Depends(get_current_user)):
    """Delete a pet and all linked pet_photos; remove uploads/ files; CASCADE clears DB."""
    require_home_owner(current_user)
    oid = int(current_user["id"])
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "SELECT id FROM pets WHERE id = %s AND user_id = %s",
            (pet_id, oid),
        )
        if not cursor.fetchone():
            cursor.close()
            conn.close()
            raise HTTPException(status_code=404, detail="Pet not found")
        cursor.execute(
            "SELECT photo_path FROM pet_photos WHERE pet_id = %s",
            (pet_id,),
        )
        paths = [r["photo_path"] for r in cursor.fetchall()]
        cursor.execute("DELETE FROM pets WHERE id = %s AND user_id = %s", (pet_id, oid))
        conn.commit()
        cursor.close()
        conn.close()
        for rel_path in paths:
            delete_upload_relative(rel_path)
        _invalidate_pet_reference_cache(oid)
        return {"success": True, "deleted_pet_id": pet_id}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# User Events Endpoints
@app.get("/api/events")
async def get_user_events(current_user: dict = Depends(get_current_user)):
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute("""
            SELECT id, user_id, title, description, event_type, 
                   video_path as video_url, room_name, timestamp 
            FROM user_events 
            WHERE user_id = %s 
            ORDER BY timestamp DESC
        """, (effective_owner_id(current_user),))
        events = cursor.fetchall()
        cursor.close()
        conn.close()
        return events
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/events")
async def create_user_event(data: dict, current_user: dict = Depends(get_current_user)):
    require_home_owner(current_user)
    try:
        title = data.get('title')
        if not title:
            raise HTTPException(status_code=400, detail="Title is required")
            
        description = data.get('description')
        event_type = data.get('event_type')
        room_name = data.get('room_name')
        
        new_event = await save_and_broadcast_event(
            user_id=effective_owner_id(current_user),
            title=title,
            description=description,
            event_type=event_type,
            room_name=room_name
        )
        
        if not new_event:
            raise HTTPException(status_code=500, detail="Failed to create event")
            
        return new_event
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# --- Local storage (recordings / uploads on this server; no third-party cloud) ---


def _resolve_stored_file_path(stored: Optional[str]) -> Optional[Path]:
    if not stored:
        return None
    s = str(stored).strip()
    if s.startswith("/"):
        s = s[1:]
    p = Path(s)
    if not p.is_absolute():
        p = Path.cwd() / p
    return p if p.is_file() else None


def _unlink_recording_bytes(video_path: Optional[str]) -> bool:
    p = _resolve_stored_file_path(video_path)
    if p and p.is_file():
        try:
            p.unlink()
            return True
        except OSError as e:
            print(f"[storage] could not delete {p}: {e}")
    return False


def _dir_size_bytes(root: Path) -> int:
    if not root.is_dir():
        return 0
    n = 0
    try:
        for f in root.rglob("*"):
            if f.is_file():
                try:
                    n += f.stat().st_size
                except OSError:
                    pass
    except OSError:
        pass
    return n


@app.get("/api/storage/summary")
async def storage_summary(current_user: dict = Depends(get_current_user)):
    oid = effective_owner_id(current_user)
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)

        cursor.execute(
            """
            SELECT video_path FROM user_events
            WHERE user_id = %s AND video_path IS NOT NULL AND TRIM(video_path) <> ''
            """,
            (oid,),
        )
        clips_bytes = 0
        for r in cursor.fetchall():
            p = _resolve_stored_file_path(r["video_path"])
            if p:
                try:
                    clips_bytes += p.stat().st_size
                except OSError:
                    pass

        cursor.execute(
            "SELECT COUNT(*)::int AS n FROM user_events WHERE user_id = %s",
            (oid,),
        )
        event_count = cursor.fetchone()["n"]
        cursor.execute(
            """
            SELECT COUNT(*)::int AS n FROM user_events
            WHERE user_id = %s AND video_path IS NOT NULL AND TRIM(video_path) <> ''
            """,
            (oid,),
        )
        events_with_video = cursor.fetchone()["n"]

        profile_bytes = 0
        cursor.execute(
            "SELECT profile_image FROM users WHERE id = %s OR owner_user_id = %s",
            (oid, oid),
        )
        for row in cursor.fetchall():
            pi = row.get("profile_image")
            if not pi:
                continue
            p = _resolve_stored_file_path(str(pi))
            if p:
                try:
                    profile_bytes += p.stat().st_size
                except OSError:
                    pass

        cursor.execute(
            "SELECT recording_retention_days FROM user_options WHERE user_id = %s",
            (oid,),
        )
        opt = cursor.fetchone()
        retention_days = 30
        if opt and opt.get("recording_retention_days") is not None:
            retention_days = int(opt["recording_retention_days"])

        cursor.close()
        conn.close()

        faces_dir = Path("known_faces") / f"user_{oid}"
        faces_bytes = _dir_size_bytes(faces_dir)

        rec_root = Path("recordings").resolve()
        anchor = rec_root if rec_root.is_dir() else Path.cwd().resolve()
        du = shutil.disk_usage(anchor)
        low_disk = du.free < 500 * 1024 * 1024

        return {
            "success": True,
            "owner_user_id": oid,
            "event_count": event_count,
            "events_with_video": events_with_video,
            "clips_bytes": clips_bytes,
            "profile_images_bytes": profile_bytes,
            "known_faces_bytes": faces_bytes,
            "retention_days": retention_days,
            "disk_free_bytes": du.free,
            "disk_total_bytes": du.total,
            "low_disk_warning": low_disk,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/events/{event_id}")
async def delete_user_event(event_id: int, current_user: dict = Depends(get_current_user)):
    require_home_owner(current_user)
    oid = effective_owner_id(current_user)
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "SELECT id, video_path FROM user_events WHERE id = %s AND user_id = %s",
            (event_id, oid),
        )
        row = cursor.fetchone()
        if not row:
            cursor.close()
            conn.close()
            raise HTTPException(status_code=404, detail="Event not found")
        _unlink_recording_bytes(row.get("video_path"))
        cursor.execute(
            "DELETE FROM user_events WHERE id = %s AND user_id = %s",
            (event_id, oid),
        )
        conn.commit()
        cursor.close()
        conn.close()
        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/events/{event_id}/retranscode-video")
async def retranscode_event_video(
    event_id: int, current_user: dict = Depends(get_current_user)
):
    """
    Re-run WebM→MP4 normalization for an existing event clip and update video_path.
    Use when the DB still has a .enc WebM but ffmpeg was fixed; mobile ExoPlayer needs MP4.
    """
    oid = effective_owner_id(current_user)
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "SELECT id, video_path FROM user_events WHERE id = %s AND user_id = %s",
            (event_id, oid),
        )
        row = cursor.fetchone()
        if not row:
            cursor.close()
            conn.close()
            raise HTTPException(status_code=404, detail="Event not found")
        vp = row.get("video_path")
        if not vp or not str(vp).strip():
            cursor.close()
            conn.close()
            raise HTTPException(status_code=400, detail="Event has no recording")
        p = _resolve_stored_file_path(str(vp))
        if not p:
            cursor.close()
            conn.close()
            raise HTTPException(status_code=404, detail="Recording file missing on server")

        new_disk, new_db = _normalize_event_clip_for_playback(str(p.resolve()), p.name)

        new_path = Path(new_disk)
        if not new_path.is_file():
            cursor.close()
            conn.close()
            raise HTTPException(status_code=500, detail="Transcode failed: output missing")

        with open(new_path, "rb") as f:
            head = f.read(16)
        is_mp4 = len(head) >= 12 and head[4:8] == b"ftyp"
        if not is_mp4:
            if head.startswith(b"\x1a\x45\xdf\xa3"):
                cursor.close()
                conn.close()
                raise HTTPException(
                    status_code=500,
                    detail="Still WebM after transcode — check ffmpeg on the server ([STARTUP] log, FFMPEG_PATH).",
                )
            cursor.close()
            conn.close()
            raise HTTPException(
                status_code=500,
                detail=(
                    "This recording cannot be converted to MP4 on the server. "
                    "Older mobile uploads used AES with a random IV only the phone knew, "
                    "so nothing can decode that file here. Rebuild the app (upload is now plain video), "
                    "then record again or delete this event."
                ),
            )

        final_disk, final_db = _finalize_clip_encrypted_storage(new_disk)

        cursor.execute(
            "UPDATE user_events SET video_path = %s WHERE id = %s AND user_id = %s",
            (final_db, event_id, oid),
        )
        conn.commit()
        cursor.close()
        conn.close()
        return {"success": True, "video_path": final_db}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/storage/purge-old")
async def storage_purge_old(data: dict, current_user: dict = Depends(get_current_user)):
    require_home_owner(current_user)
    oid = effective_owner_id(current_user)
    days = data.get("days")
    if days is None:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "SELECT recording_retention_days FROM user_options WHERE user_id = %s",
            (oid,),
        )
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        days = (
            int(row["recording_retention_days"])
            if row and row.get("recording_retention_days") is not None
            else 30
        )
    try:
        days = int(days)
    except (TypeError, ValueError):
        raise HTTPException(status_code=400, detail="days must be a number")
    if days < 1:
        raise HTTPException(status_code=400, detail="days must be >= 1")

    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            """
            SELECT id, video_path FROM user_events
            WHERE user_id = %s
              AND video_path IS NOT NULL AND TRIM(video_path) <> ''
              AND timestamp < NOW() - (%s * INTERVAL '1 day')
            """,
            (oid, days),
        )
        rows = cursor.fetchall()
        files_deleted = 0
        for r in rows:
            if _unlink_recording_bytes(r.get("video_path")):
                files_deleted += 1
            cursor.execute(
                "UPDATE user_events SET video_path = NULL WHERE id = %s",
                (r["id"],),
            )
        conn.commit()
        cursor.close()
        conn.close()
        return {
            "success": True,
            "events_affected": len(rows),
            "files_deleted": files_deleted,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/storage/recordings/all")
async def storage_delete_all_recordings(current_user: dict = Depends(get_current_user)):
    require_home_owner(current_user)
    oid = effective_owner_id(current_user)
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            """
            SELECT id, video_path FROM user_events
            WHERE user_id = %s AND video_path IS NOT NULL AND TRIM(video_path) <> ''
            """,
            (oid,),
        )
        rows = cursor.fetchall()
        files_deleted = 0
        for r in rows:
            if _unlink_recording_bytes(r.get("video_path")):
                files_deleted += 1
            cursor.execute(
                "UPDATE user_events SET video_path = NULL WHERE id = %s",
                (r["id"],),
            )
        conn.commit()
        cursor.close()
        conn.close()
        return {"success": True, "clips_cleared": len(rows), "files_deleted": files_deleted}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


_fcm_messaging_ready = False


def init_firebase_messaging() -> None:
    """Optional: set FIREBASE_SERVICE_ACCOUNT_JSON to a Firebase service account file path."""
    global _fcm_messaging_ready
    path = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON", "").strip().strip('"').strip("'")
    if not path:
        print(
            "[FCM] Push disabled: set FIREBASE_SERVICE_ACCOUNT_JSON to your Firebase "
            "service account JSON path (Project settings → Service accounts)."
        )
        return
    if not os.path.isfile(path):
        print(f"[FCM] Push disabled: file not found: {path}")
        return
    try:
        import firebase_admin
        from firebase_admin import credentials

        if not firebase_admin._apps:
            cred = credentials.Certificate(path)
            firebase_admin.initialize_app(cred)
        _fcm_messaging_ready = True
        print("[FCM] Firebase Admin initialized; mobile push enabled.")
    except ImportError:
        print("[FCM] pip install firebase-admin to enable push.")
    except Exception as e:
        print(f"[FCM] Firebase init failed: {e}")


def _owner_wants_push_notifications(owner_user_id: int) -> bool:
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "SELECT notifications_enabled FROM user_options WHERE user_id = %s",
            (owner_user_id,),
        )
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        if row is None:
            return True
        v = row.get("notifications_enabled")
        return v is None or bool(v)
    except Exception as e:
        print(f"[FCM] notifications_enabled check error: {e}")
        return True


def _collect_fcm_tokens_for_home(owner_user_id: int) -> list:
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            """
            SELECT DISTINCT t.token
            FROM user_fcm_tokens t
            WHERE t.user_id = %s
               OR t.user_id IN (
                   SELECT id FROM users WHERE owner_user_id = %s
               )
            """,
            (owner_user_id, owner_user_id),
        )
        rows = cursor.fetchall()
        cursor.close()
        conn.close()
        return [r["token"] for r in rows if r.get("token")]
    except Exception as e:
        print(f"[FCM] token query error: {e}")
        return []


def _delete_fcm_token_value(token: str) -> None:
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("DELETE FROM user_fcm_tokens WHERE token = %s", (token,))
        conn.commit()
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"[FCM] token delete error: {e}")


def send_fcm_event_notifications_sync(
    owner_user_id: int, title: str, body: str, data: dict
) -> None:
    if not _fcm_messaging_ready:
        print(f"[FCM] Skipped (admin not initialized) for owner_user_id={owner_user_id}")
        return
    if not _owner_wants_push_notifications(owner_user_id):
        print(
            f"[FCM] Skipped (notifications_enabled off) for owner_user_id={owner_user_id}"
        )
        return
    tokens = _collect_fcm_tokens_for_home(owner_user_id)
    if not tokens:
        print(
            f"[FCM] Skipped (no device tokens) for owner_user_id={owner_user_id} — "
            "open the app signed in as owner/family so it can register FCM."
        )
        return
    try:
        from firebase_admin import messaging
    except ImportError:
        return
    data_str = {k: str(v) for k, v in data.items() if v is not None}
    try:
        msg = messaging.MulticastMessage(
            notification=messaging.Notification(
                title=title[:80] if title else "HomeGuardian",
                body=(body or "")[:200],
            ),
            data=data_str,
            tokens=tokens,
        )
        resp = messaging.send_each_for_multicast(msg)
        for idx, r in enumerate(resp.responses):
            if r.success:
                continue
            exc = r.exception
            err = str(exc) if exc else ""
            if (
                "not found" in err.lower()
                or "not-registered" in err.lower()
                or "invalid-registration" in err.lower()
                or "registration-token" in err.lower()
            ):
                if idx < len(tokens):
                    _delete_fcm_token_value(tokens[idx])
            else:
                print(f"[FCM] send failure: {err}")
    except Exception as e:
        print(f"[FCM] multicast error: {e}")


async def send_fcm_event_notifications_async(
    owner_user_id: int, title: str, body: str, data: dict
) -> None:
    try:
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(
            None,
            lambda: send_fcm_event_notifications_sync(
                owner_user_id, title, body, data
            ),
        )
    except Exception as e:
        print(f"[FCM] async send error: {e}")


async def send_trusted_person_alert_emails_async(
    owner_user_id: int,
    title: str,
    body: str,
    event_type: Optional[str],
    room_name: Optional[str],
) -> None:
    try:
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(
            None,
            lambda: send_trusted_person_alert_emails(
                owner_user_id,
                title,
                body,
                event_type,
                room_name,
            ),
        )
    except Exception as e:
        print(f"[EMAIL] async trusted alert error: {e}")


async def send_owner_alert_email_async(
    owner_user_id: int,
    title: str,
    body: str,
    event_type: Optional[str],
    room_name: Optional[str],
) -> None:
    try:
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(
            None,
            lambda: send_owner_alert_email(
                owner_user_id,
                title,
                body,
                event_type,
                room_name,
            ),
        )
    except Exception as e:
        print(f"[EMAIL] async alert error: {e}")


def schedule_owner_event_notifications(
    owner_user_id: int,
    event_dict: dict,
    *,
    event_type_fallback: str = "",
    room_name_fallback: str = "",
) -> None:
    """Mobile push + owner email for any row in user_events (respects user toggles)."""
    push_title = str(event_dict.get("title") or "HomeGuardian")
    push_body = str(event_dict.get("description") or push_title)[:200]
    push_data = {
        "event_id": str(event_dict.get("id", "")),
        "event_type": str(event_dict.get("event_type") or ""),
        "room_name": str(event_dict.get("room_name") or ""),
    }
    asyncio.create_task(
        send_fcm_event_notifications_async(
            owner_user_id, push_title, push_body, push_data
        )
    )
    asyncio.create_task(
        send_owner_alert_email_async(
            owner_user_id,
            push_title,
            push_body,
            str(event_dict.get("event_type") or event_type_fallback or ""),
            str(event_dict.get("room_name") or room_name_fallback or ""),
        )
    )
    asyncio.create_task(
        send_trusted_person_alert_emails_async(
            owner_user_id,
            push_title,
            push_body,
            str(event_dict.get("event_type") or event_type_fallback or ""),
            str(event_dict.get("room_name") or room_name_fallback or ""),
        )
    )


async def save_and_broadcast_event(
    user_id: int,
    title: str,
    description: str,
    event_type: str,
    room_name: Optional[str] = None,
):
    """Helper to save an event to DB and broadcast it via WebSocket."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "INSERT INTO user_events (user_id, title, description, event_type, room_name) VALUES (%s, %s, %s, %s, %s) RETURNING *",
            (user_id, title, description, event_type, room_name),
        )
        new_event = cursor.fetchone()
        conn.commit()
        cursor.close()
        conn.close()

        if new_event:
            event_dict = dict(new_event)
            if "timestamp" in event_dict and isinstance(
                event_dict["timestamp"], datetime
            ):
                event_dict["timestamp"] = event_dict["timestamp"].isoformat()

            event_message = {
                "type": "event_created",
                "event": event_dict,
                "recording_expected": True,
            }
            print(f"Broadcasting new event to user {user_id}: {event_dict['title']}")
            await manager.broadcast_to_user(user_id, event_message)
            schedule_owner_event_notifications(
                user_id,
                event_dict,
                event_type_fallback=event_type or "",
                room_name_fallback=room_name or "",
            )
            return new_event
    except Exception as e:
        print(f"Error in save_and_broadcast_event: {e}")
    return None


async def silver_fall_dispatch(
    user_id: int,
    room_name: str,
    probability: Optional[float],
    detail_line: str,
    jpeg_preview: Optional[bytes],
    modes_label: str = "Silver",
) -> Optional[dict]:
    """Persist + push `fall_alert` for laptop-monitor stream (Silver / Nanny / Nurse)."""
    detail = detail_line or ""
    if len(detail) > 420:
        detail = detail[:417] + "..."
    desc_parts = [
        "Fall-like activity detected on the dashboard/laptop monitor stream "
        f"({modes_label} monitoring).",
        "(Same camera feed as Monitor page; verify visually.)",
    ]
    if probability is not None:
        desc_parts.append(f"Estimated probability≈{probability:.2f}.")
    desc = " ".join(desc_parts)
    try:
        new_event = await save_and_broadcast_event(
            user_id=user_id,
            title=f"Possible fall detected ({modes_label})",
            description=desc,
            event_type="emergency",
            room_name=room_name,
        )
        if new_event:
            eid = new_event["id"]
            await manager.broadcast_to_user(
                user_id,
                {
                    "type": "fall_alert",
                    "fall_detected": True,
                    "room_name": room_name,
                    "event_id": eid,
                    "start_recording": True,
                    "probability": probability,
                    "source": "dashboard_stream_fall",
                    "modes": modes_label,
                    "detail": detail,
                },
            )
            if jpeg_preview and len(jpeg_preview) > 120:
                asyncio.create_task(record_event_clip(user_id, eid, jpeg_preview))
            print(f"[MONITOR-FALL-BRIDGE] alert user={user_id} room={room_name!r} evt={eid} modes={modes_label}")
            return new_event
    except Exception as e:
        print(f"[MONITOR-FALL-BRIDGE] dispatch error: {e}")
    return None

# Signup endpoint
@app.post("/api/signup", response_model=dict, status_code=201)
def signup(user: UserCreate, background_tasks: BackgroundTasks):
    if not user.email or not user.password:
        raise HTTPException(status_code=400, detail="Email and password are required")
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        # Check if email already exists
        cursor.execute("SELECT id, is_verified FROM users WHERE email = %s", (user.email,))
        existing_user = cursor.fetchone()
        
        if existing_user and existing_user['is_verified']:
            cursor.close()
            conn.close()
            raise HTTPException(status_code=400, detail="Email already registered")

        hashed_password = get_password_hash(user.password)
        
        if existing_user:
            # User exists but not verified, update their info
            cursor.execute(
                "UPDATE users SET name = %s, password_hash = %s, phone = %s WHERE id = %s",
                (user.name, hashed_password, user.phone, existing_user['id'])
            )
            user_id = existing_user['id']
        else:
            # Insert user
            # For mobile (not dashboard), we auto-verify
            is_verified = not user.is_dashboard
            cursor.execute(
                "INSERT INTO users (name, email, password_hash, phone, is_verified) VALUES (%s, %s, %s, %s, %s) RETURNING id",
                (user.name, user.email, hashed_password, user.phone, is_verified)
            )
            user_id = cursor.fetchone()['id']
        
        # Save images if provided
        if user.profile_images:
            # Use the first image as the main profile image for the DB
            main_profile_path = save_image_from_base64(user.profile_images[0], user_id)
            if main_profile_path:
                cursor.execute(
                    "UPDATE users SET profile_image = %s WHERE id = %s",
                    (main_profile_path, user_id)
                )
            
            # Enroll ALL images for face recognition
            for i, photo_base64 in enumerate(user.profile_images):
                enroll_face_photo(photo_base64, user.name, index=i, user_id=user_id)
        
        # Initialize default user options
        cursor.execute(
            "INSERT INTO user_options (user_id) VALUES (%s) ON CONFLICT (user_id) DO NOTHING",
            (user_id,)
        )

        if user.is_dashboard:
            # Generate OTP for Dashboard
            import random
            otp_code = ''.join([str(random.randint(0, 9)) for _ in range(6)])
            
            cursor.execute(
                "INSERT INTO otp_codes (email, code) VALUES (%s, %s)",
                (user.email, otp_code)
            )
            conn.commit()
            
            # Respond immediately; SMTP can take 10+ seconds and must not block login.
            background_tasks.add_task(send_otp_email, user.email, otp_code)
            
            cursor.close()
            conn.close()
            return {
                "success": True,
                "message": f"OTP sent to {user.email}.",
                "email": user.email,
                "requires_verification": True
            }
        else:
            # Direct login for Mobile
            conn.commit()
            access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
            access_token = create_access_token(
                data={"sub": user.email, "id": user_id}, expires_delta=access_token_expires
            )
            
            cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
            result = cursor.fetchone()
            user_data = dict(result)
            user_data.pop('password_hash', None)
            
            cursor.close()
            conn.close()
            return {
                "success": True,
                "access_token": access_token,
                "token_type": "bearer",
                "user": user_data
            }

    except psycopg2.Error as e:
        print(f"Database error: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to create user: {str(e)}")
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

# Verify OTP endpoint
@app.post("/api/verify-otp", response_model=Token)
def verify_otp(verify_data: OTPVerify):
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        # Check OTP (get latest for email)
        cursor.execute(
            "SELECT code FROM otp_codes WHERE email = %s ORDER BY created_at DESC LIMIT 1",
            (verify_data.email,)
        )
        row = cursor.fetchone()
        
        if not row or row['code'] != verify_data.otp:
            cursor.close()
            conn.close()
            raise HTTPException(status_code=400, detail="Invalid OTP code")
            
        # Mark user as verified
        cursor.execute(
            "UPDATE users SET is_verified = TRUE WHERE email = %s RETURNING *",
            (verify_data.email,)
        )
        user = cursor.fetchone()
        
        if not user:
            cursor.close()
            conn.close()
            raise HTTPException(status_code=404, detail="User not found")

        if user.get("role") == "family":
            cursor.close()
            conn.close()
            raise HTTPException(
                status_code=403,
                detail="Family member accounts cannot access the web dashboard.",
            )
            
        # Initialize default user options
        cursor.execute(
            "INSERT INTO user_options (user_id) VALUES (%s) ON CONFLICT (user_id) DO NOTHING",
            (user['id'],)
        )
        
        conn.commit()
        
        # Create access token
        access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
        access_token = create_access_token(
            data={"sub": user['email'], "id": user['id']}, expires_delta=access_token_expires
        )
        
        user_data = dict(user)
        user_data.pop('password_hash', None)
        
        cursor.close()
        conn.close()
        
        return {
            "access_token": access_token,
            "token_type": "bearer",
            "user": user_data
        }
    except psycopg2.Error as e:
        raise HTTPException(status_code=500, detail=str(e))
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Login endpoint
@app.post("/api/login", response_model=dict)
def login(user_login: UserLogin, background_tasks: BackgroundTasks):
    try:
        print(f"[DEBUG LOGIN] Attempt for email: {user_login.email}, is_dashboard: {user_login.is_dashboard}")
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        cursor.execute("SELECT * FROM users WHERE email = %s", (user_login.email,))
        user = cursor.fetchone()
        
        cursor.close()
        conn.close()
        
        if not user:
            print(f"[DEBUG LOGIN] User not found: {user_login.email}")
            raise HTTPException(
                status_code=401,
                detail="Incorrect email or password",
                headers={"WWW-Authenticate": "Bearer"},
            )

        print(f"[DEBUG LOGIN] User found. Verifying password...")
        if not verify_password(user_login.password, user.get('password_hash', '')):
            print(f"[DEBUG LOGIN] Password mismatch for: {user_login.email}")
            raise HTTPException(
                status_code=401,
                detail="Incorrect email or password",
                headers={"WWW-Authenticate": "Bearer"},
            )

        if user_login.is_dashboard and user.get("role") == "family":
            raise HTTPException(
                status_code=403,
                detail="Family member accounts cannot sign in to the web dashboard. Use the mobile app.",
            )
        
        # OTP check ONLY if it's the dashboard
        if user_login.is_dashboard:
             print(f"[DEBUG LOGIN] Dashboard login triggers OTP for: {user_login.email}")
             # Generate and send a new OTP
             import random
             otp_code = ''.join([str(random.randint(0, 9)) for _ in range(6)])
             
             conn = get_db_connection()
             cursor = conn.cursor()
             cursor.execute(
                 "INSERT INTO otp_codes (email, code) VALUES (%s, %s)",
                 (user['email'], otp_code)
             )
             conn.commit()
             cursor.close()
             conn.close()

             # Respond immediately; SMTP can take 10+ seconds and must not block login.
             background_tasks.add_task(send_otp_email, user['email'], otp_code)

             return {
                 "success": True,
                 "requires_verification": True,
                 "email": user['email'],
                 "message": "Security verification required. Code sent to your inbox."
             }

        print(f"[DEBUG LOGIN] Login successful for: {user_login.email}")
        # Create access token
        access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
        access_token = create_access_token(
            data={"sub": user['email'], "id": user['id']}, expires_delta=access_token_expires
        )
        
        user_data = dict(user)
        user_data.pop('password_hash', None)
        
        return {
            "success": True,
            "access_token": access_token,
            "token_type": "bearer",
            "user": user_data
        }

    except psycopg2.Error as e:
        print(f"Database error: {e}")
        raise HTTPException(status_code=500, detail="Database connection error")

# Face Login endpoint
@app.post("/api/face-login", response_model=Token)
async def face_login(file: UploadFile = File(...)):
    temp_filename = f"temp_login_{datetime.now().strftime('%Y%m%d_%H%M%S')}.jpg"
    temp_filepath = UPLOAD_DIR / temp_filename
    
    FACE_MODEL = "Facenet512" 
    METRIC = "cosine"
    STRICT_THRESHOLD = 0.30 
    
    try:
        with open(temp_filepath, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        print(f"[FACE LOGIN] Attempting login. Model={FACE_MODEL}, Threshold={STRICT_THRESHOLD}")
        
        try:
            uploaded_results = DeepFace.represent(
                img_path=str(temp_filepath), 
                model_name=FACE_MODEL,
                enforce_detection=True,
                align=True
            )
            if not uploaded_results:
                 raise ValueError("No face detected in uploaded photo")
            uploaded_embedding = uploaded_results[0]["embedding"]
        except ValueError as e:
            if "Face could not be detected" in str(e):
                raise HTTPException(
                    status_code=400,
                    detail="No face detected in your photo. Please try again with a clearer picture."
                )
            raise e

        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        cursor.execute(
            """SELECT id, email, name, profile_image FROM users 
               WHERE profile_image IS NOT NULL 
               AND COALESCE(role, 'user') <> 'family'"""
        )
        users = cursor.fetchall()
        
        cursor.close()
        conn.close()
        
        all_candidates = []
        for u in users:
            all_candidates.append({
                'id': u['id'],
                'email': u['email'],
                'name': u['name'],
                'path': u['profile_image'],
                'display_id': u['email']
            })
            
        if not all_candidates:
            raise HTTPException(status_code=404, detail="No enrolled users found in database.")

        best_match = None
        min_distance = float('inf')
        
        for i, candidate in enumerate(all_candidates):
            try:
                db_image_path = candidate['path']
                if not db_image_path or not os.path.exists(db_image_path):
                    continue
                
                db_results = DeepFace.represent(
                    img_path=db_image_path,
                    model_name=FACE_MODEL,
                    enforce_detection=False, 
                    align=True
                )
                
                if not db_results:
                    continue
                    
                db_embedding = db_results[0]["embedding"]
                
                import numpy as np
                a = np.array(uploaded_embedding)
                b = np.array(db_embedding)
                distance = 1 - np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))
                
                if distance < min_distance:
                    min_distance = distance
                    if distance <= STRICT_THRESHOLD:
                        best_match = candidate
                        
            except Exception as e:
                continue

        if temp_filepath.exists():
            temp_filepath.unlink()
            
        if best_match:
            conn = get_db_connection()
            cursor = conn.cursor(cursor_factory=RealDictCursor)
            cursor.execute("SELECT * FROM users WHERE id = %s", (best_match['id'],))
            user_record = cursor.fetchone()
            cursor.close()
            conn.close()
            
            access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
            access_token = create_access_token(
                data={"sub": user_record['email'], "id": user_record['id']}, 
                expires_delta=access_token_expires
            )
            
            user_data = dict(user_record)
            user_data.pop('password_hash', None)
            
            return {
                "access_token": access_token,
                "token_type": "bearer",
                "user": user_data
            }
        else:
            raise HTTPException(
                status_code=401,
                detail="Face not recognized or match not strong enough.",
                headers={"WWW-Authenticate": "Bearer"},
            )

    except HTTPException:
        if temp_filepath.exists():
            temp_filepath.unlink()
        raise
    except Exception as e:
        if temp_filepath.exists():
            temp_filepath.unlink()
        raise HTTPException(status_code=500, detail=str(e))

# Fire detection endpoint
@app.post("/api/detect-fire")
async def detect_fire(file: UploadFile = File(...), current_user: dict = Depends(get_current_user)):
    require_home_owner(current_user)
    try:
        contents = await file.read()
        service = get_fire_detection_service()
        result = service.detect_from_image(contents)
        
        if not result.get("success", False):
            raise HTTPException(
                status_code=400,
                detail=result.get("error", "Failed to process image")
            )
        
        if result.get("fire_detected", False):
            # Save the event to the database and broadcast it
            oid = effective_owner_id(current_user)
            new_event = await save_and_broadcast_event(
                user_id=oid,
                title="Fire Detected!",
                description=f"Fire detected manually. Confidence: {result.get('confidence', 0.0):.2f}",
                event_type="emergency",
                room_name="Manual Scan"
            )

            if new_event:
                # Broadcast the event specifically for dashboard/mobile UI
                event_dict = dict(new_event)
                if 'timestamp' in event_dict and isinstance(event_dict['timestamp'], datetime):
                    event_dict['timestamp'] = event_dict['timestamp'].isoformat()
                
                await manager.broadcast_to_user(oid, {
                    "type": "event_created",
                    "event": event_dict
                })

            alert_message = {
                "type": "fire_alert",
                "fire_detected": True,
                "confidence": result.get("confidence", 0.0),
                "detection_count": result.get("detection_count", 0),
                "timestamp": datetime.now().isoformat(),
                "source": "manual_capture"
            }
            await manager.broadcast_to_user(oid, alert_message)

        return {
            "success": True,
            "fire_detected": result.get("fire_detected", False),
            "confidence": result.get("confidence", 0.0),
            "detections": result.get("detections", []),
            "detection_count": result.get("detection_count", 0),
            "timestamp": datetime.now().isoformat()
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

# Door detection endpoint (Manual)
@app.post("/api/detect-door")
async def detect_door(file: UploadFile = File(...), current_user: dict = Depends(get_current_user)):
    require_home_owner(current_user)
    try:
        is_home_alone = False
        oid = effective_owner_id(current_user)
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute("SELECT selected_modes FROM user_options WHERE user_id = %s", (oid,))
        options = cursor.fetchone()
        cursor.close()
        conn.close()
        
        if options and options['selected_modes']:
            modes = options['selected_modes']
            if isinstance(modes, str):
                modes = json.loads(modes)
            
            for mode in modes:
                mode_str = mode if isinstance(mode, str) else mode.get('title', '')
                if "home" in mode_str.lower() and "alone" in mode_str.lower():
                    is_home_alone = True
                    break
        
        if not is_home_alone:
            return {
                "success": False,
                "error": "HomeAlone mode is not active. Door detection is disabled.",
                "is_home_alone_active": False
            }

        contents = await file.read()
        if door_window_bridge_mod is None:
            raise HTTPException(
                status_code=503,
                detail="Door/window detection model is unavailable."
            )
        door_open, window_open, _dw_info = await asyncio.to_thread(
            door_window_bridge_mod.process_upload_jpeg,
            contents,
        )
        combined_detections = (
            _dw_info.get("door_detections", []) + _dw_info.get("window_detections", [])
        )
        result = {
            "success": True,
            "event_detected": bool(door_open or window_open),
            "detections": combined_detections,
            "detection_count": len(combined_detections),
        }
        
        if result.get("event_detected", False):
            # Save the event to the database and broadcast it
            _scan_label = "Door" if door_open else "Window"
            new_event = await save_and_broadcast_event(
                user_id=oid,
                title=f"{_scan_label} Opened!",
                description=f"A {_scan_label.lower()} was detected OPEN (manual scan).",
                event_type="security",
                room_name="Manual Scan"
            )

            if new_event:
                # Broadcast the event specifically for dashboard/mobile UI
                event_dict = dict(new_event)
                if 'timestamp' in event_dict and isinstance(event_dict['timestamp'], datetime):
                    event_dict['timestamp'] = event_dict['timestamp'].isoformat()
                
                await manager.broadcast_to_user(oid, {
                    "type": "event_created",
                    "event": event_dict
                })

            alert_message = {
                "type": "door_alert",
                "event_detected": True,
                "detections": result.get("detections", []),
                "timestamp": datetime.now().isoformat(),
                "source": "manual_capture"
            }
            await manager.broadcast_to_user(oid, alert_message)

        return {
            "success": True,
            "event_detected": result.get("event_detected", False),
            "detections": result.get("detections", []),
            "detection_count": result.get("detection_count", 0),
            "is_home_alone_active": True,
            "timestamp": datetime.now().isoformat()
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

# WebSocket endpoint for mobile clients to receive fire alerts
@app.websocket("/ws/fire-alerts")
async def websocket_fire_alerts(websocket: WebSocket, user_id: Optional[int] = None):
    await websocket.accept()
    
    if not user_id:
        try:
            initial_data = await websocket.receive_text()
            try:
                user_id = int(initial_data)
            except ValueError:
                await websocket.close(code=1003)
                return
        except Exception:
            return

    await manager.connect_socket(websocket, user_id)
    
    try:
        while True:
            data = await websocket.receive_text()
            if data == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        manager.disconnect(websocket, user_id)
    except Exception:
        manager.disconnect(websocket, user_id)

# Ensure upload directories exist
Path("profile_images").mkdir(exist_ok=True)
Path("recordings").mkdir(exist_ok=True)


@app.get("/recordings/{filename}")
async def serve_owned_recording(
    filename: str, current_user: dict = Depends(get_current_user)
):
    """
    Recordings are encrypted on disk (.enc). Only the home owner / family account
    tied to that owner's events may download. Replaces the old public StaticFiles mount.
    """
    if ".." in filename or "/" in filename or "\\" in filename:
        raise HTTPException(status_code=400, detail="Invalid path")
    safe = Path(filename).name
    if safe != filename:
        raise HTTPException(status_code=400, detail="Invalid path")
    oid = effective_owner_id(current_user)
    if not _user_owns_recording_file(oid, safe):
        raise HTTPException(status_code=404, detail="Not found")
    local = Path("recordings") / safe
    if not local.is_file():
        raise HTTPException(status_code=404, detail="Not found")
    media = "application/octet-stream"
    suf = local.suffix.lower()
    if suf in (".mp4", ".m4v"):
        media = "video/mp4"
    elif suf in (".webm",):
        media = "video/webm"
    return FileResponse(
        path=str(local.resolve()),
        media_type=media,
        filename=safe,
        headers={"Cache-Control": "private, no-store"},
    )

def _resolve_ffmpeg_bin() -> Optional[str]:
    """
    Prefer FFMPEG_PATH, then PATH, then WinGet's Gyan.FFmpeg package layout (Windows often
    lacks ffmpeg on PATH until a full new logon).
    """
    override = os.getenv("FFMPEG_PATH", "").strip().strip('"')
    if override and os.path.isfile(override):
        return override
    w = shutil.which("ffmpeg")
    if w:
        return w
    if os.name != "nt":
        return None
    local = os.environ.get("LOCALAPPDATA", "")
    if not local:
        return None
    packages = Path(local) / "Microsoft" / "WinGet" / "Packages"
    if not packages.is_dir():
        return None
    for d in sorted(packages.iterdir()):
        if not d.is_dir() or not d.name.startswith("Gyan.FFmpeg"):
            continue
        for candidate in d.glob("**/bin/ffmpeg.exe"):
            if candidate.is_file():
                return str(candidate)
    return None


try:
    from Crypto.Cipher import AES
    from Crypto.Util.Padding import pad, unpad

    _CLIP_CRYPTO_READY = True
except ImportError:
    _CLIP_CRYPTO_READY = False

# Must match lib/services/security_service.dart (AES-CBC + PKCS7, IV = 16 zero bytes).
# Optional: set RECORDINGS_AES_KEY to a 32+ char secret (first 32 used); then update
# SecurityService in the app to the same key or clips cannot be played on mobile.
# 16 zero bytes — must match Flutter SecurityService `_iv` (IV.allZerosOfLength(16)), not random IV.
_CLIP_AES_IV = bytes(16)


def _recording_aes_key_bytes() -> bytes:
    envk = os.getenv("RECORDINGS_AES_KEY", "").strip()
    if len(envk) >= 32:
        return envk[:32].encode("utf-8")
    return b"my32characterultrasecretkey12345"


_CLIP_AES_KEY = _recording_aes_key_bytes()


def _encrypt_bytes_at_rest(plain: bytes) -> Optional[bytes]:
    """AES-CBC + PKCS7; same as Flutter SecurityService.encryptBytes."""
    if not _CLIP_CRYPTO_READY or not plain:
        return None
    try:
        cipher = AES.new(_CLIP_AES_KEY, AES.MODE_CBC, _CLIP_AES_IV)
        return cipher.encrypt(pad(plain, AES.block_size))
    except (ValueError, TypeError, KeyError):
        return None


def _finalize_clip_encrypted_storage(plain_disk_path_str: str) -> tuple[str, str]:
    """
    Store clip encrypted at rest (Explorer cannot show video thumbnails).
    Plain MP4/WebM is encrypted; existing ciphertext is kept as-is.
    Returns (absolute_path, db_path like /recordings/name.enc).
    """
    p = Path(plain_disk_path_str)
    if not p.is_file():
        return plain_disk_path_str, f"/recordings/{p.name}"

    try:
        data = p.read_bytes()
    except OSError:
        return plain_disk_path_str, f"/recordings/{p.name}"

    if len(data) < 4:
        return str(p.resolve()), f"/recordings/{p.name}"

    head16 = data[:16]
    head4 = data[:4]
    is_plain_media = _head_is_mp4_magic(head16) or _head_is_webm_ebml(head4)

    if is_plain_media:
        ct = _encrypt_bytes_at_rest(data)
        if ct is None:
            print(
                "[recordings] PyCryptodome unavailable — clip left as plain media on disk."
            )
            return str(p.resolve()), f"/recordings/{p.name}"
        blob = ct
    else:
        blob = data

    out_name = f"{p.stem}.enc"
    out_path = p.parent / out_name
    try:
        out_path.write_bytes(blob)
    except OSError as e:
        print(f"[recordings] failed to write encrypted clip: {e}")
        return str(p.resolve()), f"/recordings/{p.name}"

    try:
        if p.resolve() != out_path.resolve():
            p.unlink()
    except OSError:
        pass

    return str(out_path.resolve()), f"/recordings/{out_path.name}"


def _user_owns_recording_file(user_id: int, filename: str) -> bool:
    """True if this owner has an event pointing at this recordings/ basename."""
    norm_a = f"/recordings/{filename}"
    norm_b = f"recordings/{filename}"
    like_tail = f"%/{filename}"
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT 1 FROM user_events
            WHERE user_id = %s
              AND video_path IS NOT NULL
              AND TRIM(video_path) <> ''
              AND (
                  TRIM(video_path) = %s
                  OR TRIM(video_path) = %s
                  OR TRIM(video_path) LIKE %s
              )
            LIMIT 1
            """,
            (user_id, norm_a, norm_b, like_tail),
        )
        ok = cursor.fetchone() is not None
        cursor.close()
        conn.close()
        return ok
    except Exception as e:
        print(f"[recordings] ownership check failed: {e}")
        return False


def _head_is_mp4_magic(h: bytes) -> bool:
    return len(h) >= 12 and h[4:8] == b"ftyp"


def _head_is_webm_ebml(h: bytes) -> bool:
    return len(h) >= 4 and h.startswith(b"\x1a\x45\xdf\xa3")


def _try_decrypt_mobile_upload(ciphertext: bytes) -> Optional[bytes]:
    """Decrypt camera clip bytes encrypted by Flutter SecurityService before upload."""
    if not _CLIP_CRYPTO_READY or not ciphertext:
        return None
    if len(ciphertext) < 16 or len(ciphertext) % 16 != 0:
        return None
    try:
        cipher = AES.new(_CLIP_AES_KEY, AES.MODE_CBC, _CLIP_AES_IV)
        plain = unpad(cipher.decrypt(ciphertext), AES.block_size)
    except (ValueError, TypeError, KeyError):
        return None
    sample = plain[:32]
    if _head_is_mp4_magic(sample) or _head_is_webm_ebml(sample):
        return plain
    return None


def _work_path_for_transcode(p: Path) -> tuple[Path, bytes, Optional[Path]]:
    """
    Return (path_passed_to_ffmpeg_or_rename, first_32_bytes, temp_decrypt_file_or_none).
    """
    with open(p, "rb") as f:
        head = f.read(32)
    if _head_is_mp4_magic(head) or _head_is_webm_ebml(head):
        return p, head, None
    with open(p, "rb") as f:
        raw = f.read()
    dec = _try_decrypt_mobile_upload(raw)
    if dec is None:
        return p, head, None
    tmp = p.parent / f".dec_{p.stem}_{os.getpid()}.bin"
    tmp.write_bytes(dec)
    return tmp, dec[:32], tmp


def _normalize_event_clip_for_playback(
    file_path: str, stored_filename: str, trim_start_sec: Optional[float] = None
) -> tuple[str, str]:
    """
    Prefer H.264 MP4 for Android ExoPlayer. WebM/Matroska is transcoded when ffmpeg is available.
    Mobile camera clips are AES-encrypted on disk (SecurityService.encryptBytes); decrypt here first.
    Returns (absolute path on disk, public path e.g. /recordings/clip.mp4).
    """
    p = Path(file_path)
    stem = p.stem
    out_dir = p.parent

    def db_url(name: str) -> str:
        return f"/recordings/{name}"

    try:
        work, head, tmp_dec = _work_path_for_transcode(p)
    except OSError:
        return file_path, f"/recordings/{stored_filename}"

    def cleanup_tmp():
        if tmp_dec is not None and tmp_dec.is_file():
            try:
                tmp_dec.unlink()
            except OSError:
                pass

    if _head_is_mp4_magic(head):
        new_name = f"{stem}.mp4"
        new_path = out_dir / new_name
        try:
            if str(work.resolve()) == str(p.resolve()) and p.suffix.lower() == ".mp4":
                cleanup_tmp()
                return str(p), db_url(stored_filename)
            os.replace(str(work), str(new_path))
            if str(work.resolve()) != str(p.resolve()):
                try:
                    p.unlink()
                except OSError:
                    pass
            cleanup_tmp()
            return str(new_path), db_url(new_name)
        except OSError:
            cleanup_tmp()
            return file_path, db_url(stored_filename)

    if _head_is_webm_ebml(head):
        ffmpeg_bin = _resolve_ffmpeg_bin()
        if not ffmpeg_bin:
            print(
                "[upload-event-clip] ffmpeg not found — clip left as WebM; "
                "many Android phones cannot play VP9 WebM. Install FFmpeg (winget is fine), "
                "or set FFMPEG_PATH in server .env to the full path of ffmpeg.exe, then restart "
                "the server and upload a new clip."
            )
            cleanup_tmp()
            return file_path, db_url(stored_filename)
        if not shutil.which("ffmpeg"):
            print(f"[upload-event-clip] using ffmpeg (not on PATH): {ffmpeg_bin}")

        mp4_name = f"{stem}.mp4"
        mp4_path = out_dir / mp4_name
        audio_modes = (
            ("-c:a", "aac", "-b:a", "128k"),
            ("-an",),
        )
        for audio_args in audio_modes:
            try:
                ff_args = [
                    ffmpeg_bin,
                    "-y",
                ]
                if trim_start_sec and trim_start_sec > 0.05:
                    ff_args.extend(["-ss", str(trim_start_sec)])
                ff_args.extend(
                    [
                        "-i",
                        str(work),
                        "-c:v",
                        "libx264",
                        "-preset",
                        "veryfast",
                        "-crf",
                        "23",
                        "-pix_fmt",
                        "yuv420p",
                        *audio_args,
                        "-movflags",
                        "+faststart",
                        str(mp4_path),
                    ]
                )
                subprocess.run(
                    ff_args,
                    capture_output=True,
                    timeout=180,
                    check=True,
                )
                try:
                    if str(work.resolve()) != str(p.resolve()) and work.is_file():
                        work.unlink()
                except OSError:
                    pass
                try:
                    p.unlink()
                except OSError:
                    pass
                cleanup_tmp()
                print(f"[upload-event-clip] transcoded to {mp4_name} (audio_args={audio_args[0]})")
                return str(mp4_path), db_url(mp4_name)
            except FileNotFoundError:
                print(
                    "[upload-event-clip] ffmpeg executable missing — clip left as WebM."
                )
                break
            except subprocess.CalledProcessError as e:
                err = (e.stderr or b"").decode("utf-8", errors="replace").strip()
                if err:
                    tail = err[-800:] if len(err) > 800 else err
                    print(f"[upload-event-clip] ffmpeg failed ({audio_args[0]}): {tail}")
                try:
                    if mp4_path.exists():
                        mp4_path.unlink()
                except OSError:
                    pass
            except subprocess.TimeoutExpired:
                print("[upload-event-clip] ffmpeg timed out; clip left as WebM.")
                try:
                    if mp4_path.exists():
                        mp4_path.unlink()
                except OSError:
                    pass
        cleanup_tmp()
        return file_path, db_url(stored_filename)

    cleanup_tmp()
    return file_path, db_url(stored_filename)

@app.post("/api/upload-event-clip")
async def upload_event_clip(
    file: UploadFile = File(...),
    user_id: int = Form(...),
    room_name: str = Form("Unknown"),
    event_id: Optional[int] = Form(None),
    clip_trim_start_sec: Optional[float] = Form(None),
):
    try:
        # Use .enc extension to indicate encrypted content
        filename = f"clip_{user_id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.enc"
        file_path = os.path.join("recordings", filename)
        
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        trim = None
        if clip_trim_start_sec is not None:
            try:
                trim = float(clip_trim_start_sec)
                if trim <= 0:
                    trim = None
            except (TypeError, ValueError):
                trim = None

        file_path, db_path = _normalize_event_clip_for_playback(
            file_path, filename, trim_start_sec=trim
        )
        file_path, db_path = _finalize_clip_encrypted_storage(file_path)

        conn = get_db_connection()
        if event_id:
            cursor = conn.cursor()
            cursor.execute(
                "UPDATE user_events SET video_path = %s, room_name = %s WHERE id = %s AND user_id = %s",
                (db_path, room_name, event_id, user_id)
            )
            conn.commit()
            cursor.close()
        else:
            cursor = conn.cursor(cursor_factory=RealDictCursor)
            cursor.execute(
                """
                INSERT INTO user_events (user_id, title, description, event_type, video_path, room_name)
                VALUES (%s, %s, %s, %s, %s, %s)
                RETURNING *
                """,
                (user_id, "Recording Uploaded", f"Automatic recording from laptop in {room_name}", "security", db_path, room_name),
            )
            row = cursor.fetchone()
            conn.commit()
            cursor.close()
            if row:
                event_dict = dict(row)
                if "timestamp" in event_dict and isinstance(
                    event_dict["timestamp"], datetime
                ):
                    event_dict["timestamp"] = event_dict["timestamp"].isoformat()
                await manager.broadcast_to_user(
                    user_id,
                    {
                        "type": "event_created",
                        "event": event_dict,
                        "recording_expected": False,
                    },
                )
                schedule_owner_event_notifications(
                    user_id,
                    event_dict,
                    event_type_fallback="security",
                    room_name_fallback=room_name,
                )

        conn.close()
        
        return {"success": True, "video_path": db_path}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/monitoring/heartbeat")
async def camera_heartbeat(
    user_id: int = Form(...),
    cameras: str = Form(...) # JSON string of cameras: [{"id": "0", "name": "Built-in Cam"}]
):
    try:
        camera_list = json.loads(cameras)
        if user_id not in active_user_cameras:
            active_user_cameras[user_id] = {}
        
        now = datetime.now()
        current_cam_ids = set()
        
        changed = False
        for cam in camera_list:
            cam_id = str(cam.get("id"))
            cam_name = cam.get("name", f"Camera {cam_id}")
            current_cam_ids.add(cam_id)
            
            if cam_id not in active_user_cameras[user_id]:
                changed = True
            
            active_user_cameras[user_id][cam_id] = {
                "name": cam_name,
                "last_seen": now
            }
        
        # Remove old cameras for this user
        to_remove = [cid for cid in active_user_cameras[user_id] if cid not in current_cam_ids]
        if to_remove:
            changed = True
            for cid in to_remove:
                del active_user_cameras[user_id][cid]
        
        if changed:
            # Notify mobile app via WebSocket
            await manager.broadcast_to_user(user_id, {
                "type": "camera_list_updated",
                "cameras": [
                    {"id": cid, "name": info["name"]} 
                    for cid, info in active_user_cameras[user_id].items()
                ]
            })
            
        return {"success": True}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/api/family/status")
async def get_family_status(current_user: dict = Depends(get_current_user)):
    """Returns the 'At Home' or 'Away' status of family members"""
    user_id = effective_owner_id(current_user)
    
    # Get all registered family members first
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            """
            SELECT fm.name,
                   (SELECT mp.photo_path FROM member_photos mp
                    WHERE mp.member_id = fm.id AND mp.member_type = 'family'
                    ORDER BY mp.id ASC LIMIT 1) AS photo_path
            FROM family_members fm
            WHERE fm.user_id = %s
            """,
            (user_id,),
        )
        members = cursor.fetchall()
        cursor.execute("SELECT name FROM trusted_persons WHERE user_id = %s", (user_id,))
        trusted = cursor.fetchall()
        cursor.close()
        conn.close()
        
        all_names = [m["name"] for m in members] + [t["name"] for t in trusted]
        photo_by_name = {m["name"]: m.get("photo_path") for m in members if m.get("name")}
        
        status_map = family_home_status.get(user_id, {})
        result = []
        
        for name in all_names:
            status_data = status_map.get(name, {"status": "Away", "last_seen": None})
            # Double check timeout
            if status_data["last_seen"] and (datetime.now() - status_data["last_seen"]).total_seconds() > HOME_TIMEOUT_MINUTES * 60:
                status_data["status"] = "Away"
                
            result.append({
                "name": name,
                "status": status_data["status"],
                "last_seen": status_data["last_seen"].isoformat() if status_data["last_seen"] else None,
                "photo_path": photo_by_name.get(name),
            })
            
        return {"success": True, "members": result}
    except Exception as e:
        print(f"[ERROR STATUS] {e}")
        return {"success": False, "error": str(e)}

@app.get("/api/monitoring/cameras")
async def get_active_cameras(current_user: dict = Depends(get_current_user)):
    user_id = effective_owner_id(current_user)
    now = datetime.now()
    
    # Clean up stale cameras (not seen in 30 seconds)
    if user_id in active_user_cameras:
        stale_ids = [
            cid for cid, info in active_user_cameras[user_id].items()
            if (now - info["last_seen"]).total_seconds() > 30
        ]
        for cid in stale_ids:
            del active_user_cameras[user_id][cid]
            
    cameras = []
    if user_id in active_user_cameras:
        for cid, info in active_user_cameras[user_id].items():
            cameras.append({"id": cid, "name": info["name"]})
            
    return {"success": True, "cameras": cameras}


_MONITOR_MODE_CANONICAL = frozenset({"silver", "nanny", "nurse", "pet", "home_alone"})


def _canonical_monitor_mode(token: object) -> Optional[str]:
    if not isinstance(token, str):
        return None
    s = token.strip()
    if not s:
        return None
    low = s.lower().replace("-", "_")
    if "home" in low and "alone" in low:
        return "home_alone"
    if "silver" in low:
        return "silver"
    if "nanny" in low:
        return "nanny"
    if "nurse" in low:
        return "nurse"
    if "pet" in low:
        return "pet"
    if low in _MONITOR_MODE_CANONICAL:
        return low
    return None


def normalize_monitor_modes_list(raw: object) -> List[str]:
    """Return unique canonical monitor mode ids (optional per-room toggles)."""
    if raw is None:
        return []
    if isinstance(raw, str):
        try:
            raw = json.loads(raw)
        except Exception:
            return []
    if not isinstance(raw, list):
        return []
    seen: List[str] = []
    for item in raw:
        key = _canonical_monitor_mode(item) if isinstance(item, str) else None
        if key and key not in seen:
            seen.append(key)
    return seen


def _monitor_modes_from_db_value(val: object) -> List[str]:
    if val is None:
        return []
    if isinstance(val, (list, dict)):
        if isinstance(val, dict):
            return []
        return normalize_monitor_modes_list(val)
    if isinstance(val, str):
        return normalize_monitor_modes_list(val)
    return []


def _load_assignment_monitor_modes_set(uid: int, room_label: str) -> Set[str]:
    rl = (room_label or "").strip()
    if not rl or rl == "Unknown":
        return set()
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            """
            SELECT monitor_modes FROM user_camera_assignments
            WHERE user_id = %s AND room_name = %s
            """,
            (uid, rl),
        )
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        if not row:
            return set()
        return set(_monitor_modes_from_db_value(row.get("monitor_modes")))
    except Exception:
        return set()


@app.get("/api/monitoring/assignment")
async def get_camera_assignment(current_user: dict = Depends(get_current_user)):
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        oid = effective_owner_id(current_user)
        cursor.execute(
            """
            SELECT id, room_name, camera_id, camera_name, monitor_modes
            FROM user_camera_assignments
            WHERE user_id = %s
            ORDER BY id
            """,
            (oid,),
        )
        rows = cursor.fetchall()
        cursor.close()
        conn.close()
        assignment = rows[0] if rows else None
        return {"success": True, "assignments": rows, "assignment": assignment}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.post("/api/monitoring/assignment")
async def save_camera_assignment(
    room_name: Optional[str] = Form(None),
    camera_id: Optional[str] = Form(None),
    camera_name: Optional[str] = Form(None),
    monitor_modes_json: Optional[str] = Form(None),
    data: Optional[dict] = None, # For JSON support
    current_user: dict = Depends(get_current_user)
):
    require_home_owner(current_user)
    try:
        # Support both JSON and Form data
        if not room_name and not camera_id and data:
            room_name = data.get("room_name")
            camera_id = data.get("camera_id")
            camera_name = data.get("camera_name")
            # If monitor_modes is passed as a list in JSON, stringify it for the logic below
            m_modes = data.get("monitor_modes")
            if isinstance(m_modes, list):
                monitor_modes_json = json.dumps(m_modes)
            else:
                monitor_modes_json = data.get("monitor_modes_json")

        if not room_name or not camera_id:
            raise HTTPException(status_code=422, detail="room_name and camera_id are required")

        conn = get_db_connection()
        cursor = conn.cursor()
        oid = effective_owner_id(current_user)

        cursor.execute(
            """
            SELECT monitor_modes FROM user_camera_assignments
            WHERE user_id = %s AND room_name = %s
            """,
            (oid, room_name),
        )
        prev = cursor.fetchone()
        existing_raw = prev[0] if prev else None

        if monitor_modes_json is not None:
            try:
                parsed = json.loads(monitor_modes_json)
            except Exception:
                parsed = []
            modes_list = normalize_monitor_modes_list(parsed)
        else:
            modes_list = _monitor_modes_from_db_value(existing_raw)

        cursor.execute(
            """
            INSERT INTO user_camera_assignments
                (user_id, room_name, camera_id, camera_name, monitor_modes)
            VALUES (%s, %s, %s, %s, %s::jsonb)
            ON CONFLICT (user_id, room_name)
            DO UPDATE SET camera_id = EXCLUDED.camera_id,
                          camera_name = EXCLUDED.camera_name,
                          monitor_modes = EXCLUDED.monitor_modes
            """,
            (oid, room_name, camera_id, camera_name, Json(modes_list)),
        )
        
        conn.commit()
        cursor.close()
        conn.close()
        
        # Also update the active monitoring session automatically
        if oid not in active_monitoring_sessions:
            active_monitoring_sessions[oid] = {}
        active_monitoring_sessions[oid][room_name] = camera_id
        
        try:
            await manager.broadcast_to_user(oid, {"type": "monitoring_assignments_updated"})
        except Exception:
            pass

        return {"success": True}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.delete("/api/monitoring/assignment")
async def delete_camera_assignment(
    room_name: Optional[str] = Query(None),
    current_user: dict = Depends(get_current_user),
):
    require_home_owner(current_user)
    try:
        oid = effective_owner_id(current_user)
        conn = get_db_connection()
        cursor = conn.cursor()
        if room_name:
            cursor.execute(
                "DELETE FROM user_camera_assignments WHERE user_id = %s AND room_name = %s",
                (oid, room_name),
            )
            sess = active_monitoring_sessions.get(oid)
            if sess and room_name in sess:
                del sess[room_name]
            if sess is not None and len(sess) == 0:
                active_monitoring_sessions.pop(oid, None)
        else:
            cursor.execute("DELETE FROM user_camera_assignments WHERE user_id = %s", (oid,))
            active_monitoring_sessions.pop(oid, None)
        conn.commit()
        cursor.close()
        conn.close()
        try:
            await manager.broadcast_to_user(oid, {"type": "monitoring_assignments_updated"})
        except Exception:
            pass
        return {"success": True}
    except Exception as e:
        return {"success": False, "error": str(e)}


def _monitor_upload_user_id(
    current_user: Optional[dict], user_id: Optional[str]
) -> Optional[int]:
    final_user_id = None
    if current_user:
        final_user_id = effective_owner_id(current_user)
    if not final_user_id and user_id:
        try:
            sanitized_id = "".join(c for c in user_id if c.isdigit())
            if sanitized_id:
                final_user_id = int(sanitized_id)
        except (ValueError, TypeError):
            pass
    return final_user_id


def _resolve_preview_room_label(
    uid: int, room_name: Optional[str], camera_id: Optional[str]
) -> str:
    if room_name and room_name.strip():
        return room_name.split(",")[0].strip()
    sessions = active_monitoring_sessions.get(uid, {})
    if not sessions:
        return "Unknown"
    cid = str(camera_id) if camera_id is not None else None
    if cid:
        for room, assigned in sessions.items():
            if str(assigned) == cid:
                return room
    return next(iter(sessions.keys()))


# Lightweight JPEG uploads for mobile live preview only (no AI). Dashboard still uses /api/laptop-monitor for detection.
@app.post("/api/laptop-preview")
async def laptop_preview_only(
    file: UploadFile = File(...),
    user_id: Optional[str] = Query(None),
    room_name: Optional[str] = Query(None),
    camera_id: Optional[str] = Query(None),
    current_user: Optional[dict] = Depends(get_current_user_optional),
):
    final_user_id = _monitor_upload_user_id(current_user, user_id)
    if not final_user_id:
        return {"success": False, "error": "User ID not found"}
    try:
        contents = await file.read()
        if not contents or len(contents) < 80 or file.filename == "poll.txt":
            return {"success": True}
        preview_room = _resolve_preview_room_label(final_user_id, room_name, camera_id)
        asyncio.create_task(
            maybe_broadcast_remote_preview(
                final_user_id, preview_room, contents, preview_lane=True
            )
        )
        return {"success": True}
    except Exception as e:
        print(f"[laptop-preview] {e}")
        return {"success": False, "error": str(e)}


# Endpoint for laptop to send camera frames for monitoring
@app.post("/api/laptop-monitor")
async def laptop_monitor_api(
    file: UploadFile = File(...),
    user_id: Optional[str] = Query(None),
    room_name: Optional[str] = Query(None),
    camera_id: Optional[str] = Query(None),
    current_user: Optional[dict] = Depends(get_current_user_optional)
):
    final_user_id = _monitor_upload_user_id(current_user, user_id)

    if not final_user_id:
        return {"success": False, "error": "User ID not found"}

    try:
        contents = await file.read()
        
        if not contents or file.filename == 'poll.txt':
            # Check which camera this room is supposed to be using
            target_camera_id = None
            if final_user_id in active_monitoring_sessions and room_name:
                target_camera_id = active_monitoring_sessions[final_user_id].get(room_name)

            return {
                "success": True,
                "fire_detected": False,
                "active_rooms": list(active_monitoring_sessions.get(final_user_id, {}).keys()),
                "camera_id": target_camera_id,
                "timestamp": datetime.now().isoformat()
            }
        
        preview_room = _resolve_preview_room_label(final_user_id, room_name, camera_id)
        asyncio.create_task(
            maybe_broadcast_remote_preview(
                final_user_id, preview_room, contents, preview_lane=False
            )
        )

        # 1. RUN ALL ACTIVE MODELS IN PARALLEL FOR SPEED
        # We'll collect all results into a single dictionary
        all_results = {}
        
        # Optional detectors: silver / nanny / nurse / pet / home_alone via monitor_modes.
        # Fire, fridge, face always run. Window-open YOLO is disabled (never loaded).
        room_modes = _load_assignment_monitor_modes_set(final_user_id, preview_room)
        gating = get_mode_gating_config(room_modes)
        
        is_home_alone = gating["is_home_alone"]
        is_silver_mode = gating["is_silver_mode"]
        legacy_silver_monitor = user_has_legacy_silver_in_options(final_user_id)
        is_nanny_mode = gating["is_nanny_mode"]
        is_nurse_mode = gating["is_nurse_mode"]
        is_pet_mode = gating["is_pet_mode"]

        # Get services
        fire_service = get_fire_detection_service()
        exit_service = get_exit_detection_service()
        stillness_service = get_stillness_detection_service()
        fridge_service = get_fridge_detection_service()
        face_service = get_face_recognition_service()

        # Define which services to run based on modes
        services_to_run = {}
        for s_name in gating["parallel_services"]:
            if s_name == "fire": services_to_run["fire"] = fire_service
            elif s_name == "fridge": services_to_run["fridge"] = fridge_service
            elif s_name == "face": services_to_run["face"] = face_service
            elif s_name == "exit": services_to_run["exit"] = exit_service
            elif s_name == "stillness": services_to_run["stillness"] = stillness_service
            elif s_name == "pet": services_to_run["pet"] = get_pet_detection_service()


        # Use asyncio to run all detections concurrently
        async def run_detection(name, service):
            try:
                if name == "exit" or name == "exit_bg":
                    room_for_tracking = preview_room if preview_room else "Unknown"
                    return name, service.detect(contents, user_id=final_user_id, room_name=room_for_tracking if name == "exit" else "Background-Tracking")
                if name == "stillness" or name == "fridge":
                    room_for_tracking = preview_room if preview_room else "Unknown"
                    # Pass user_id and room_name to stillness/fridge service for state tracking
                    return name, service.detect(contents, user_id=final_user_id, room_name=room_for_tracking)
                if name == "pet":
                    # Pass cursor for DB access
                    conn = get_db_connection()
                    cursor = conn.cursor(cursor_factory=RealDictCursor)
                    result = service.detect(contents, user_id=final_user_id, cursor=cursor)
                    cursor.close()
                    conn.close()
                    return name, result
                if name == "face":
                    # Per-user isolation: face service uses known_faces/user_<id>/ ONLY for this account
                    return name, service.detect(contents, user_id=final_user_id)
                return name, service.detect(contents)
            except Exception as e:
                print(f"[ERROR] Detection {name} failed: {e}")
                return name, {"success": False, "event_detected": False}

        # Execute all detections in parallel
        detection_tasks = [run_detection(name, service) for name, service in services_to_run.items()]
        results_list = await asyncio.gather(*detection_tasks)
        all_results = dict(results_list)

        # 2. EXTRACT RESULTS
        fire_result = all_results.get("fire", {})
        fire_detected = fire_result.get("event_detected", False)
        
        # Door/window OPEN come from the Home-Alone-only bridge below (not parallel services).
        window_open_detected = False
        window_detections: list = []
        door_event_detected = False
        door_detections: list = []
        
        exit_result = all_results.get("exit", {})
        exit_detected = exit_result.get("event_detected", False)
        
        stillness_result = all_results.get("stillness", {})
        stillness_detected = stillness_result.get("event_detected", False)

        pet_result = all_results.get("pet", {})
        unknown_pet_detected = pet_result.get("event_detected", False)

        # Sharp objects now come from the Nanny-only bridge below (not the parallel services).
        sharp_object_detected = False
        sharp_info: dict = {}

        fridge_result = all_results.get("fridge", {})
        fridge_open_detected = fridge_result.get("event_detected", False)
        fridge_prolonged_open = fridge_result.get("is_prolonged_open", False)

        face_result = all_results.get("face", {})
        stranger_detected = face_result.get("event_detected", False)
        known_members_seen = face_result.get("known_members", [])
        has_faces = face_result.get("has_faces", False)

        legacy_silver_sel = legacy_silver_monitor
        legacy_nanny_sel = user_has_legacy_nanny_in_options(final_user_id)
        legacy_nurse_sel = user_has_legacy_nurse_in_options(final_user_id)
        # Choking runs ONLY when this room has Silver/Nanny/Nurse selected in Configure Room.
        # (Matches fall detection. Legacy account-option flags are NOT used to keep it active,
        # otherwise turning all room modes off would still trigger choking.)
        choking_pipeline_active = (
            is_silver_mode
            or is_nanny_mode
            or is_nurse_mode
        )
        # --- Choking (Silver / Nanny / Nurse): same Nanny Mode run.py via bridge ---
        choking_detected = False
        choking_info: dict = {}
        if (
            choking_bridge is not None
            and choking_pipeline_active
            and preview_room
            and preview_room.strip()
            and preview_room != "Unknown"
        ):
            try:
                choking_detected, choking_info = await asyncio.to_thread(
                    choking_bridge.process_upload_jpeg,
                    final_user_id,
                    preview_room.strip(),
                    contents,
                )
            except Exception as _chk_e:
                print(f"[CHOKING-BRIDGE] {_chk_e}")

        # --- Monitor-stream fall detection (Silver / Nanny / Nurse); same JPEGs as /api/laptop-monitor ---
        _monitor_fall_mode_parts: list[str] = []
        if is_silver_mode:
            _monitor_fall_mode_parts.append("Silver")
        if is_nanny_mode:
            _monitor_fall_mode_parts.append("Nanny")
        if is_nurse_mode:
            _monitor_fall_mode_parts.append("Nurse")
        monitor_fall_modes_label = ", ".join(_monitor_fall_mode_parts)

        silver_fall_detected = False
        silver_fall_info: dict = {}
        monitor_fall_stream_active = bool(
            is_silver_mode or is_nanny_mode or is_nurse_mode
        )
        if (
            silver_fall_bridge is not None
            and monitor_fall_stream_active
            and preview_room
            and preview_room.strip()
            and preview_room != "Unknown"
        ):
            try:
                silver_fall_detected, silver_fall_info = await asyncio.to_thread(
                    silver_fall_bridge.process_upload_jpeg,
                    final_user_id,
                    preview_room.strip(),
                    contents,
                )
            except Exception as _sfb_exc:
                print(f"[MONITOR-FALL-BRIDGE] bridge: {_sfb_exc}")

        # --- Food left out (always-on): runs for any mode or no mode, like fire ---
        food_detected = False
        food_info: dict = {}
        if (
            food_bridge is not None
            and preview_room
            and preview_room.strip()
            and preview_room != "Unknown"
        ):
            try:
                food_detected, food_info = await asyncio.to_thread(
                    food_bridge.process_upload_jpeg,
                    final_user_id,
                    preview_room.strip(),
                    contents,
                )
            except Exception as _food_exc:
                print(f"[FOOD-BRIDGE] bridge: {_food_exc}")

        # --- Pests (all modes): Insect/Lizard/Rodent via pests/pests/best.pt ---
        pest_detected = False
        pest_info: dict = {}
        if (
            gating.get("pests_active", True)
            and pests_bridge is not None
            and preview_room
            and preview_room.strip()
            and preview_room != "Unknown"
        ):
            try:
                pest_detected, pest_info = await asyncio.to_thread(
                    pests_bridge.process_upload_jpeg,
                    contents,
                )
            except Exception as _pest_exc:
                print(f"[PESTS-BRIDGE] bridge: {_pest_exc}")

        # --- Lost items (all modes): Charger/Keys/Wallet/sunglasses + room memory ---
        lost_item_sync_info: dict = {}
        if (
            gating.get("lost_items_active", True)
            and lost_item_service is not None
            and preview_room
            and preview_room.strip()
            and preview_room != "Unknown"
        ):
            try:
                lost_item_sync_info = await asyncio.to_thread(
                    lost_item_service.process_monitor_frame,
                    final_user_id,
                    preview_room.strip(),
                    contents,
                )
                if lost_item_sync_info.get("updated"):
                    await manager.broadcast_to_user(
                        final_user_id,
                        {"type": "lost_items_updated"},
                    )
            except Exception as _li_exc:
                print(f"[LOST-ITEM] bridge: {_li_exc}")

        # --- Hazard proximity (Nanny and/or Pet): yolov8n COCO hazards ---
        hazard_alerts: list = []
        if (
            hazard_area_bridge is not None
            and preview_room
            and preview_room.strip()
            and preview_room != "Unknown"
            and (is_nanny_mode or is_pet_mode)
        ):
            try:
                hazard_alerts = await asyncio.to_thread(
                    hazard_area_bridge.process_upload_jpeg,
                    final_user_id,
                    preview_room.strip(),
                    contents,
                    is_nanny_mode,
                    is_pet_mode,
                )
            except Exception as _hab_exc:
                print(f"[HAZARD-BRIDGE] bridge: {_hab_exc}")

        # --- Stuck in room (Nanny and/or Pet): stuck_in_a_room/app.py via bridge ---
        stuck_in_room_detected = False
        stuck_in_room_info: dict = {}
        if (
            stuck_in_a_room_bridge is not None
            and preview_room
            and preview_room.strip()
            and preview_room != "Unknown"
            and (is_nanny_mode or is_pet_mode)
        ):
            try:
                stuck_in_room_detected, stuck_in_room_info = await asyncio.to_thread(
                    stuck_in_a_room_bridge.process_upload_jpeg,
                    final_user_id,
                    preview_room.strip(),
                    contents,
                    is_nanny_mode,
                    is_pet_mode,
                )
            except Exception as _sir_exc:
                print(f"[STUCK-BRIDGE] bridge: {_sir_exc}")

        # --- Sleep monitor (Silver only): fell asleep / woke up ---
        sleep_events: list = []
        if (
            gating.get("sleep_monitor_active", False)
            and sleep_detection_bridge is not None
            and is_silver_mode
            and preview_room
            and preview_room.strip()
            and preview_room != "Unknown"
        ):
            try:
                sleep_events = await asyncio.to_thread(
                    sleep_detection_bridge.process_upload_jpeg,
                    final_user_id,
                    preview_room.strip(),
                    contents,
                )
            except Exception as _sdb_exc:
                print(f"[SLEEP-BRIDGE] bridge: {_sdb_exc}")

        # --- Bed exit (Nurse mode only): Bed_exit/main.py via bridge ---
        bed_exit_detected = False
        bed_exit_info: dict = {}
        if (
            bed_exit_bridge is not None
            and is_nurse_mode
            and preview_room
            and preview_room.strip()
            and preview_room != "Unknown"
        ):
            try:
                bed_exit_detected, bed_exit_info = await asyncio.to_thread(
                    bed_exit_bridge.process_upload_jpeg,
                    final_user_id,
                    preview_room.strip(),
                    contents,
                )
            except Exception as _be_exc:
                print(f"[BED-EXIT-BRIDGE] bridge: {_be_exc}")

        # --- Sharp objects: NANNY MODE ONLY (same best.pt as Sharp Objects/app.py) ---
        if (
            sharp_bridge is not None
            and is_nanny_mode
            and preview_room
            and preview_room.strip()
            and preview_room != "Unknown"
        ):
            try:
                sharp_object_detected, sharp_info = await asyncio.to_thread(
                    sharp_bridge.process_upload_jpeg,
                    contents,
                )
            except Exception as _sharp_exc:
                print(f"[SHARP-BRIDGE] bridge: {_sharp_exc}")

        # --- Door / Window OPEN: HOME ALONE MODE ONLY (Setting_model/best.pt) ---
        if (
            door_window_bridge_mod is not None
            and is_home_alone
            and preview_room
            and preview_room.strip()
            and preview_room != "Unknown"
        ):
            try:
                door_event_detected, window_open_detected, _dw_info = await asyncio.to_thread(
                    door_window_bridge_mod.process_upload_jpeg,
                    contents,
                )
                door_detections = _dw_info.get("door_detections", [])
                window_detections = _dw_info.get("window_detections", [])
            except Exception as _dw_exc:
                print(f"[DOORWIN-BRIDGE] bridge: {_dw_exc}")

        # Heartbeat so you can see choking gates + pose baseline state in the terminal
        global _choking_live_last_diag
        global _exit_live_last_diag
        _now_d = datetime.now()
        real_frame = bool(contents and len(contents) >= 200)

        if real_frame and (_now_d - _exit_live_last_diag).total_seconds() >= 20.0:
            _exit_live_last_diag = _now_d
            if "exit" in services_to_run:
                exm = exit_result.get("metadata") or {}
                gates_ok_room = (
                    preview_room is not None
                    and str(preview_room).strip()
                    and str(preview_room).strip() != "Unknown"
                )
                print(
                    "[EXIT-DIAG] "
                    f"uid={final_user_id} preview_room={preview_room!r} gates_ok_room={gates_ok_room} "
                    f"silver_assign={is_silver_mode} legacy_silver={legacy_silver_monitor} "
                    f"success={exit_result.get('success')} exit_edge_now={exit_detected} "
                    f"door_state={exm.get('door_state')!r} door_label={exm.get('door_label')!r} "
                    f"pipeline_err={exm.get('error')!r}"
                )
            elif is_silver_mode:
                print(
                    "[EXIT-DIAG] "
                    f"uid={final_user_id} preview_room={preview_room!r} WARNING: Silver ON "
                    f"but exit detector was NOT run (assignment bug); silver_assign={is_silver_mode}"
                )
        if real_frame and (_now_d - _choking_live_last_diag).total_seconds() >= 20.0:
            _choking_live_last_diag = _now_d
            gates_ok_room = (
                preview_room is not None
                and str(preview_room).strip()
                and str(preview_room).strip() != "Unknown"
            )
            ran = (
                choking_bridge is not None
                and choking_pipeline_active
                and gates_ok_room
            )
            print(
                "[CHOKING-DIAG] "
                f"uid={final_user_id} preview_room={preview_room!r} "
                f"silver_in_assignment={is_silver_mode} nanny_in_assignment={is_nanny_mode} "
                f"nurse_in_assignment={is_nurse_mode} "
                f"legacy_selected_silver={legacy_silver_sel} legacy_selected_nanny={legacy_nanny_sel} "
                f"legacy_selected_nurse={legacy_nurse_sel} "
                f"choking_pipeline_active={choking_pipeline_active} bridge_loaded={choking_bridge is not None} "
                f"ran_model={ran} alert={choking_detected} "
                f"pose={choking_info.get('pose_detected')} baseline_ready={choking_info.get('baseline_ready')} "
                f"score={choking_info.get('score')} window_ratio={choking_info.get('window_ratio')} "
                f"(throttled={bool(choking_info.get('skipped_throttle'))})"
            )
            if silver_fall_bridge is not None and monitor_fall_stream_active and gates_ok_room:
                print(
                    "[MONITOR-FALL-DIAG] "
                    f"uid={final_user_id} room={preview_room!r} modes={monitor_fall_modes_label!r} "
                    f"edge_now={silver_fall_detected} prob={silver_fall_info.get('probability')} "
                    f"buf_fill={silver_fall_info.get('buffer_fill')} "
                    f"person={silver_fall_info.get('person_visible')}"
                )
            if bed_exit_bridge is not None and is_nurse_mode and gates_ok_room:
                print(
                    "[BED-EXIT-DIAG] "
                    f"uid={final_user_id} room={preview_room!r} "
                    f"persons={bed_exit_info.get('persons')} "
                    f"bed_yolo={bed_exit_info.get('bed_yolo')} bed_inferred={bed_exit_info.get('bed_inferred')} "
                    f"pose={bed_exit_info.get('pose_ok')} state={bed_exit_info.get('state')} "
                    f"alert_type={bed_exit_info.get('alert_type')!r} alert_edge={bed_exit_detected} "
                    f"caregiver={bed_exit_info.get('caregiver')} "
                    f"torso_delta={bed_exit_info.get('torso_delta')} "
                    f"torso_thresh={bed_exit_info.get('torso_threshold')} "
                    f"torso_count={bed_exit_info.get('torso_count')} foot_count={bed_exit_info.get('foot_count')}"
                )

        if has_faces:
            print(f"[DEBUG MONITOR] Face(s) detected. Known: {known_members_seen}, Stranger: {stranger_detected}")

        # 3. CROSS-MODEL VALIDATION & FILTERING (Logic remains the same, just using pre-calculated results)
        if fire_detected:
            valid_fire = []
            for det in fire_result.get("detections", []):
                cls = det.get("class", "").lower()
                if "fire" in cls or "smoke" in cls:
                    bbox = det.get("bbox", {})
                    if (bbox.get("x2", 0) - bbox.get("x1", 0)) > 20: 
                        valid_fire.append(det)
            fire_detected = len(valid_fire) > 0

        # Door vs window are now separated natively by the door/window model, so the old
        # size/high-confidence window heuristics are no longer needed.

        # 4. PROCESS ALL ACTIVE ROOMS (Broadcasting)
        # ... (rest of the logic for saving and broadcasting events) ...

        # DEBUG LOGS
        if fire_detected: print(f"[DEBUG MONITOR] VALID Fire detected for user {final_user_id}")
        if sharp_object_detected: print(f"[DEBUG MONITOR] VALID Sharp object detected for user {final_user_id}")
        if window_open_detected: print(f"[DEBUG MONITOR] VALID Window open detected for user {final_user_id}")
        if exit_detected: print(f"[DEBUG MONITOR] VALID Exit detected for user {final_user_id}")
        if stillness_detected: print(f"[DEBUG MONITOR] VALID Stillness detected for user {final_user_id} ({stillness_result.get('elapsed_time')}s)")
        if bed_exit_detected: print(f"[DEBUG MONITOR] VALID Bed exit for user {final_user_id} ({bed_exit_info.get('alert_type')}) state={bed_exit_info.get('state')}")
        if door_event_detected: print(f"[DEBUG MONITOR] VALID Door open detected for user {final_user_id}")
        if unknown_pet_detected: print(f"[DEBUG MONITOR] VALID Unknown pet detected for user {final_user_id}")
        if pest_detected:
            labels = pest_info.get("labels") or []
            print(
                f"[DEBUG MONITOR] VALID Pest detected for user {final_user_id} "
                f"labels={labels!r} conf={pest_info.get('confidence')!r}"
            )
        if hazard_alerts:
            print(
                f"[DEBUG MONITOR] Hazard alerts for user {final_user_id} "
                f"room={preview_room} count={len(hazard_alerts)} "
                f"alerts={hazard_alerts!r}"
            )
        if stuck_in_room_detected:
            print(
                f"[DEBUG MONITOR] VALID Stuck in room for user {final_user_id} "
                f"room={preview_room} subject={stuck_in_room_info.get('subject_type')!r} "
                f"score={stuck_in_room_info.get('score')!r} info={stuck_in_room_info!r}"
            )
        if sleep_events:
            print(
                f"[DEBUG MONITOR] Sleep events for user {final_user_id} "
                f"room={preview_room} events={sleep_events!r}"
            )
        if choking_detected:
            print(
                f"[DEBUG MONITOR] Choking heuristic TRUE for user {final_user_id} "
                f"room={preview_room} info={choking_info!r}"
            )
        if silver_fall_detected:
            print(
                f"[DEBUG MONITOR] Monitor fall ALERT EDGE for user {final_user_id} "
                f"room={preview_room} modes=[{monitor_fall_modes_label}] "
                f"prob={silver_fall_info.get('probability')!r} "
                f"detail={silver_fall_info!r}"
            )
        if fridge_open_detected: print(f"[DEBUG MONITOR] VALID Fridge open detected for user {final_user_id}")
        if fridge_prolonged_open: print(f"[DEBUG MONITOR] VALID Fridge LEFT OPEN for user {final_user_id} ({fridge_result.get('elapsed_time')}s)")
        if stranger_detected: print(f"[DEBUG MONITOR] VALID Unknown person detected for user {final_user_id}")
        if known_members_seen: print(f"[DEBUG MONITOR] Known members seen for user {final_user_id}: {known_members_seen}")

        # 4. UPDATE FAMILY HOME STATUS & FACE SMOOTHING
        if final_user_id not in family_home_status:
            family_home_status[final_user_id] = {}
        if final_user_id not in stranger_frame_counts:
            stranger_frame_counts[final_user_id] = {}
        if final_user_id not in room_last_known_seen:
            room_last_known_seen[final_user_id] = {}
        if final_user_id not in known_member_frame_counts:
            known_member_frame_counts[final_user_id] = {}
            
        current_room = room_name if room_name else "Unknown"
        now = datetime.now()

        if current_room not in known_member_frame_counts[final_user_id]:
            known_member_frame_counts[final_user_id][current_room] = {}

        # --- FACE RECOGNITION SMOOTHING LOGIC ---

        # STEP 1: KNOWN-MEMBER CONSENSUS
        # Require N consecutive frames of "Known: X" before treating that member as confirmed.
        # This prevents a single accidental match from locking an unknown person as a family member.
        confirmed_known_members: list[str] = []
        room_known_counts = known_member_frame_counts[final_user_id][current_room]

        if known_members_seen:
            # Bump the streak for every member seen this frame
            for name in known_members_seen:
                room_known_counts[name] = room_known_counts.get(name, 0) + 1
                if room_known_counts[name] >= KNOWN_MEMBER_CONSENSUS_THRESHOLD:
                    confirmed_known_members.append(name)
                else:
                    print(f"[DEBUG MONITOR] Known match for {name}, waiting for consensus ({room_known_counts[name]}/{KNOWN_MEMBER_CONSENSUS_THRESHOLD})")
            # Reset streaks for members NOT seen this frame
            for name in list(room_known_counts.keys()):
                if name not in known_members_seen:
                    room_known_counts[name] = 0
        else:
            # No known matches this frame — reset all known streaks for this room
            for name in list(room_known_counts.keys()):
                room_known_counts[name] = 0

        # STEP 2: UPDATE "AT HOME" STATUS & ROOM MEMORY
        # Only confirmed known members count toward home status / stickiness anchor.
        for name in confirmed_known_members:
            family_home_status[final_user_id][name] = {
                "last_seen": now,
                "status": "At Home"
            }
            room_last_known_seen[final_user_id][current_room] = now

        # Clean up old statuses (mark as Away after timeout)
        for name, data in list(family_home_status[final_user_id].items()):
            if (now - data["last_seen"]).total_seconds() > HOME_TIMEOUT_MINUTES * 60:
                family_home_status[final_user_id][name]["status"] = "Away"

        # Push at-home updates to mobile WebSocket clients (throttled; no HTTP poll required)
        try:
            last_push = presence_ws_last_sent.get(final_user_id)
            if last_push is None or (now - last_push).total_seconds() >= PRESENCE_WS_MIN_INTERVAL_SEC:
                presence_ws_last_sent[final_user_id] = now
                await manager.broadcast_to_user(final_user_id, {
                    "type": "home_presence_updated",
                    "timestamp": now.isoformat(),
                })
        except Exception as _presence_err:
            print(f"[PRESENCE WS] broadcast failed: {_presence_err}")

        # STEP 3: KNOWN MEMBER OVERRIDE (Instant Silence)
        # If a confirmed known member is in view, suppress stranger alerts entirely.
        if confirmed_known_members:
            stranger_detected = False
            stranger_frame_counts[final_user_id][current_room] = 0

        # STEP 4: IDENTITY STICKINESS
        # For 15 seconds after a confirmed known member was seen in this room,
        # treat any "Unknown" frames as ambiguous (still the known person at a bad angle).
        last_member_time = room_last_known_seen[final_user_id].get(current_room)
        if last_member_time and (now - last_member_time).total_seconds() < KNOWN_MEMBER_STICKINESS_SECONDS:
            if stranger_detected:
                elapsed = (now - last_member_time).total_seconds()
                print(f"[DEBUG MONITOR] Ambiguous frame silenced (within {KNOWN_MEMBER_STICKINESS_SECONDS}s stickiness window, {elapsed:.1f}s since known seen)")
            stranger_detected = False
            stranger_frame_counts[final_user_id][current_room] = 0

        # STEP 5: STRANGER CONSENSUS (Wait for N frames of Unknown before alerting)
        if stranger_detected:
            stranger_frame_counts[final_user_id][current_room] = stranger_frame_counts[final_user_id].get(current_room, 0) + 1
            if stranger_frame_counts[final_user_id][current_room] < STRANGER_ALERT_THRESHOLD:
                print(f"[DEBUG MONITOR] Stranger detected, waiting for consensus ({stranger_frame_counts[final_user_id][current_room]}/{STRANGER_ALERT_THRESHOLD})")
        else:
            stranger_frame_counts[final_user_id][current_room] = 0

        # Final decision: Is this a valid stranger alert?
        is_stranger_valid = stranger_frame_counts[final_user_id].get(current_room, 0) >= STRANGER_ALERT_THRESHOLD
        if is_stranger_valid:
            print(f"[DEBUG MONITOR] VALID Stranger detected (Consensus) for user {final_user_id} in {current_room}")

        # 3.5 MULTI-FRAME VALIDATION for Sharp Objects
        if final_user_id not in sharp_object_frames:
            sharp_object_frames[final_user_id] = {}
        
        current_room = room_name if room_name else "Unknown"
        if sharp_object_detected:
            sharp_object_frames[final_user_id][current_room] = sharp_object_frames[final_user_id].get(current_room, 0) + 1
        else:
            sharp_object_frames[final_user_id][current_room] = 0
            
        # One confident frame (>=0.75) is enough for a fast alert. Hard re-gate on Nanny mode so a
        # stale counter can never fire an alert the moment Nanny mode is turned off / another mode
        # (or no mode) is selected.
        is_sharp_valid = (
            is_nanny_mode
            and sharp_object_frames[final_user_id].get(current_room, 0) >= SHARP_OBJECT_THRESHOLD
        )
        
        if is_sharp_valid:
            print(f"[DEBUG MONITOR] VALID Sharp object detected (Multi-frame) for user {final_user_id} in {current_room}")

        # 4. CHECK COOLDOWN
        now = datetime.now()
        preview_room_key = (
            preview_room.strip()
            if preview_room and preview_room != "Unknown"
            else ""
        )
        broadcast_choking = False
        if choking_detected and preview_room_key:
            ck_key = (final_user_id, preview_room_key)
            lc = last_choking_alert_ts.get(ck_key)
            if (
                lc is None
                or (now - lc).total_seconds() >= CHOKING_ALERT_MIN_INTERVAL_SEC
            ):
                broadcast_choking = True

        broadcast_silver_fall = False
        if silver_fall_detected and preview_room_key:
            sf_k = (final_user_id, preview_room_key)
            lsff = last_silver_fall_alert_ts.get(sf_k)
            if (
                lsff is None
                or (now - lsff).total_seconds() >= SILVER_FALL_ALERT_MIN_INTERVAL_SEC
            ):
                broadcast_silver_fall = True

        broadcast_food = False
        if food_detected and preview_room_key:
            food_k = (final_user_id, preview_room_key)
            lf = last_food_alert_ts.get(food_k)
            if (
                lf is None
                or (now - lf).total_seconds() >= FOOD_ALERT_MIN_INTERVAL_SEC
            ):
                broadcast_food = True

        broadcast_pest = False
        if pest_detected and preview_room_key:
            pest_k = (final_user_id, preview_room_key)
            lp = last_pest_alert_ts.get(pest_k)
            if (
                lp is None
                or (now - lp).total_seconds() >= PEST_ALERT_MIN_INTERVAL_SEC
            ):
                broadcast_pest = True

        broadcast_bed_exit = False
        if bed_exit_detected and preview_room_key:
            be_k = (final_user_id, preview_room_key)
            lbe = last_bed_exit_alert_ts.get(be_k)
            if (
                lbe is None
                or (now - lbe).total_seconds() >= BED_EXIT_ALERT_MIN_INTERVAL_SEC
            ):
                broadcast_bed_exit = True

        broadcast_stuck_in_room = False
        if stuck_in_room_detected and preview_room_key:
            sir_k = (final_user_id, preview_room_key)
            lsir = last_stuck_in_room_alert_ts.get(sir_k)
            if (
                lsir is None
                or (now - lsir).total_seconds() >= STUCK_IN_ROOM_ALERT_MIN_INTERVAL_SEC
            ):
                broadcast_stuck_in_room = True

        bed_exit_event_id_for_response = None
        bed_exit_clip_trim_for_response = None
        if (
            bed_exit_info.get("arm_recording")
            and preview_room_key
            and is_nurse_mode
        ):
            arm_k = (final_user_id, preview_room_key)
            if arm_k not in bed_exit_recording_armed:
                bed_exit_recording_armed[arm_k] = now
                await manager.broadcast_to_user(
                    final_user_id,
                    {
                        "type": "bed_exit_arm_recording",
                        "room_name": preview_room_key,
                    },
                )
                print(
                    f"[BED-EXIT-BRIDGE] arm recording user={final_user_id} "
                    f"room={preview_room_key!r}"
                )

        on_cooldown = False
        if final_user_id in event_cooldowns:
            time_since_last = (now - event_cooldowns[final_user_id]).total_seconds()
            if time_since_last < COOLDOWN_SECONDS:
                on_cooldown = True

        # 4. PROCESS ALL ACTIVE ROOMS
        # If room_name is provided in query, use it. Otherwise use all active sessions.
        rooms_to_process = []
        if room_name:
            rooms_to_process = [r.strip() for r in room_name.split(',')]
        else:
            rooms_to_process = list(active_monitoring_sessions.get(final_user_id, {}).keys())

        # Check if this specific camera is assigned to any of these rooms
        # If camera_id is provided, we only broadcast if it matches the room's assigned camera
        
        # Now broadcast alerts for each room if detected
        event_id = None
        for room in rooms_to_process:
            # Multi-camera check: if this room has an assigned camera, only process if it matches
            assigned_camera = active_monitoring_sessions.get(final_user_id, {}).get(room)
            if assigned_camera and camera_id and assigned_camera != camera_id:
                continue

            # Choking: bypasses global 10s event_cooldown (still gated by CHOKING_ALERT_MIN_INTERVAL_SEC)
            if broadcast_choking and room == preview_room_key:
                wr = choking_info.get("window_ratio") if choking_info else None
                desc = (
                    f"A possible choking pattern was detected in {room} "
                    "(Silver, Nanny, or Nurse monitoring)."
                    + (f" Heuristic window≈{wr:.0%}." if isinstance(wr, (int, float)) else "")
                )
                new_event = await save_and_broadcast_event(
                    user_id=final_user_id,
                    title="Possible choking detected",
                    description=desc,
                    event_type="emergency",
                    room_name=room,
                )
                if new_event:
                    eid = new_event["id"]
                    last_choking_alert_ts[
                        (final_user_id, preview_room_key)
                    ] = now
                    await manager.broadcast_to_user(
                        final_user_id,
                        {
                            "type": "choking_alert",
                            "choking_detected": True,
                            "room_name": room,
                            "event_id": eid,
                            "start_recording": True,
                            "window_ratio": wr,
                        },
                    )
                    asyncio.create_task(record_event_clip(final_user_id, eid, contents))

            if broadcast_silver_fall and room == preview_room_key:
                prob_raw = silver_fall_info.get("probability")
                prob_num: Optional[float] = (
                    float(prob_raw)
                    if isinstance(prob_raw, (int, float))
                    else None
                )
                new_sf = await silver_fall_dispatch(
                    final_user_id,
                    room,
                    prob_num,
                    f"laptop-monitor stream FALL prob={prob_raw!s}",
                    contents if isinstance(contents, (bytes, bytearray)) else None,
                    monitor_fall_modes_label or "Silver, Nanny, or Nurse",
                )
                if new_sf:
                    last_silver_fall_alert_ts[
                        (final_user_id, preview_room_key)
                    ] = now

            # Food left out: bypasses global event_cooldown (gated by FOOD_ALERT_MIN_INTERVAL_SEC)
            if broadcast_food and room == preview_room_key:
                secs = food_info.get("elapsed_seconds") if food_info else None
                desc = (
                    f"Food has been left out in {room}"
                    + (f" for ~{int(secs)}s." if isinstance(secs, (int, float)) else ".")
                )
                new_event = await save_and_broadcast_event(
                    user_id=final_user_id,
                    title="Food Left Out!",
                    description=desc,
                    event_type="warning",
                    room_name=room,
                )
                if new_event:
                    eid = new_event["id"]
                    last_food_alert_ts[(final_user_id, preview_room_key)] = now
                    await manager.broadcast_to_user(
                        final_user_id,
                        {
                            "type": "food_alert",
                            "food_detected": True,
                            "room_name": room,
                            "event_id": eid,
                            "start_recording": True,
                            "elapsed_seconds": secs,
                        },
                    )
                    asyncio.create_task(record_event_clip(final_user_id, eid, contents))

            if broadcast_pest and room == preview_room_key:
                labels = pest_info.get("labels") or []
                label_str = ", ".join(str(x) for x in labels) if labels else "pest"
                conf = pest_info.get("confidence")
                desc = (
                    f"{label_str} detected in {room}"
                    + (f" (confidence {conf:.0%})." if isinstance(conf, (int, float)) else ".")
                )
                new_event = await save_and_broadcast_event(
                    user_id=final_user_id,
                    title="Pest detected",
                    description=desc,
                    event_type="warning",
                    room_name=room,
                )
                if new_event:
                    eid = new_event["id"]
                    last_pest_alert_ts[(final_user_id, preview_room_key)] = now
                    await manager.broadcast_to_user(
                        final_user_id,
                        {
                            "type": "pest_alert",
                            "pest_detected": True,
                            "room_name": room,
                            "event_id": eid,
                            "start_recording": True,
                            "labels": labels,
                            "confidence": conf,
                        },
                    )
                    asyncio.create_task(record_event_clip(final_user_id, eid, contents))

            if hazard_alerts and room == preview_room_key:
                for ha in hazard_alerts:
                    subject = str(ha.get("subject") or "subject")
                    label = str(ha.get("label") or "hazard")
                    status = str(ha.get("status") or "APPROACHING")
                    severity = str(ha.get("severity") or "MEDIUM")
                    hmode = str(ha.get("mode") or "monitoring")
                    title = f"Hazard: {severity} — {label}"
                    desc = (
                        f"{subject.title()} {status.lower()} '{label}' in {room} "
                        f"({hmode} mode)."
                    )
                    evt_type = "emergency" if severity == "CRITICAL" else "warning"
                    new_event = await save_and_broadcast_event(
                        user_id=final_user_id,
                        title=title,
                        description=desc,
                        event_type=evt_type,
                        room_name=room,
                    )
                    if new_event:
                        eid = new_event["id"]
                        await manager.broadcast_to_user(
                            final_user_id,
                            {
                                "type": "hazard_alert",
                                "hazard_detected": True,
                                "room_name": room,
                                "event_id": eid,
                                "start_recording": True,
                                "subject": subject,
                                "label": label,
                                "status": status,
                                "severity": severity,
                                "mode": hmode,
                                "zone_type": ha.get("zone_type"),
                            },
                        )
                        asyncio.create_task(
                            record_event_clip(final_user_id, eid, contents)
                        )

            if broadcast_stuck_in_room and room == preview_room_key:
                subject = str(stuck_in_room_info.get("subject_type") or "subject")
                title = str(
                    stuck_in_room_info.get("title")
                    or f"{subject.title()} may be stuck in room"
                )
                desc = str(
                    stuck_in_room_info.get("message")
                    or f"{subject.title()} may be stuck in {room}."
                )
                score = stuck_in_room_info.get("score")
                if isinstance(score, (int, float)):
                    desc = f"{desc} (score {int(score)}/3)."
                mode_label = "Pet" if subject in ("cat", "dog") else "Nanny"
                new_event = await save_and_broadcast_event(
                    user_id=final_user_id,
                    title=title,
                    description=f"{desc} ({mode_label} mode, {room}).",
                    event_type="emergency",
                    room_name=room,
                )
                if new_event:
                    eid = new_event["id"]
                    last_stuck_in_room_alert_ts[(final_user_id, preview_room_key)] = now
                    await manager.broadcast_to_user(
                        final_user_id,
                        {
                            "type": "stuck_in_room_alert",
                            "stuck_in_room_detected": True,
                            "subject_type": subject,
                            "title": title,
                            "message": desc,
                            "room_name": room,
                            "event_id": eid,
                            "start_recording": True,
                            "score": score,
                            "signals": stuck_in_room_info.get("signals"),
                            "door_state": stuck_in_room_info.get("door_state"),
                        },
                    )
                    asyncio.create_task(record_event_clip(final_user_id, eid, contents))
                    print(
                        f"[STUCK-BRIDGE] alert user={final_user_id} room={room!r} "
                        f"subject={subject} evt={eid}"
                    )

            if sleep_events and room == preview_room_key:
                for se in sleep_events:
                    kind = str(se.get("event") or "")
                    if kind == "fell_asleep":
                        title = "Fell asleep"
                        desc = f"Person fell asleep in {room} (Silver sleep monitor)."
                        ws_type = "sleep_fell_asleep"
                    elif kind == "woke_up":
                        dur = se.get("duration_label") or ""
                        reason = str(se.get("reason") or "woke up")
                        title = "Woke up"
                        desc = (
                            f"Person woke up in {room}"
                            + (f" (slept {dur})" if dur else "")
                            + f" — {reason}."
                        )
                        ws_type = "sleep_woke_up"
                    else:
                        continue
                    new_event = await save_and_broadcast_event(
                        user_id=final_user_id,
                        title=title,
                        description=desc,
                        event_type="safety",
                        room_name=room,
                    )
                    if new_event:
                        eid = new_event["id"]
                        await manager.broadcast_to_user(
                            final_user_id,
                            {
                                "type": ws_type,
                                "sleep_event": kind,
                                "room_name": room,
                                "event_id": eid,
                                "start_recording": True,
                                "reason": se.get("reason"),
                                "duration_sec": se.get("duration_sec"),
                                "duration_label": se.get("duration_label"),
                            },
                        )
                        asyncio.create_task(
                            record_event_clip(final_user_id, eid, contents)
                        )

            if broadcast_bed_exit and room == preview_room_key:
                atype = str(bed_exit_info.get("alert_type") or "early_warning")
                msg = str(bed_exit_info.get("message") or "Bed exit detected.")
                state = bed_exit_info.get("state", 0)
                is_critical = atype == "critical"
                title = (
                    "CRITICAL: Patient exited bed!"
                    if is_critical
                    else "Bed exit warning"
                )
                desc = f"{msg} (Nurse mode, {room}, state={state})."
                new_event = await save_and_broadcast_event(
                    user_id=final_user_id,
                    title=title,
                    description=desc,
                    event_type="emergency" if is_critical else "safety",
                    room_name=room,
                )
                if new_event:
                    eid = new_event["id"]
                    bed_exit_event_id_for_response = eid
                    last_bed_exit_alert_ts[(final_user_id, preview_room_key)] = now
                    armed_sec = bed_exit_info.get("recording_armed_sec")
                    trim_hint = None
                    if isinstance(armed_sec, (int, float)) and armed_sec > 0:
                        trim_hint = min(max(float(armed_sec) * 0.45, 0.8), 2.5)
                    bed_exit_clip_trim_for_response = trim_hint
                    bed_exit_recording_armed.pop(
                        (final_user_id, preview_room_key), None
                    )
                    await manager.broadcast_to_user(
                        final_user_id,
                        {
                            "type": "bed_exit_alert",
                            "bed_exit_detected": True,
                            "alert_type": atype,
                            "state": state,
                            "message": msg,
                            "room_name": room,
                            "event_id": eid,
                            "finalize_bed_exit_recording": True,
                            "clip_trim_start_sec": trim_hint,
                            "start_recording": False,
                        },
                    )
                    asyncio.create_task(record_event_clip(final_user_id, eid, contents))
                    print(
                        f"[BED-EXIT-BRIDGE] alert user={final_user_id} room={room!r} "
                        f"type={atype} evt={eid} trim={trim_hint}"
                    )

            if not on_cooldown:
                # Fire Alert
                if fire_detected:
                    event_cooldowns[final_user_id] = now
                    new_event = await save_and_broadcast_event(
                        user_id=final_user_id,
                        title="Fire Detected!",
                        description=f"Fire detected in {room}.",
                        event_type="emergency",
                        room_name=room
                    )
                    if new_event:
                        event_id = new_event['id']
                        await manager.broadcast_to_user(final_user_id, {
                            "type": "fire_alert",
                            "fire_detected": True,
                            "confidence": fire_result.get("confidence", 0.0),
                            "room_name": room,
                            "event_id": event_id,
                            "start_recording": True
                        })
                        asyncio.create_task(record_event_clip(final_user_id, event_id, contents))
                
                # Sharp Object Alert
                elif is_sharp_valid:
                    event_cooldowns[final_user_id] = now
                    new_event = await save_and_broadcast_event(
                        user_id=final_user_id,
                        title="Sharp Object!",
                        description=f"A dangerous sharp object was detected in {room}.",
                        event_type="emergency",
                        room_name=room
                    )
                    if new_event:
                        event_id = new_event['id']
                        await manager.broadcast_to_user(final_user_id, {
                            "type": "sharp_object_alert",
                            "sharp_object_detected": True,
                            "confidence": sharp_info.get("confidence", 0.0),
                            "room_name": room,
                            "event_id": event_id,
                            "start_recording": True
                        })
                        asyncio.create_task(record_event_clip(final_user_id, event_id, contents))
                
                # Window Alert
                elif window_open_detected:
                    event_cooldowns[final_user_id] = now
                    new_event = await save_and_broadcast_event(
                        user_id=final_user_id,
                        title="Window Open!",
                        description=f"Window detected as OPEN in {room}.",
                        event_type="security",
                        room_name=room
                    )
                    if new_event:
                        event_id = new_event['id']
                        await manager.broadcast_to_user(final_user_id, {
                            "type": "window_alert",
                            "window_open_detected": True,
                            "detections": window_detections,
                            "room_name": room,
                            "event_id": event_id,
                            "start_recording": True
                        })
                        asyncio.create_task(record_event_clip(final_user_id, event_id, contents))
                
                # Exit Alert (Silver Mode)
                elif exit_detected:
                    event_cooldowns[final_user_id] = now
                    new_event = await save_and_broadcast_event(
                        user_id=final_user_id,
                        title="Room Exit!",
                        description=f"A person was detected exiting {room} in Silver Mode.",
                        event_type="security",
                        room_name=room
                    )
                    if new_event:
                        event_id = new_event['id']
                        await manager.broadcast_to_user(final_user_id, {
                            "type": "exit_alert",
                            "exit_detected": True,
                            "room_name": room,
                            "event_id": event_id,
                            "start_recording": True
                        })
                        asyncio.create_task(record_event_clip(final_user_id, event_id, contents))

                # Stillness Alert (Silver / Nanny / Nurse)
                elif stillness_detected:
                    event_cooldowns[final_user_id] = now
                    _still_labels = []
                    if is_silver_mode:
                        _still_labels.append("Silver")
                    if is_nanny_mode:
                        _still_labels.append("Nanny")
                    if is_nurse_mode:
                        _still_labels.append("Nurse")
                    _still_mode_txt = ", ".join(_still_labels) if _still_labels else "Monitoring"
                    new_event = await save_and_broadcast_event(
                        user_id=final_user_id,
                        title="Prolonged Stillness!",
                        description=(
                            f"A person has been still for {stillness_result.get('elapsed_time', 0)}s "
                            f"in {room} ({_still_mode_txt} monitoring)."
                        ),
                        event_type="safety",
                        room_name=room
                    )
                    if new_event:
                        event_id = new_event['id']
                        await manager.broadcast_to_user(final_user_id, {
                            "type": "stillness_alert",
                            "stillness_detected": True,
                            "elapsed_time": stillness_result.get('elapsed_time', 0),
                            "room_name": room,
                            "event_id": event_id,
                            "start_recording": True
                        })
                        asyncio.create_task(record_event_clip(final_user_id, event_id, contents))

                # Door Alert
                elif door_event_detected:
                    event_cooldowns[final_user_id] = now
                    new_event = await save_and_broadcast_event(
                        user_id=final_user_id,
                        title="Door Opened!",
                        description=f"A door was detected OPEN in {room}.",
                        event_type="security",
                        room_name=room
                    )
                    if new_event:
                        event_id = new_event['id']
                        await manager.broadcast_to_user(final_user_id, {
                            "type": "door_alert",
                            "event_detected": True,
                            "detections": door_detections,
                            "room_name": room,
                            "event_id": event_id,
                            "start_recording": True
                        })
                        asyncio.create_task(record_event_clip(final_user_id, event_id, contents))

                # Pet Alert (Pet Mode)
                elif unknown_pet_detected:
                    event_cooldowns[final_user_id] = now
                    new_event = await save_and_broadcast_event(
                        user_id=final_user_id,
                        title="Unknown Pet Detected!",
                        description=f"An unrecognized animal was detected in {room}.",
                        event_type="security",
                        room_name=room
                    )
                    if new_event:
                        event_id = new_event['id']
                        await manager.broadcast_to_user(final_user_id, {
                            "type": "pet_alert",
                            "unknown_pet_detected": True,
                            "detections": pet_result.get("detections", []),
                            "room_name": room,
                            "event_id": event_id,
                            "start_recording": True
                        })
                        asyncio.create_task(record_event_clip(final_user_id, event_id, contents))

                # Fridge Alert
                elif fridge_prolonged_open:
                    event_cooldowns[final_user_id] = now
                    new_event = await save_and_broadcast_event(
                        user_id=final_user_id,
                        title="Fridge Left Open!",
                        description=f"The fridge in {room} has been left open for {fridge_result.get('elapsed_time')} seconds.",
                        event_type="security",
                        room_name=room
                    )
                    if new_event:
                        event_id = new_event['id']
                        await manager.broadcast_to_user(final_user_id, {
                            "type": "fridge_alert",
                            "fridge_open_detected": True,
                            "elapsed_time": fridge_result.get('elapsed_time', 0),
                            "room_name": room,
                            "event_id": event_id,
                            "start_recording": True
                        })
                        asyncio.create_task(record_event_clip(final_user_id, event_id, contents))

                # Unknown Person Alert
                elif is_stranger_valid:
                    event_cooldowns[final_user_id] = now
                    new_event = await save_and_broadcast_event(
                        user_id=final_user_id,
                        title="Unknown Person Detected!",
                        description=f"An unknown person was seen in {room}.",
                        event_type="emergency",
                        room_name=room
                    )
                    if new_event:
                        event_id = new_event['id']
                        await manager.broadcast_to_user(final_user_id, {
                            "type": "stranger_alert",
                            "stranger_detected": True,
                            "room_name": room,
                            "event_id": event_id,
                            "start_recording": True
                        })
                        asyncio.create_task(record_event_clip(final_user_id, event_id, contents))

        active_room_display = room_name
        sess = active_monitoring_sessions.get(final_user_id) or {}
        if not active_room_display and sess:
            active_room_display = _resolve_preview_room_label(
                final_user_id, None, camera_id
            )

        return {
            "success": True,
            "fire_detected": fire_detected,
            "sharp_object_detected": sharp_object_detected,
            "window_open_detected": window_open_detected,
            "exit_detected": exit_detected,
            "stillness_detected": stillness_detected,
            "choking_detected": choking_detected,
            "pest_detected": pest_detected,
            "lost_items_detected": lost_item_sync_info.get("count", 0),
            "hazard_alerts_fired": len(hazard_alerts),
            "stuck_in_room_detected": stuck_in_room_detected,
            "sleep_events_fired": len(sleep_events),
            "bed_exit_detected": bed_exit_detected,
            "bed_exit_arm_recording": bool(bed_exit_info.get("arm_recording")),
            "bed_exit_event_id": bed_exit_event_id_for_response,
            "bed_exit_finalize_recording": bed_exit_detected,
            "clip_trim_start_sec": bed_exit_clip_trim_for_response,
            # Fall classifier on JPEG stream — active for Silver/Nanny/Nurse assignments
            "fall_detection_edge": silver_fall_detected,
            "silver_fall_edge": silver_fall_detected,
            "door_event_detected": door_event_detected,
            "unknown_pet_detected": unknown_pet_detected,
            "fridge_open_detected": fridge_open_detected,
            "stranger_detected": is_stranger_valid,
            "is_home_alone_active": is_home_alone,
            "is_nurse_mode_active": is_nurse_mode,
            "is_pet_mode_active": is_pet_mode,
            "is_pests_active": gating.get("pests_active", True),
            "timestamp": datetime.now().isoformat(),
            "active_rooms": list(sess.keys()),
            "active_room": active_room_display,
            "camera_id": (sess.get(active_room_display) if active_room_display else None),
        }
    except Exception as e:
        print(f"[ERROR MONITOR] {e}")
        return {"success": False, "error": str(e)}

@app.post("/api/monitoring/session")
async def set_monitoring_session(
    user_id: int = Form(...), 
    room_name: Optional[str] = Form(None), 
    camera_id: Optional[str] = Form(None),
    action: str = Form("add")
):
    if user_id not in active_monitoring_sessions:
        active_monitoring_sessions[user_id] = {}
    
    if room_name:
        if action == "add":
            active_monitoring_sessions[user_id][room_name] = camera_id or "0"
        else:
            active_monitoring_sessions[user_id].pop(room_name, None)
    
    # Clean up empty dicts
    if not active_monitoring_sessions[user_id]:
        active_monitoring_sessions.pop(user_id, None)
        
    return {"success": True, "active_rooms": list(active_monitoring_sessions.get(user_id, {}).keys())}

@app.get("/laptop-monitor", response_class=HTMLResponse)
async def laptop_monitor_page():
    html_content = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>HomeGuardian - Laptop Camera Monitor</title>
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                background: #121212;
                color: white;
                min-height: 100vh;
                display: flex;
                justify-content: center;
                align-items: center;
                padding: 20px;
            }
            .container {
                background: #1e1e1e;
                border-radius: 24px;
                padding: 40px;
                box-shadow: 0 20px 50px rgba(0,0,0,0.5);
                max-width: 900px;
                width: 100%;
                text-align: center;
            }
            h1 { margin-bottom: 24px; font-weight: 300; letter-spacing: 1px; }
            h1 span { font-weight: 700; color: #4CAF50; }
            
            .video-container {
                position: relative;
                width: 100%;
                background: #000;
                border-radius: 16px;
                overflow: hidden;
                margin-bottom: 24px;
                aspect-ratio: 4/3;
                border: 2px solid #333;
            }
            video { width: 100%; height: 100%; object-fit: cover; }
            
            .status-overlay {
                position: absolute;
                top: 20px;
                left: 20px;
                padding: 8px 16px;
                border-radius: 20px;
                font-size: 14px;
                font-weight: 600;
                text-transform: uppercase;
                background: rgba(0,0,0,0.6);
            }
            
            .status {
                width: 100%;
                padding: 16px;
                border-radius: 12px;
                margin-bottom: 24px;
                font-weight: 600;
                font-size: 18px;
            }
            .status.connecting { background: #333; color: #999; }
            .status.connected { background: #1b5e20; color: #81c784; }
            .status.disconnected { background: #b71c1c; color: #e57373; }
            .status.fire-detected { background: #d32f2f; color: white; animation: blink 1s infinite; }
            .status.door-detected { background: #f57c00; color: white; animation: blink 1s infinite; }
            
            @keyframes blink { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
            
            .info-grid {
                display: grid;
                grid-template-columns: repeat(3, 1fr);
                gap: 16px;
                margin-bottom: 24px;
            }
            .info-card {
                background: #252525;
                padding: 16px;
                border-radius: 12px;
                text-align: center;
            }
            .info-card .label { color: #888; font-size: 12px; text-transform: uppercase; margin-bottom: 8px; }
            .info-card .value { font-size: 20px; font-weight: 600; }
            
            .user-setup {
                background: #252525;
                padding: 24px;
                border-radius: 16px;
                margin-bottom: 24px;
            }
            input {
                background: #333;
                border: 1px solid #444;
                color: white;
                padding: 12px 20px;
                border-radius: 8px;
                font-size: 16px;
                width: 200px;
                margin-right: 12px;
            }
            button {
                background: #4CAF50;
                color: white;
                border: none;
                padding: 12px 24px;
                border-radius: 8px;
                font-size: 16px;
                font-weight: 600;
                cursor: pointer;
                transition: 0.2s;
            }
            button:hover { background: #45a049; }
            
            .alert-box {
                background: #ff5252;
                color: white;
                padding: 20px;
                border-radius: 12px;
                margin-top: 24px;
                display: none;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>Home<span>Guardian</span> Monitor</h1>
            
            <div id="setupDiv" class="user-setup">
                <p style="margin-bottom: 15px; color: #aaa;">Enter your User ID to start monitoring</p>
                <input type="number" id="userIdInput" placeholder="User ID">
                <button onclick="setUserId()">Connect</button>
            </div>

            <div id="status" class="status connecting">Connecting...</div>
            
            <div class="video-container">
                <video id="video" autoplay playsinline muted></video>
                <div id="roomBadge" class="status-overlay" style="display:none; border: 1px solid #4CAF50; color: #4CAF50;">
                    LIVE: <span id="roomName">None</span>
                </div>
            </div>
            
            <div class="info-grid">
                <div class="info-card">
                    <div class="label">Frames Sent</div>
                    <div id="frameCount" class="value">0</div>
                </div>
                <div class="info-card">
                    <div class="label">Mobile Clients</div>
                    <div id="mobileClients" class="value">0</div>
                </div>
                <div class="info-card">
                    <div class="label">Last Event</div>
                    <div id="lastEvent" class="value">None</div>
                </div>
            </div>

            <div id="alertBox" class="alert-box">
                <h2 id="alertTitle" style="margin-bottom: 10px;">🚨 ALERT!</h2>
                <p id="alertDetails"></p>
            </div>

            <p id="waitingMsg" style="color: #666; font-style: italic;">
                Waiting for mobile app to select a room...
            </p>
        </div>

        <script>
            let video = document.getElementById('video');
            let stream = null;
            let isMonitoring = false;
            let frameCount = 0;
            let canvas = document.createElement('canvas');
            let ctx = canvas.getContext('2d');
            let previewCanvas = null;
            let previewCtx = null;
            let currentRoomName = null;
            let userId = new URLSearchParams(window.location.search).get('user_id');
            const API_URL = window.location.origin;
            
            let mediaRecorder = null;
            let recordedChunks = [];
            let isRecording = false;
            let bedExitArmed = false;
            let bedExitArmStartedAt = 0;
            let bedExitPendingEventId = null;
            let bedExitPendingRoom = null;
            let bedExitFinalizeTimer = null;
            let availableCameras = [];
            let selectedCameraId = null;

            if (userId) {
                userId = userId.replace(/[^0-9]/g, '');
                if (userId) {
                    document.getElementById('setupDiv').style.display = 'none';
                } else {
                    userId = null;
                }
            }

            function setUserId() {
                const input = document.getElementById('userIdInput').value;
                if (input) {
                    userId = input.replace(/[^0-9]/g, '');
                    if (userId) {
                        document.getElementById('setupDiv').style.display = 'none';
                        startMonitoring();
                    } else {
                        alert("Please enter a valid numeric User ID");
                    }
                }
            }

            async function startMonitoring() {
                if (!userId) return;
                updateStatus('connecting', 'Scanning for cameras...');
                
                try {
                    // 1. Get list of all video devices
                    const devices = await navigator.mediaDevices.enumerateDevices();
                    availableCameras = devices
                        .filter(device => device.kind === 'videoinput')
                        .map((device, index) => ({
                            id: device.deviceId || index.toString(),
                            name: device.label || `Camera ${index + 1}`
                        }));
                    
                    console.log("Detected cameras:", availableCameras);
                    
                    // 2. Send heartbeat to server with camera list
                    await sendHeartbeat();
                    
                    // 3. Start default camera if none selected
                    if (availableCameras.length > 0) {
                        if (!selectedCameraId) selectedCameraId = availableCameras[0].id;
                        
                        stream = await navigator.mediaDevices.getUserMedia({ 
                            video: { deviceId: selectedCameraId ? { exact: selectedCameraId } : undefined, width: 640, height: 480 }, 
                            audio: false 
                        });
                        video.srcObject = stream;
                        canvas.width = 640;
                        canvas.height = 480;
                        updateStatus('connected', `Monitoring: ${availableCameras.find(c => c.id === selectedCameraId)?.name || 'Active'}`);
                    } else {
                        updateStatus('disconnected', 'No cameras found');
                    }
                } catch (error) {
                    updateStatus('disconnected', 'Camera Error: ' + error.message);
                }
            }

            async function sendHeartbeat() {
                if (!userId || availableCameras.length === 0) return;
                
                const formData = new FormData();
                formData.append('user_id', userId);
                formData.append('cameras', JSON.stringify(availableCameras));
                
                try {
                    await fetch(`${API_URL}/api/monitoring/heartbeat`, {
                        method: 'POST',
                        body: formData
                    });
                } catch (e) {
                    console.error("Heartbeat failed", e);
                }
            }

            async function loop() {
                if (userId) {
                    await sendFrame();
                    // Send heartbeat every 10 seconds (every 5 loops)
                    if (frameCount % 5 === 0) {
                        await startMonitoring(); // Re-scan and heartbeat
                    }
                }
                // Restored to original speed: 2000ms (2 seconds)
                setTimeout(loop, 2000);
            }

            function sendLivePreviewJpeg() {
                if (!stream || !userId || !isMonitoring) return;
                let roomLabel = currentRoomName;
                if (!roomLabel || roomLabel === 'None') {
                    const rn = document.getElementById('roomName');
                    if (rn && rn.textContent && rn.textContent !== 'None') roomLabel = rn.textContent;
                    else roomLabel = null;
                }
                if (!previewCanvas) {
                    previewCanvas = document.createElement('canvas');
                    previewCanvas.width = 320;
                    previewCanvas.height = 240;
                    previewCtx = previewCanvas.getContext('2d');
                }
                previewCtx.drawImage(video, 0, 0, previewCanvas.width, previewCanvas.height);
                previewCanvas.toBlob((blob) => {
                    if (!blob) return;
                    const fd = new FormData();
                    fd.append('file', blob, 'preview.jpg');
                    let url = `${API_URL}/api/laptop-preview?user_id=${userId}`;
                    if (roomLabel) url += `&room_name=${encodeURIComponent(roomLabel)}`;
                    if (selectedCameraId) url += `&camera_id=${encodeURIComponent(selectedCameraId)}`;
                    fetch(url, { method: 'POST', body: fd }).catch(() => {});
                }, 'image/jpeg', 0.58);
            }

            async function sendFrame() {
                const formData = new FormData();
                if (stream && isMonitoring) {
                    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
                    const blob = await new Promise(r => canvas.toBlob(r, 'image/jpeg', 0.8));
                    formData.append('file', blob, 'frame.jpg');
                } else {
                    const emptyBlob = new Blob([''], {type: 'application/octet-stream'});
                    formData.append('file', emptyBlob, 'poll.txt');
                }

                try {
                    // Include selected_camera_id if we have one
                    let url = `${API_URL}/api/laptop-monitor?user_id=${userId}`;
                    if (selectedCameraId) url += `&camera_id=${selectedCameraId}`;
                    
                    const response = await fetch(url, {
                        method: 'POST',
                        body: formData
                    });
                    const result = await response.json();
                    if (result.success) {
                        handleServerState(result);
                    }
                } catch (error) {
                    updateStatus('disconnected', 'Network/Server Error');
                }
            }

            function handleServerState(result) {
                const room = result.active_room;
                if (result.bed_exit_arm_recording && !bedExitArmed && !isRecording) {
                    armBedExitRecording(room);
                }
                if (result.bed_exit_detected && result.bed_exit_event_id) {
                    finalizeBedExitRecording(result.bed_exit_event_id, room, result.clip_trim_start_sec);
                }
                if ((result.fire_detected || result.door_event_detected) && !isRecording && result.event_id) {
                    startRecording(result.event_id, room, 5000, 0);
                }

                if (result.fire_detected) {
                    updateStatus('fire-detected', '⚠️ FIRE DETECTED!');
                    const alertBox = document.getElementById('alertBox');
                    alertBox.style.display = 'block';
                    alertBox.style.backgroundColor = '#d32f2f';
                    document.getElementById('alertTitle').textContent = '🚨 FIRE DETECTED!';
                    document.getElementById('alertDetails').textContent = `Confidence: ${(result.confidence * 100).toFixed(1)}%`;
                    document.getElementById('lastEvent').textContent = new Date().toLocaleTimeString();
                } else if (result.door_event_detected) {
                    updateStatus('door-detected', '🚪 DOOR ACTIVITY!');
                    const alertBox = document.getElementById('alertBox');
                    alertBox.style.display = 'block';
                    alertBox.style.backgroundColor = '#f57c00';
                    document.getElementById('alertTitle').textContent = '🚪 DOOR ACTIVITY DETECTED!';
                    document.getElementById('alertDetails').textContent = `Activity observed on door`;
                    document.getElementById('lastEvent').textContent = new Date().toLocaleTimeString();
                } else {
                    document.getElementById('alertBox').style.display = 'none';
                }

                if (room) {
                    isMonitoring = true;
                    currentRoomName = room;
                    
                    // If the server tells us to switch cameras
                    if (result.camera_id && result.camera_id !== selectedCameraId) {
                        console.log("Switching to camera:", result.camera_id);
                        selectedCameraId = result.camera_id;
                        startMonitoring(); // Re-initialize with new camera
                    }

                    document.getElementById('roomBadge').style.display = 'block';
                    document.getElementById('roomName').textContent = room;
                    document.getElementById('waitingMsg').style.display = 'none';
                    if (!result.fire_detected) updateStatus('connected', 'MONITORING ACTIVE');
                } else {
                    isMonitoring = false;
                    document.getElementById('roomBadge').style.display = 'none';
                    document.getElementById('waitingMsg').style.display = 'block';
                    if (!result.fire_detected) updateStatus('connected', 'Ready - Waiting for Mobile');
                }

                document.getElementById('mobileClients').textContent = result.mobile_clients_notified || 0;
                if (isMonitoring) {
                    frameCount++;
                    document.getElementById('frameCount').textContent = frameCount;
                }
            }

            function updateStatus(type, message) {
                const statusEl = document.getElementById('status');
                statusEl.className = 'status ' + type;
                statusEl.textContent = message;
            }

            function armBedExitRecording(roomName) {
                if (!stream || isRecording) return;
                console.log("!!! ARM BED-EXIT RECORDING (sit-up detected) !!!");
                bedExitArmed = true;
                bedExitArmStartedAt = Date.now();
                bedExitPendingRoom = roomName || currentRoomName || "Unknown";
                startRecording(null, bedExitPendingRoom, 15000, 0, true);
            }

            function finalizeBedExitRecording(eventId, roomName, trimSec) {
                if (!isRecording && !bedExitArmed) {
                    startRecording(eventId, roomName, 8000, trimSec || 0);
                    return;
                }
                bedExitPendingEventId = eventId;
                bedExitPendingRoom = roomName || bedExitPendingRoom || currentRoomName || "Unknown";
                const trim = (typeof trimSec === 'number' && trimSec > 0) ? trimSec : null;
                if (bedExitFinalizeTimer) clearTimeout(bedExitFinalizeTimer);
                bedExitFinalizeTimer = setTimeout(() => {
                    stopRecordingUpload(eventId, bedExitPendingRoom, trim);
                }, 6000);
                console.log("!!! FINALIZE BED-EXIT RECORDING in 6s for event", eventId);
            }

            function stopRecordingUpload(eventId, roomName, trimSec) {
                if (!mediaRecorder || mediaRecorder.state === "inactive") {
                    bedExitArmed = false;
                    return;
                }
                mediaRecorder._hgEventId = eventId;
                mediaRecorder._hgRoom = roomName;
                mediaRecorder._hgTrimSec = trimSec;
                mediaRecorder.stop();
            }

            function startRecording(eventId, roomName, durationMs, trimSec, isBedExitArm) {
                if (!stream || (isRecording && !isBedExitArm)) return;
                
                console.log("!!! STARTING EVENT RECORDING", durationMs, "ms !!!");
                isRecording = true;
                recordedChunks = [];
                
                const mimeCandidates = [
                    'video/webm;codecs=vp8,opus',
                    'video/webm;codecs=vp8',
                    'video/webm',
                    'video/mp4',
                ];
                let chosenMime = null;
                for (const m of mimeCandidates) {
                    if (MediaRecorder.isTypeSupported(m)) {
                        chosenMime = m;
                        break;
                    }
                }
                
                try {
                    mediaRecorder = chosenMime
                        ? new MediaRecorder(stream, { mimeType: chosenMime })
                        : new MediaRecorder(stream);
                    const outMime = (mediaRecorder.mimeType && mediaRecorder.mimeType.length > 0)
                        ? mediaRecorder.mimeType
                        : (chosenMime || 'video/webm');
                    mediaRecorder._hgTrimSec = trimSec || 0;
                    console.log("MediaRecorder using", outMime);
                    
                    mediaRecorder.ondataavailable = (event) => {
                        if (event.data.size > 0) {
                            recordedChunks.push(event.data);
                        }
                    };
                    
                    mediaRecorder.onstop = () => {
                        console.log("Recording stopped. Total chunks: " + recordedChunks.length);
                        const baseType = (outMime.split(';')[0] || 'video/webm').trim();
                        const blob = new Blob(recordedChunks, { type: baseType });
                        if (blob.size > 0) {
                            const ext = baseType.indexOf('mp4') !== -1 ? 'mp4' : 'webm';
                            const eid = mediaRecorder._hgEventId || eventId;
                            const rn = mediaRecorder._hgRoom || roomName;
                            const tr = mediaRecorder._hgTrimSec || 0;
                            uploadVideo(blob, eid, rn, ext, tr);
                        }
                        isRecording = false;
                        bedExitArmed = false;
                        bedExitPendingEventId = null;
                    };
                    
                    mediaRecorder.start();
                    
                    if (durationMs && durationMs > 0 && !bedExitArmed) {
                        setTimeout(() => {
                            if (mediaRecorder && mediaRecorder.state !== "inactive") {
                                mediaRecorder._hgEventId = eventId;
                                mediaRecorder._hgRoom = roomName;
                                mediaRecorder.stop();
                            }
                        }, durationMs);
                    }
                } catch (e) {
                    console.error("Error starting MediaRecorder: ", e);
                    isRecording = false;
                    bedExitArmed = false;
                }
            }

            async function uploadVideo(blob, eventId, roomName, ext, trimSec) {
                const fileExt = ext || 'webm';
                const formData = new FormData();
                formData.append('file', blob, 'event_clip.' + fileExt);
                formData.append('user_id', userId);
                formData.append('room_name', roomName || "Unknown");
                if (eventId) formData.append('event_id', eventId);
                if (trimSec && trimSec > 0.05) {
                    formData.append('clip_trim_start_sec', String(trimSec));
                }
                
                try {
                    console.log("Uploading event clip to server...");
                    const response = await fetch(`${API_URL}/api/upload-event-clip`, {
                        method: 'POST',
                        body: formData
                    });
                    const result = await response.json();
                    if (result.success) {
                        console.log("SUCCESS: Video clip uploaded to " + result.video_path);
                    } else {
                        console.error("Server error during upload: ", result.error);
                    }
                } catch (error) {
                    console.error('Network error during upload:', error);
                }
            }

            window.onload = () => {
                if (userId) {
                    startMonitoring();
                    setInterval(sendLivePreviewJpeg, 280);
                }
                loop();
            };
            window.onbeforeunload = () => {
                if (stream) stream.getTracks().forEach(t => t.stop());
            };
        </script>
    </body>
    </html>
    """
    return HTMLResponse(content=html_content)


# --- Pet Station (IoT feeder + ESP32-CAM) — independent from Pet Mode monitor ---

@app.post("/api/pet-station/analyze")
async def pet_station_analyze(request: Request):
    """ESP32-CAM posts JPEG; server runs YOLO and pushes verdict to main ESP32."""
    if pet_station_bridge_mod is None:
        raise HTTPException(status_code=503, detail="Pet station AI unavailable")

    device = await _pet_station_device_from_request(request)
    user_id = int(device["user_id"])
    main_ip = (device.get("main_ip") or "").strip()

    body = await request.body()
    try:
        verdict, info = pet_station_bridge_mod.process_jpeg(body)
    except FileNotFoundError as e:
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        print(f"[PET-STATION] analyze error user={user_id}: {e}")
        raise HTTPException(status_code=500, detail="Analysis failed")

    now_str = datetime.now().strftime("%H:%M:%S")
    last_detection = {
        "detected": verdict.get("detected", False),
        "eating": verdict.get("eating", False),
        "class": verdict.get("class"),
        "confidence": info.get("confidence"),
        "time": now_str,
    }

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            UPDATE pet_station_devices
            SET last_seen = CURRENT_TIMESTAMP,
                last_detection = %s,
                updated_at = CURRENT_TIMESTAMP
            WHERE user_id = %s
            """,
            (Json(last_detection), user_id),
        )
        conn.commit()
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"[PET-STATION] failed to persist last_detection: {e}")

    if main_ip:
        try:
            r = requests.post(
                f"http://{main_ip}/ai_result",
                json=verdict,
                timeout=3,
            )
            print(
                f"[PET-STATION] verdict user={user_id} -> {main_ip}/ai_result "
                f"status={r.status_code} body={verdict}"
            )
        except Exception as e:
            print(f"[PET-STATION] verdict push failed user={user_id} main={main_ip}: {e}")
    else:
        print(f"[PET-STATION] analyze user={user_id}: main_ip not configured")

    return verdict


@app.post("/api/pet-station/event")
async def pet_station_event(request: Request):
    """Main ESP32 posts feeder state changes."""
    device = await _pet_station_device_from_request(request)
    user_id = int(device["user_id"])

    try:
        data = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    if not isinstance(data, dict):
        raise HTTPException(status_code=400, detail="JSON object required")

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            UPDATE pet_station_devices
            SET last_seen = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
            WHERE user_id = %s
            """,
            (user_id,),
        )
        conn.commit()
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"[PET-STATION] event last_seen update failed: {e}")

    return await _handle_pet_station_esp32_event(user_id, data)


@app.get("/api/lost-items")
async def list_lost_items(current_user: dict = Depends(get_current_user)):
    """List tracked lost-item locations (one row per item + room)."""
    if lost_item_service is None:
        return {"success": True, "items": []}
    owner_id = effective_owner_id(current_user)
    items = await asyncio.to_thread(lost_item_service.list_items, owner_id)
    return {"success": True, "items": items}


@app.get("/api/lost-items/{item_id}")
async def get_lost_item(
    item_id: int,
    current_user: dict = Depends(get_current_user),
):
    """Single lost-item record with cropped screenshot path."""
    if lost_item_service is None:
        raise HTTPException(status_code=503, detail="Lost item service unavailable")
    owner_id = effective_owner_id(current_user)
    item = await asyncio.to_thread(lost_item_service.get_item, owner_id, item_id)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return {"success": True, "item": item}


@app.get("/api/pet-station/status")
async def pet_station_status(current_user: dict = Depends(get_current_user)):
    """Dashboard poll: last AI detection + recent feeder events."""
    owner_id = effective_owner_id(current_user)
    row = _get_pet_station_row(owner_id)

    if not row:
        return {
            "configured": False,
            "cam_ip": None,
            "main_ip": None,
            "device_token": None,
            "last_detection": {},
            "events": [],
            "last_seen": None,
        }

    last_det = row.get("last_detection") or {}
    if isinstance(last_det, str):
        try:
            last_det = json.loads(last_det)
        except Exception:
            last_det = {}

    last_seen = row.get("last_seen")
    if isinstance(last_seen, datetime):
        last_seen = last_seen.isoformat()

    show_token = current_user.get("role") != "family"
    return {
        "configured": True,
        "cam_ip": row.get("cam_ip"),
        "main_ip": row.get("main_ip"),
        "device_token": row.get("device_token") if show_token else None,
        "last_detection": last_det,
        "events": list(_pet_station_history(owner_id)),
        "last_seen": last_seen,
    }


@app.get("/api/pet-station/snapshot")
async def pet_station_snapshot(current_user: dict = Depends(get_current_user)):
    """
    Proxy one JPEG from the ESP32-CAM for the dashboard.
    Tries /snapshot first, then one frame from :81/stream (snapshot often hangs while streaming).
    """
    owner_id = effective_owner_id(current_user)
    row = _get_pet_station_row(owner_id)
    cam_ip = (row.get("cam_ip") if row else None) or ""
    cam_ip = cam_ip.strip()
    if not cam_ip:
        raise HTTPException(status_code=404, detail="ESP32-CAM IP not configured")

    async with _pet_station_snapshot_lock:
        jpeg = await asyncio.to_thread(_fetch_pet_cam_jpeg, cam_ip)

    if not jpeg:
        raise HTTPException(
            status_code=502,
            detail=(
                f"Could not get a frame from ESP32-CAM at {cam_ip}. "
                "Open http://{cam_ip}:81/stream in a browser — if that fails, reboot the CAM."
            ).replace("{cam_ip}", cam_ip),
        )

    return Response(
        content=jpeg,
        media_type="image/jpeg",
        headers={"Cache-Control": "no-cache, no-store, must-revalidate"},
    )


def _extract_jpeg_from_buffer(buf: bytes) -> bytes:
    soi = buf.find(b"\xff\xd8")
    if soi < 0:
        return b""
    eoi = buf.find(b"\xff\xd9", soi + 2)
    if eoi < 0:
        return b""
    return buf[soi : eoi + 2]


def _fetch_pet_cam_jpeg(cam_ip: str) -> bytes:
    """Fetch one JPEG from ESP32-CAM (/snapshot, else first MJPEG stream frame)."""
    snap_url = f"http://{cam_ip}/snapshot"
    try:
        r = requests.get(snap_url, timeout=(3, 8))
        if r.status_code == 200 and len(r.content) > 500:
            return r.content
    except Exception as e:
        print(f"[PET-STATION] /snapshot timed out cam={cam_ip}: {e}")

    stream_url = f"http://{cam_ip}:81/stream"
    try:
        with requests.get(stream_url, stream=True, timeout=(3, 18)) as resp:
            if resp.status_code != 200:
                print(f"[PET-STATION] stream HTTP {resp.status_code} cam={cam_ip}")
                return b""
            buf = b""
            for chunk in resp.iter_content(chunk_size=2048):
                if not chunk:
                    continue
                buf += chunk
                frame = _extract_jpeg_from_buffer(buf)
                if len(frame) > 500:
                    print(
                        f"[PET-STATION] snapshot via MJPEG cam={cam_ip} ({len(frame)} bytes)"
                    )
                    return frame
                if len(buf) > 400_000:
                    soi = buf.rfind(b"\xff\xd8")
                    buf = buf[soi:] if soi >= 0 else buf[-16384:]
    except Exception as e:
        print(f"[PET-STATION] stream fallback failed cam={cam_ip}: {e}")
    return b""


@app.post("/api/pet-station/settings")
async def pet_station_settings(
    data: dict,
    current_user: dict = Depends(get_current_user),
):
    """Save CAM / main ESP32 IPs and optionally rotate device token (owner only)."""
    require_home_owner(current_user)
    owner_id = effective_owner_id(current_user)

    cam_ip = (data.get("cam_ip") or "").strip() or None
    main_ip = (data.get("main_ip") or "").strip() or None
    regenerate = bool(data.get("regenerate_token"))

    existing = _get_pet_station_row(owner_id)
    token = existing["device_token"] if existing else _generate_pet_station_device_token()
    if regenerate:
        token = _generate_pet_station_device_token()

    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        if existing:
            cursor.execute(
                """
                UPDATE pet_station_devices
                SET cam_ip = %s,
                    main_ip = %s,
                    device_token = %s,
                    updated_at = CURRENT_TIMESTAMP
                WHERE user_id = %s
                RETURNING *
                """,
                (cam_ip, main_ip, token, owner_id),
            )
        else:
            cursor.execute(
                """
                INSERT INTO pet_station_devices
                    (user_id, device_token, cam_ip, main_ip)
                VALUES (%s, %s, %s, %s)
                RETURNING *
                """,
                (owner_id, token, cam_ip, main_ip),
            )
        row = cursor.fetchone()
        conn.commit()
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"[PET-STATION] settings save failed: {e}")
        raise HTTPException(status_code=500, detail="Could not save pet station settings")

    return {
        "success": True,
        "cam_ip": row.get("cam_ip"),
        "main_ip": row.get("main_ip"),
        "device_token": row.get("device_token"),
    }


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", "3000"))
    uvicorn.run(app, host="0.0.0.0", port=port)
