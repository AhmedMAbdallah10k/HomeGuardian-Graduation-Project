#!/usr/bin/env python3
"""
Home Guardian — Real-Time Pest & Wildlife Detector
Detects: Insect · Lizard · Rodent

Usage:
  python realtime_detector.py                          # webcam (index 0)
  python realtime_detector.py --source 1               # second camera
  python realtime_detector.py --source video.mp4       # video file
  python realtime_detector.py --source rtsp://...      # IP camera stream
  python realtime_detector.py --model path/to/best.pt  # custom model path

Controls (while window is open):
  Q or ESC   → quit
  S          → save screenshot
  R          → start/stop recording
  +          → raise confidence threshold by 0.05
  -          → lower confidence threshold by 0.05
  P          → pause / resume
"""

import cv2
import sys
import time
import argparse
import numpy as np
from pathlib import Path
from collections import deque, defaultdict
from datetime import datetime

# ── Class palette (BGR for OpenCV) ────────────────────────────────────────────
PALETTE = {
    'Insect': (180, 184, 20),   # teal
    'Lizard': (250, 139, 167),  # purple
    'Rodent': (22, 116, 249),   # orange
}
DEFAULT_COLOR = (180, 180, 180)

# ── Default settings ──────────────────────────────────────────────────────────
DEFAULT_MODEL    = r"D:\flutter_application_1\flutter_application_1\server\pests\pests\best.pt"
DEFAULT_CONF     = 0.80
DEFAULT_IOU      = 0.45
DEFAULT_IMG_SIZE = 960
DEFAULT_SAVE_DIR = 'detections'


def hex_to_bgr(h):
    h = h.lstrip('#')
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return (b, g, r)


def draw_box(frame, x1, y1, x2, y2, label, conf, color):
    """Draw a detection box with label badge."""
    cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
    text = f"{label}  {conf:.0%}"
    font       = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 0.55
    thickness  = 1
    (tw, th), baseline = cv2.getTextSize(text, font, font_scale, thickness)
    pad = 4
    bx1, by1 = x1, max(y1 - th - pad * 2 - baseline, 0)
    bx2, by2 = x1 + tw + pad * 2, y1
    cv2.rectangle(frame, (bx1, by1), (bx2, by2), color, -1)
    cv2.putText(frame, text, (bx1 + pad, by2 - baseline - 1),
                font, font_scale, (255, 255, 255), thickness, cv2.LINE_AA)


