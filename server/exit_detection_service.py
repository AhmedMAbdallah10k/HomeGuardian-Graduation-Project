"""
Silver room-exit alerts on `/api/laptop-monitor` JPEGs — delegates to Silver Mode module
`MODES/Silver Mode/door_exit_detection/detection_pipeline.py` without editing that script.

Each monitored (user_id, room) stream gets its **own dynamically loaded copy** of the pipeline
module so globals (`_door_model`, `_person_model`, tracker state) stay isolated per stream.
"""

from __future__ import annotations

import importlib.util
import re
import sys
import threading
from collections import OrderedDict
from pathlib import Path
from types import ModuleType
from typing import Any, Dict, Optional, Tuple
import os
import time

import cv2
import numpy as np
import torch

from base_ai_service import BaseAIService

_SILVER_PIPE_DIR = (
    Path(__file__).resolve().parent / "MODES" / "Silver Mode" / "door_exit_detection"
)
_PIPELINE_PY = _SILVER_PIPE_DIR / "detection_pipeline.py"


try:
    _mx_raw = (os.environ.get("EXIT_PIPELINE_MAX_STREAMS", "12") or "12").strip()
    _MAX_STREAM_MODULES = max(2, min(32, int(_mx_raw)))
except ValueError:
    _MAX_STREAM_MODULES = 12


def _silver_exit_assets_present() -> bool:
    dm = _SILVER_PIPE_DIR / "best_v4.pt"
    ym = _SILVER_PIPE_DIR / "botsort_custom.yaml"
    return dm.is_file() and ym.is_file()


def _sanitize_moniker(fragment: str) -> str:
    s = fragment.strip().replace("/", "_").replace("\\", "_")
    safe = re.sub(r"[^\w]", "_", s, flags=re.UNICODE).strip("_")
    return (safe[:48] if safe else "room")


def _env_truthy(name: str, default: bool = True) -> bool:
    v = os.environ.get(name)
    if v is None or str(v).strip() == "":
        return default
    return str(v).strip().lower() in ("1", "true", "yes", "on")


def _upscale_small_bgr(frame: np.ndarray) -> np.ndarray:
    """Thin dashboard JPEGs are harder on YOLO; keep behaviour local to adapter (pipeline file untouched)."""
    h, w = frame.shape[:2]
    longest = max(h, w)
    if longest < 640:
        scale = 720.0 / float(longest)
        return cv2.resize(
            frame,
            (int(w * scale), int(h * scale)),
            interpolation=cv2.INTER_LINEAR,
        )
    return frame


def _monitor_tune_loaded_pipeline(mod: ModuleType) -> None:
    """Sparse laptop-monitor uploads vs webcam FPS: shorten door/person modulo + cooldown unless strict env."""
    if _env_truthy("EXIT_USE_WEBCAM_PIPELINE_CADENCE", default=False):
        return
    mod.DOOR_INFER_EVERY_N_FRAMES = 1  # type: ignore[attr-defined]
    mod.PERSON_INFER_EVERY_N_FRAMES = 1  # type: ignore[attr-defined]
    try:
        dc = int((os.environ.get("EXIT_UPLOAD_COOLDOWN_FRAMES", "") or "15").strip())
    except ValueError:
        dc = 15
    mod.EXIT_COOLDOWN_FRAMES_AFTER_FIRE = max(5, min(120, dc))  # type: ignore[attr-defined]


def _relax_door_label_maybe(state: Any) -> bool:
    """
    Mirror common class-name variants without editing detection_pipeline.py on disk.
    Returns True iff door_state was changed.
    """
    if not _env_truthy("EXIT_MONITOR_RELAX_DOOR_LABEL", default=True):
        return False
    if state.last_door_label is None:
        return False
    ln = str(state.last_door_label).strip().lower()
    before = state.door_state

    loosely_open = (
        ln == "door_opened"
        or ln.endswith("_opened")
        or "ajar" in ln
        or (("opened" in ln or "open" in ln) and "closed" not in ln)
    )
    loosely_closed = "closed" in ln and ("open" not in ln or "opened" not in ln)

    if loosely_open and not loosely_closed:
        state.door_state = "open"
    elif loosely_closed:
        state.door_state = "closed"

    return before != state.door_state


