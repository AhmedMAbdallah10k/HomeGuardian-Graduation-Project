"""
Hazard proximity detection on dashboard JPEG uploads (`/api/laptop-monitor`).

Loads `MODES/Pet Mode/Hazard_area_detection/detector.py` via importlib without
importing or modifying main.py / detector.py / config.py / zone_manager.py.

Runs COCO hazard checks only (oven, microwave, toilet, tv) — manual zones are
loaded if present but zone drawing is not required for phase 1.

When both Nanny and Pet modes are assigned to a room, both pipelines run on
each frame (person hazards + pet hazards).
"""

from __future__ import annotations

import importlib.util
import re
import sys
import threading
from pathlib import Path
from typing import Dict, List, Tuple

_HAZARD_DIR = (
    Path(__file__).resolve().parent
    / "MODES"
    / "Pet Mode"
    / "Hazard_area_detection"
)
_YOLO_PT = _HAZARD_DIR / "yolov8n.pt"

_module_lock = threading.Lock()
_DetectorClass = None

_pipeline_lock = threading.Lock()
_pipelines: Dict[Tuple[int, str, str], object] = {}


def _load_detector_class():
    global _DetectorClass
    if _DetectorClass is not None:
        return _DetectorClass

    with _module_lock:
        if _DetectorClass is not None:
            return _DetectorClass

        if not (_HAZARD_DIR / "detector.py").is_file():
            raise FileNotFoundError(f"Missing hazard detector: {_HAZARD_DIR / 'detector.py'}")

        hazard_path = str(_HAZARD_DIR)
        inserted = hazard_path not in sys.path
        if inserted:
            sys.path.insert(0, hazard_path)

        saved_config = sys.modules.get("config")
        saved_zone = sys.modules.get("zone_manager")

        try:
            spec_c = importlib.util.spec_from_file_location(
                "hg_hazard_config", _HAZARD_DIR / "config.py"
            )
            mod_c = importlib.util.module_from_spec(spec_c)
            sys.modules["config"] = mod_c
            spec_c.loader.exec_module(mod_c)

            spec_z = importlib.util.spec_from_file_location(
                "hg_hazard_zone_manager", _HAZARD_DIR / "zone_manager.py"
            )
            mod_z = importlib.util.module_from_spec(spec_z)
            sys.modules["zone_manager"] = mod_z
            spec_z.loader.exec_module(mod_z)

            spec_d = importlib.util.spec_from_file_location(
                "hg_hazard_detector", _HAZARD_DIR / "detector.py"
            )
            mod_d = importlib.util.module_from_spec(spec_d)
            spec_d.loader.exec_module(mod_d)

            _DetectorClass = mod_d.Detector
            print(f"[HAZARD-BRIDGE] detector loaded from {_HAZARD_DIR}")
        finally:
            if inserted:
                try:
                    sys.path.remove(hazard_path)
                except ValueError:
                    pass
            if saved_config is not None:
                sys.modules["config"] = saved_config
            else:
                sys.modules.pop("config", None)
            if saved_zone is not None:
                sys.modules["zone_manager"] = saved_zone
            else:
                sys.modules.pop("zone_manager", None)

    return _DetectorClass


def _camera_id(user_id: int, room_name: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9_-]+", "_", room_name.strip())[:40] or "room"
    return f"u{user_id}_{slug}"


def _get_pipeline(user_id: int, room_name: str, mode: str):
    Detector = _load_detector_class()
    key = (user_id, room_name.strip(), mode)
    with _pipeline_lock:
        det = _pipelines.get(key)
        if det is None:
            model_path = str(_YOLO_PT)
            det = Detector(
                camera_id=_camera_id(user_id, room_name),
                mode=mode,
                model_path=model_path,
                on_alert=None,
                on_emergency=None,
            )
            det.load_zones()
            _pipelines[key] = det
        return det


def preload() -> None:
    _load_detector_class()
    model_path = str(_YOLO_PT)
    if not _YOLO_PT.is_file():
        print(
            f"[HAZARD-BRIDGE] {model_path} not found yet — "
            "Ultralytics may download on first detection frame."
        )
    else:
        print(f"[HAZARD-BRIDGE] using weights {_YOLO_PT}")


def process_upload_jpeg(
    user_id: int,
    room_name: str,
    jpeg_bytes: bytes,
    run_nanny: bool,
    run_pet: bool,
) -> List[dict]:
    """
    Run hazard detection for enabled modes. Returns alert dicts fired this frame
    (same structure as standalone detector._maybe_fire output).
    """
    import cv2
    import numpy as np

    room = (room_name or "").strip()
    if not room or room == "Unknown":
        return []
    if not jpeg_bytes or len(jpeg_bytes) < 80:
        return []
    if not run_nanny and not run_pet:
        return []

    arr = np.frombuffer(jpeg_bytes, dtype=np.uint8)
    frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if frame is None:
        return []

    fired: List[dict] = []
    modes: List[str] = []
    if run_nanny:
        modes.append("nanny")
    if run_pet:
        modes.append("pet")

    for mode in modes:
        try:
            detector = _get_pipeline(user_id, room, mode)
            _, alerts = detector.process(frame.copy())
            if alerts:
                fired.extend(alerts)
        except Exception as exc:
            print(f"[HAZARD-BRIDGE] mode={mode} user={user_id} room={room!r}: {exc}")

    return fired