def draw_hud(frame, fps, conf_thresh, counts, paused, recording):
    """Draw the heads-up display overlay."""
    h, w = frame.shape[:2]

    # Top bar
    overlay = frame.copy()
    cv2.rectangle(overlay, (0, 0), (w, 50), (10, 12, 16), -1)
    cv2.addWeighted(overlay, 0.85, frame, 0.15, 0, frame)

    # FPS indicator
    fps_clr = (0, 220, 80) if fps >= 20 else (0, 165, 255) if fps >= 10 else (0, 60, 220)
    cv2.putText(frame, f"FPS {fps:4.1f}", (12, 32),
                cv2.FONT_HERSHEY_SIMPLEX, 0.7, fps_clr, 2, cv2.LINE_AA)

    # Confidence level
    cv2.putText(frame, f"conf {conf_thresh:.2f}", (105, 32),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (180, 180, 180), 1, cv2.LINE_AA)

    # Title
    title = "HOME GUARDIAN  |  Pest Detector"
    (tw, _), _ = cv2.getTextSize(title, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 1)
    cv2.putText(frame, title, (w // 2 - tw // 2, 32),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 1, cv2.LINE_AA)

    # PAUSED badge
    if paused:
        cv2.putText(frame, "PAUSED", (w - 100, 32),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0, 165, 255), 2, cv2.LINE_AA)

    # REC indicator
    if recording:
        cv2.circle(frame, (w - 22, 25), 9, (0, 0, 220), -1)
        cv2.putText(frame, "REC", (w - 58, 32),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 0, 220), 2, cv2.LINE_AA)

    # Bottom bar with counts
    active = {k: v for k, v in counts.items() if v > 0}
    if active:
        overlay2 = frame.copy()
        cv2.rectangle(overlay2, (0, h - 42), (w, h), (10, 12, 16), -1)
        cv2.addWeighted(overlay2, 0.8, frame, 0.2, 0, frame)
        x = 12
        for cls_name, count in active.items():
            color = PALETTE.get(cls_name, DEFAULT_COLOR)
            txt = f"{cls_name}: {count}"
            cv2.putText(frame, txt, (x, h - 14),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.62, color, 2, cv2.LINE_AA)
            x += len(txt) * 13 + 20

    # Controls hint
    hint = "Q=quit  S=screenshot  R=record  P=pause  +/-=confidence"
    (hw, _), _ = cv2.getTextSize(hint, cv2.FONT_HERSHEY_SIMPLEX, 0.38, 1)
    cv2.putText(frame, hint, (w // 2 - hw // 2, h - (52 if active else 10)),
                cv2.FONT_HERSHEY_SIMPLEX, 0.38, (80, 80, 80), 1, cv2.LINE_AA)


def run(model_path, source, conf, iou, img_size, save_dir):
    try:
        from ultralytics import YOLO
    except ImportError:
        print("ERROR: ultralytics not installed.")
        print("  Run: pip install ultralytics")
        sys.exit(1)

    # Load model
    print(f"\n  Loading model : {model_path}")
    if not Path(model_path).exists():
        print(f"  ERROR: model file not found — {model_path}")
        print("  Update DEFAULT_MODEL at the top of this script.")
        sys.exit(1)

    model = YOLO(model_path)
    names = model.names
    print(f"  Classes       : {list(names.values())}")
    print(f"  Confidence    : {conf}")
    print(f"  Source        : {source}")
    print(f"  Image size    : {img_size}×{img_size}")
    print()

    # Open video source
    src = int(source) if str(source).isdigit() else source
    cap = cv2.VideoCapture(src)
    if not cap.isOpened():
        print(f"  ERROR: Cannot open source '{source}'")
        print("  For webcam use --source 0  |  For file use --source path/to/video.mp4")
        sys.exit(1)

    cap_w   = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    cap_h   = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    cap_fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    print(f"  Resolution    : {cap_w}×{cap_h} @ {cap_fps:.0f} fps")
    print(f"  Controls      : Q=quit  S=screenshot  R=record  P=pause  +/-=conf\n")

    save_path = Path(save_dir)
    save_path.mkdir(parents=True, exist_ok=True)

    # State
    conf_thresh = conf
    fps_buf     = deque(maxlen=30)
    paused      = False
    recording   = False
    writer      = None
    frames      = 0
    t_prev      = time.perf_counter()
    last_frame  = None

    while True:
        if not paused:
            ret, frame = cap.read()
            if not ret:
                print("  Stream ended or camera disconnected.")
                break
            last_frame = frame.copy()
            frames += 1
        else:
            if last_frame is None:
                continue
            frame = last_frame.copy()

        # Inference
        if not paused:
            results = model.predict(
                source  = frame,
                imgsz   = img_size,
                conf    = conf_thresh,
                iou     = iou,
                verbose = False,
            )
            result = results[0]
        else:
            result = None

        # Draw detections
        counts = defaultdict(int)
        if result is not None:
            for box in result.boxes:
                cls_id   = int(box.cls)
                cls_name = names[cls_id]
                conf_val = float(box.conf)
                x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
                color = PALETTE.get(cls_name, DEFAULT_COLOR)
                draw_box(frame, x1, y1, x2, y2, cls_name, conf_val, color)
                counts[cls_name] += 1

        # FPS
        now = time.perf_counter()
        fps_buf.append(1.0 / max(now - t_prev, 1e-6))
        t_prev = now
        fps = float(np.mean(fps_buf))

        # HUD
        draw_hud(frame, fps, conf_thresh, dict(counts), paused, recording)

        # Display
        cv2.imshow("Home Guardian — Pest Detector", frame)

        # Record
        if recording and writer is not None:
            writer.write(frame)

        # Keyboard
        key = cv2.waitKey(1) & 0xFF
        if key in (ord('q'), 27):
            break
        elif key == ord('s'):
            ts   = datetime.now().strftime('%Y%m%d_%H%M%S')
            fp   = save_path / f"detect_{ts}.jpg"
            cv2.imwrite(str(fp), frame)
            print(f"  Screenshot → {fp}")
        elif key == ord('r'):
            if not recording:
                ts     = datetime.now().strftime('%Y%m%d_%H%M%S')
                vp     = save_path / f"recording_{ts}.mp4"
                fourcc = cv2.VideoWriter_fourcc(*'mp4v')
                writer = cv2.VideoWriter(str(vp), fourcc, cap_fps, (cap_w, cap_h))
                recording = True
                print(f"  Recording → {vp}")
            else:
                recording = False
                if writer:
                    writer.release()
                    writer = None
                print("  Recording stopped")
        elif key == ord('p'):
            paused = not paused
            print(f"  {'Paused' if paused else 'Resumed'}")
        elif key in (ord('+'), ord('=')):
            conf_thresh = min(0.95, round(conf_thresh + 0.05, 2))
            print(f"  Confidence → {conf_thresh:.2f}")
        elif key == ord('-'):
            conf_thresh = max(0.05, round(conf_thresh - 0.05, 2))
            print(f"  Confidence → {conf_thresh:.2f}")

    # Cleanup
    cap.release()
    if writer:
        writer.release()
    cv2.destroyAllWindows()
    print(f"\n  Done. Frames processed: {frames}")


def main():
    ap = argparse.ArgumentParser(
        description='Home Guardian — Real-Time Pest Detector',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    ap.add_argument('--model',    default=DEFAULT_MODEL,
                    help=f'Path to best.pt weights (default: {DEFAULT_MODEL})')
    ap.add_argument('--source',   default='0',
                    help='Camera index, video file path, or RTSP URL (default: 0)')
    ap.add_argument('--conf',     default=DEFAULT_CONF,    type=float,
                    help=f'Confidence threshold (default: {DEFAULT_CONF})')
    ap.add_argument('--iou',      default=DEFAULT_IOU,     type=float,
                    help=f'NMS IoU threshold (default: {DEFAULT_IOU})')
    ap.add_argument('--imgsz',    default=DEFAULT_IMG_SIZE, type=int,
                    help=f'Inference image size (default: {DEFAULT_IMG_SIZE})')
    ap.add_argument('--save-dir', default=DEFAULT_SAVE_DIR,
                    help=f'Folder for screenshots and recordings (default: {DEFAULT_SAVE_DIR})')
    args = ap.parse_args()

    run(
        model_path = args.model,
        source     = args.source,
        conf       = args.conf,
        iou        = args.iou,
        img_size   = args.imgsz,
        save_dir   = args.save_dir,
    )


if __name__ == '__main__':
    main()
