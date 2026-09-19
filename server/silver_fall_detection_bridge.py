"""
Fall detector on dashboard JPEG uploads (same path as `/api/laptop-monitor`).

Deployed for Silver, Nanny, and Nurse room assignments — same classifier artifacts directory
under Silver Mode FALL_DETECTION. Uses the same logic as `realtime_fall_detection.py` without
importing that script (and without a subprocess webcam). Pipeline:
  Mediapipe Pose → 99 dims → sliding window → Keras classifier.

`realtime_fall_detection.py` stays available for standalone OpenCV demos.
"""

from __future__ import annotations

import os
import threading
from collections import deque
from pathlib import Path
from typing import Any, Dict, Tuple

# Match realtime script compatibility hints (safe before tf/mp import).
os.environ.setdefault("PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION", "python")
os.environ.setdefault("TF_ENABLE_ONEDNN_OPTS", "0")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")

import cv2  # noqa: E402
import mediapipe as mp  # noqa: E402
import numpy as np  # noqa: E402

_ARTIFACT_DIR = (
    Path(__file__).resolve().parent
    / "MODES"
    / "Silver Mode"
    / "FALL_DETECTION"
    / "FALL_DETECTION"
)

MODEL_PATH = _ARTIFACT_DIR / "best_fall_detection_model.keras"
MEAN_PATH = _ARTIFACT_DIR / "feature_mean.npy"
STD_PATH = _ARTIFACT_DIR / "feature_std.npy"

WINDOW_SIZE = 30
N_FEATURES = 99
FALL_THRESHOLD = 0.5  # alert when prob >= this (very sensitive; normal pose ~0.002–0.01)
SMOOTHING_WINDOW = 5
ALERT_DURATION_SEC = 3.0

_model_lock = threading.Lock()
_model = None  # keras model
_feature_mean = None
_feature_std = None

_cache_lock = threading.Lock()
_detectors: Dict[Tuple[int, str], "_RoomFallDetector"] = {}


class _RoomFallDetector:
    """Stateful fall pipeline for one (user_id, room) stream."""

    __slots__ = (
        "_pose",
        "_lock",
        "frame_buffer",
        "pred_buffer",
        "alert_active",
        "alert_start_time",
    )

    def __init__(self) -> None:
        # Laptop-monitor JPEGs arrive sporadically (~2 FPS), not as a steady webcam
        # stream. Video-mode Pose expects monotonic frame timestamps and can abort the
        # process on mismatch; static mode treats each upload independently.
        self._lock = threading.Lock()
        self._pose = self._new_pose()
        self.frame_buffer: deque[np.ndarray] = deque(maxlen=WINDOW_SIZE)
        self.pred_buffer: deque[float] = deque(maxlen=SMOOTHING_WINDOW)
        self.alert_active = False
        self.alert_start_time = 0.0

    @staticmethod
    def _new_pose():
        return mp.solutions.pose.Pose(
            static_image_mode=True,
            model_complexity=1,
            smooth_landmarks=False,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
        )

    def _reset_pose(self) -> None:
        try:
            self._pose.close()
        except Exception:
            pass
        self._pose = self._new_pose()

    def close(self) -> None:
        try:
            self._pose.close()
        except Exception:
            pass

    @staticmethod
    def _get_landmarks(results) -> Tuple[np.ndarray, bool]:
        if not results.pose_landmarks:
            return np.zeros(N_FEATURES, dtype=np.float32), False
        coords = []
        for lm in results.pose_landmarks.landmark:
            coords.extend([lm.x, lm.y, lm.z])
        return np.asarray(coords, dtype=np.float32), True

    @staticmethod
    def _normalize(features: np.ndarray, mean: np.ndarray, std: np.ndarray) -> np.ndarray:
        if np.all(features == 0):
            return features
        return np.where(features != 0, (features - mean) / std, 0.0).astype(np.float32)

    def process_frame(
        self,
        bgr_frame: np.ndarray,
        *,
        keras_model,
        mean: np.ndarray,
        std: np.ndarray,
        now_mono: float,
    ) -> Tuple[bool, Dict[str, Any]]:
        """
        Update state from one BGR frame. Returns (broadcast_alert_now, diagnostics).
        """
        info: Dict[str, Any] = {
            "buffer_fill": len(self.frame_buffer) / WINDOW_SIZE,
            "person_visible": False,
            "probability": 0.0,
            "is_fall_raw": False,
        }

        frame = cv2.flip(bgr_frame, 1)
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        rgb.flags.writeable = False
        with self._lock:
            try:
                results = self._pose.process(rgb)
            except Exception as exc:
                msg = str(exc)
                if "timestamp mismatch" in msg or "CalculatorGraph" in msg:
                    self._reset_pose()
                    results = self._pose.process(rgb)
                else:
                    raise
        rgb.flags.writeable = True

        lm, person_visible = self._get_landmarks(results)
        info["person_visible"] = bool(person_visible)
        norm_lm = self._normalize(lm, mean, std)
        self.frame_buffer.append(norm_lm)

        probability = 0.0
        is_fall = False

        if len(self.frame_buffer) == WINDOW_SIZE and person_visible:
            seq = np.array(self.frame_buffer, dtype=np.float32).reshape(
                1, WINDOW_SIZE, N_FEATURES
            )
            raw = float(keras_model.predict(seq, verbose=0)[0][0])
            self.pred_buffer.append(raw)
            probability = float(np.mean(self.pred_buffer))
            is_fall = probability >= FALL_THRESHOLD
            info["is_fall_raw"] = bool(is_fall)
            info["probability"] = probability

        emit_edge = False
        if is_fall and not self.alert_active:
            self.alert_active = True
            self.alert_start_time = now_mono
            emit_edge = True

        alert_countdown = 0.0
        if self.alert_active:
            elapsed = now_mono - self.alert_start_time
            alert_countdown = max(0.0, ALERT_DURATION_SEC - elapsed)
            info["alert_countdown"] = alert_countdown
            if elapsed >= ALERT_DURATION_SEC:
                if is_fall:
                    self.alert_start_time = now_mono
                else:
                    self.alert_active = False

        info["probability"] = probability
        info["alert_active"] = self.alert_active
        info["buffer_fill"] = (
            len(self.frame_buffer) / WINDOW_SIZE
            if len(self.frame_buffer) < WINDOW_SIZE
            else 1.0
        )

        return emit_edge, info