def _gather_tracked_with_recovery(mod: ModuleType, state: Any) -> list:
    frame_count = int(state.frame_count)
    tracked = []
    results = state.person_results
    tracked_tid_present: list[int] = []
    pm = getattr(mod, "_person_model")

    rec = getattr(mod, "TRACK_RECOVERY_LAST_SEEN_FRAMES", 10)
    if results is not None:
        for r in results:
            boxes = getattr(r, "boxes", None)
            if boxes is None or boxes.id is None:
                continue
            for box, tid_raw, cls in zip(
                boxes.xyxy.cpu(),
                boxes.id.cpu().int(),
                boxes.cls.cpu(),
            ):
                if pm.names[int(cls)] != "person":
                    continue
                tid_i = int(tid_raw)
                x1, y1, x2, y2 = box
                xf1, xf2, xf3, xf4 = float(x1), float(y1), float(x2), float(y2)
                tracked.append((tid_i, xf1, xf2, xf3, xf4))
                tracked_tid_present.append(tid_i)

    for tid_p, tup in list(state.last_seen.items()):
        x1, y1, x2, y2, last_frame = tup
        if frame_count - last_frame < rec and tid_p not in tracked_tid_present:
            tracked.append((tid_p, x1, y1, x2, y2))
    return tracked


def _supplement_exit_crossing(mod: ModuleType, state: Any) -> bool:
    """Run exit-line crossing when pipeline skipped branch (e.g. door_state was wrong closed)."""
    if not state.last_door_box or state.door_state != "open":
        return False
    dx1, dy1, dx2, dy2 = map(int, state.last_door_box)
    exit_line = int(dy1 + (dy2 - dy1) * 0.85)
    fc = int(state.frame_count)
    cooldown = int(getattr(mod, "EXIT_COOLDOWN_FRAMES_AFTER_FIRE", 60))
    tracked = _gather_tracked_with_recovery(mod, state)
    exit_detected = False

    for xtid, x1, y1, x2, y2 in tracked:
        cy = float(y1 + (y2 - y1) * 0.85)
        pid = int(xtid)

        prev_y_raw = state.prev_centers.get(pid)
        prev_y = float(prev_y_raw) if prev_y_raw is not None else cy

        if prev_y_raw is not None and prev_y > exit_line and cy <= exit_line:
            if fc > int(state.exit_cooldown):
                exit_detected = True
                state.exit_cooldown = fc + cooldown

        state.prev_centers[pid] = cy

    return exit_detected


def _run_detection_pipeline_adapter(
    mod: ModuleType, frame: np.ndarray, pipe_state: Any, *, annotate: bool = False
) -> Tuple[bool, Any, Optional[np.ndarray]]:
    proc = mod.process_frame_bgr
    exit_now, pipe_state_updated, disp = proc(frame, pipe_state, annotate=annotate)

    relaxed = _relax_door_label_maybe(pipe_state_updated)

    supplemental = False
    if relaxed and pipe_state_updated.door_state == "open" and not exit_now:
        supplemental = _supplement_exit_crossing(mod, pipe_state_updated)

    return bool(exit_now or supplemental), pipe_state_updated, disp