def _ensure_model():
    """Lazy-load Keras weights once (Keras-3 .keras file + mixed TF/tf-keras stacks)."""
    global _model, _feature_mean, _feature_std
    if _model is not None:
        return _model, _feature_mean, _feature_std

    with _model_lock:
        if _model is not None:
            return _model, _feature_mean, _feature_std

        if not MODEL_PATH.is_file():
            raise FileNotFoundError(f"Silver fall model missing: {MODEL_PATH}")
        if not MEAN_PATH.is_file() or not STD_PATH.is_file():
            raise FileNotFoundError(
                f"Silver fall stats missing: {MEAN_PATH} / {STD_PATH}"
            )

        mp = str(MODEL_PATH)
        errors: list[str] = []

        _keras_lib = None
        try:
            import keras as _kl

            _keras_lib = _kl
            if hasattr(_kl.config, "enable_unsafe_deserialization"):
                _kl.config.enable_unsafe_deserialization()
        except Exception:
            _keras_lib = None

        import tensorflow as tf  # noqa: E402

        tf.get_logger().setLevel("ERROR")

        # 1) Standalone Keras 3 (often required for `.keras` saved with keras.src.* metadata)
        if _keras_lib is not None:
            try:
                _model = _keras_lib.models.load_model(mp, compile=False)
                print(
                    "[SILVER-FALL-BRIDGE] model loaded via keras "
                    f"{getattr(_model, 'input_shape', None)}"
                )
            except Exception as e1:
                errors.append(f"keras.models.load_model: {e1!r}")
                _model = None
        else:
            _model = None

        # 2) tf.keras — try safe_mode when available (TF 2.14+)
        if _model is None:
            try:
                try:
                    _model = tf.keras.models.load_model(
                        mp, compile=False, safe_mode=False
                    )
                except TypeError:
                    _model = tf.keras.models.load_model(mp, compile=False)
                print(f"[SILVER-FALL-BRIDGE] model loaded via tf.keras {_model.input_shape}")
            except Exception as e2:
                errors.append(f"tf.keras.models.load_model: {e2!r}")
                _model = None

        if _model is None:
            raise RuntimeError(
                "Could not load Silver fall classifier. Align TensorFlow/Keras packages to "
                "the version used when saving the model, e.g.\n"
                "  pip install -U tensorflow keras\n\n"
                "Details:\n"
                + "\n".join(errors)
            )

        _feature_mean = np.load(str(MEAN_PATH))
        _feature_std = np.load(str(STD_PATH))
        _feature_std[_feature_std == 0] = 1.0

        return _model, _feature_mean, _feature_std


def process_upload_jpeg(user_id: int, room_label: str, jpeg_bytes: bytes) -> Tuple[bool, dict]:
    """
    Decode laptop-monitor JPEG and run streaming fall classifier (one step).
    `(True, info)` means emit a dashboard/mobile alert **this upload** (fall crossing edge).
    """
    import time as time_module

    if not jpeg_bytes or len(jpeg_bytes) < 80:
        return False, {}

    arr = np.frombuffer(jpeg_bytes, dtype=np.uint8)
    frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if frame is None:
        return False, {}

    h, w = frame.shape[:2]
    longest = max(h, w)
    if longest < 640:
        scale = 720.0 / float(longest)
        frame = cv2.resize(
            frame,
            (int(w * scale), int(h * scale)),
            interpolation=cv2.INTER_LINEAR,
        )

    try:
        keras_model, mean, std = _ensure_model()
    except Exception as e:
        print(f"[SILVER-FALL-BRIDGE] load error: {e}")
        return False, {"error": str(e)}

    key = (user_id, room_label.strip())
    with _cache_lock:
        det = _detectors.get(key)
        if det is None:
            if len(_detectors) > 48:
                for k_old, old in list(_detectors.items())[:20]:
                    old.close()
                    del _detectors[k_old]
                print("[SILVER-FALL-BRIDGE] trimmed old room detectors cache")
            det = _RoomFallDetector()
            _detectors[key] = det

    now_mono = time_module.monotonic()
    try:
        alert_now, payload = det.process_frame(
            frame, keras_model=keras_model, mean=mean, std=std, now_mono=now_mono
        )
    except Exception as e:
        print(f"[SILVER-FALL-BRIDGE] process_frame: {e}")
        return False, {"error": str(e)}

    payload["alert"] = bool(alert_now)
    return bool(alert_now), payload