class ExitDetectionService(BaseAIService):
    """Delegates inference to Silver `detection_pipeline.process_frame_bgr`; no duplicate weights logic."""

    def __init__(self) -> None:
        self._infer_lock = threading.RLock()
        self._streams: OrderedDict[Tuple[int, str], Tuple[ModuleType, Any]] = OrderedDict()
        self._stream_seq = 0
        torch.set_grad_enabled(False)

        if _PIPELINE_PY.is_file():
            print(f"[EXIT] Silver pipeline script: {_PIPELINE_PY}")
        else:
            print(f"[EXIT] MISSING pipeline file: {_PIPELINE_PY}")

        if not _silver_exit_assets_present():
            print(
                f"[EXIT] Missing best_v4.pt or botsort_custom.yaml under {_SILVER_PIPE_DIR}; "
                "exit detection inactive until assets exist."
            )
        else:
            print(f"[EXIT] Silver exit assets OK under {_SILVER_PIPE_DIR}")

    def _touch_stream(self, key: Tuple[int, str]) -> None:
        if key in self._streams:
            self._streams.move_to_end(key)

    def _evict_oldest_stream_unlocked(self) -> None:
        if not self._streams:
            return
        stale_key = next(iter(self._streams))
        mod, _st = self._streams.pop(stale_key)
        nm = getattr(mod, "__name__", None)
        if isinstance(nm, str) and nm in sys.modules:
            sys.modules.pop(nm, None)

    def _pipeline_module_and_state(self, key: Tuple[int, str]) -> Tuple[ModuleType, Any]:
        if key not in self._streams:
            while len(self._streams) >= _MAX_STREAM_MODULES:
                self._evict_oldest_stream_unlocked()

            self._stream_seq += 1
            uid, room_lbl = key
            moniker = f"hg_exit_pipe_{uid}_{_sanitize_moniker(room_lbl)}_{self._stream_seq}"

            spec = importlib.util.spec_from_file_location(moniker, _PIPELINE_PY)
            if spec is None or spec.loader is None:
                raise RuntimeError(f"Cannot load {_PIPELINE_PY}")
            mod = importlib.util.module_from_spec(spec)
            sys.modules[moniker] = mod
            spec.loader.exec_module(mod)
            _monitor_tune_loaded_pipeline(mod)

            PipeState = mod.DoorExitStreamState  # noqa: SLF001
            self._streams[key] = (mod, PipeState())
            self._touch_stream(key)

        self._streams.move_to_end(key)
        return self._streams[key]

    def detect(self, image_bytes: bytes, **kwargs) -> Dict[str, Any]:
        user_id = int(kwargs.get("user_id") or 0)
        room_name = kwargs.get("room_name") or "Unknown"
        result = self.detect_exit(image_bytes, user_id, room_name)
        return {
            "success": result.get("success", False),
            "event_detected": result.get("exit_detected", False),
            "detections": [],
            "type": "exit",
            "metadata": {k: v for k, v in result.items() if k not in ("success", "exit_detected")},
        }

    def detect_exit(self, image_bytes: bytes, user_id: int, room_name: str) -> Dict[str, Any]:
        if (
            not _PIPELINE_PY.is_file()
            or not image_bytes
            or len(image_bytes) < 80
            or not _silver_exit_assets_present()
        ):
            return {
                "success": False,
                "exit_detected": False,
                "error": "Pipeline or assets unavailable",
            }

        room_key = (user_id, (room_name or "Unknown").strip() or "Unknown")

        with self._infer_lock:
            try:
                mod, pipe_state = self._pipeline_module_and_state(room_key)
                self._touch_stream(room_key)

                nparr = np.frombuffer(image_bytes, dtype=np.uint8)
                frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
                if frame is None:
                    return {"success": False, "exit_detected": False, "error": "Decode failed"}

                frame = _upscale_small_bgr(frame)

                exit_now, pipe_state_updated, _ = _run_detection_pipeline_adapter(
                    mod, frame, pipe_state, annotate=False
                )
                assert pipe_state_updated is pipe_state

                door_state = pipe_state_updated.door_state
                door_label = pipe_state_updated.last_door_label

                return {
                    "success": True,
                    "exit_detected": bool(exit_now),
                    "door_state": door_state,
                    "door_label": door_label,
                    "timestamp": time.time(),
                }
            except FileNotFoundError as e:
                print(f"[EXIT] {e}")
                return {"success": False, "exit_detected": False, "error": str(e)}
            except Exception as e:
                print(f"[EXIT] detection_pipeline delegation error: {e}")
                return {"success": False, "exit_detected": False, "error": str(e)}


_exit_detection_service: Optional[ExitDetectionService] = None


def get_exit_detection_service() -> ExitDetectionService:
    global _exit_detection_service
    if _exit_detection_service is None:
        _exit_detection_service = ExitDetectionService()
    return _exit_detection_service
