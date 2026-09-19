"""
Smart Pet Care System - AI Server v4

Features:
  - YOLOv8 detection of cat/dog
  - Receives images from CAM, sends verdicts to main ESP32
  - Dashboard with live feed + system status + event log
  - Live feed tries MJPEG stream first, falls back to /snapshot polling

Setup:
    pip install fastapi uvicorn ultralytics opencv-python requests

Run:
    python pet_server_v4.py

Open: http://localhost:8000/dashboard
"""

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, HTMLResponse
from ultralytics import YOLO
import requests
import numpy as np
import cv2
import uvicorn
from datetime import datetime
from collections import deque

# ==================== CONFIG ====================
ESP32_MAIN_IP = "192.168.8.191"   # <-- CHANGE to main ESP32 IP
ESP32_CAM_IP  = "192.168.8.103"   # <-- CHANGE to CAM IP
MODEL_PATH    = r"D:\WORKSPACE\Graduation_Project\HOMEGUARDIAN\MODES\Pet Mode\Pet_station\yolov8n.pt"
TARGET_CLASSES = {15: "cat", 16: "dog"}
CONFIDENCE_THRESHOLD = 0.4
EATING_REGION_BOTTOM = 0.6   # bbox bottom > 60% of frame height = "eating" heuristic

app = FastAPI()
model = YOLO(MODEL_PATH)
print(f"[{datetime.now()}] Model loaded: {MODEL_PATH}")

event_history = deque(maxlen=30)
last_detection = {"detected": False, "eating": False, "class": None, "time": None}


# ==================== ENDPOINTS ====================
@app.post("/analyze")
async def analyze(request: Request):
    """Receives JPEG from ESP32-CAM, runs YOLO, sends verdict to main ESP32."""
    body = await request.body()
    img_array = np.frombuffer(body, dtype=np.uint8)
    img = cv2.imdecode(img_array, cv2.IMREAD_COLOR)
    if img is None:
        return JSONResponse({"error": "bad image"}, status_code=400)

    results = model(img, verbose=False)[0]
    detected = False
    eating = False
    best_class = None

    h = img.shape[0]
    for box in results.boxes:
        cls_id = int(box.cls[0])
        conf = float(box.conf[0])
        if cls_id in TARGET_CLASSES and conf >= CONFIDENCE_THRESHOLD:
            detected = True
            best_class = TARGET_CLASSES[cls_id]
            y_bottom = float(box.xyxy[0][3])
            if y_bottom / h > EATING_REGION_BOTTOM:
                eating = True
            print(f"[{datetime.now()}] Detected {best_class} "
                  f"conf={conf:.2f} eating={eating}")

    annotated = results.plot()
    cv2.imwrite("last_frame.jpg", annotated)

    last_detection.update({
        "detected": detected,
        "eating": eating,
        "class": best_class,
        "time": datetime.now().strftime("%H:%M:%S"),
    })

    verdict = {"detected": detected, "eating": eating, "class": best_class}
    try:
        r = requests.post(f"http://{ESP32_MAIN_IP}/ai_result", json=verdict, timeout=3)
        print(f"[{datetime.now()}] Verdict sent: {verdict} -> {r.status_code}")
    except Exception as e:
        print(f"[{datetime.now()}] Failed to send verdict: {e}")

    return verdict


@app.post("/event")
async def event(request: Request):
    data = await request.json()
    timestamp = datetime.now().strftime("%H:%M:%S")
    event_str = f"{timestamp} | {data.get('event','?')} | state={data.get('state','?')}"
    print(f"[{datetime.now()}] EVENT: {data}")
    event_history.appendleft(event_str)
    with open("events.log", "a") as f:
        f.write(f"{datetime.now()},{data.get('event','?')},{data.get('state','?')}\n")
    return {"ok": True}


@app.get("/status")
def status():
    return {
        "last_detection": last_detection,
        "events": list(event_history),
        "cam_ip": ESP32_CAM_IP,
        "main_ip": ESP32_MAIN_IP,
    }


@app.get("/dashboard", response_class=HTMLResponse)
def dashboard():
    html = f"""
<!DOCTYPE html>
<html>
<head>
    <title>Pet Care Dashboard</title>
    <meta charset="utf-8">
    <style>
        body {{
            font-family: 'Segoe UI', Arial, sans-serif;
            background: #1a1a1a;
            color: #e0e0e0;
            margin: 0;
            padding: 20px;
        }}
        h1 {{ color: #4caf50; text-align: center; }}
        .container {{
            display: grid;
            grid-template-columns: 1.2fr 1fr;
            gap: 20px;
            max-width: 1400px;
            margin: 0 auto;
        }}
        .card {{
            background: #2d2d2d;
            border-radius: 12px;
            padding: 20px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.4);
        }}
        .card h2 {{ margin-top: 0; color: #2196f3; }}
        #liveFeed {{
            width: 100%;
            border-radius: 8px;
            background: #000;
            min-height: 360px;
            object-fit: contain;
        }}
        .feed-status {{
            margin-top: 8px;
            font-size: 12px;
            color: #888;
            text-align: center;
        }}
        .status-row {{
            padding: 10px 0;
            border-bottom: 1px solid #444;
            display: flex;
            justify-content: space-between;
        }}
        .status-row:last-child {{ border-bottom: none; }}
        .label {{ color: #aaa; }}
        .value {{ color: #fff; font-weight: bold; }}
        .ok {{ color: #4caf50; }}
        .warn {{ color: #ff9800; }}
        .err {{ color: #f44336; }}
        .events {{
            max-height: 350px;
            overflow-y: auto;
            font-family: 'Consolas', monospace;
            font-size: 13px;
        }}
        .event-item {{
            padding: 8px 12px;
            margin: 4px 0;
            background: #1e1e1e;
            border-left: 3px solid #2196f3;
            border-radius: 3px;
        }}
        .event-item.dispense {{ border-left-color: #4caf50; }}
        .event-item.cancel {{ border-left-color: #f44336; }}
        .event-item.eating {{ border-left-color: #4caf50; }}
        .event-item.not_eating {{ border-left-color: #ff9800; }}
        .footer {{
            text-align: center;
            margin-top: 20px;
            color: #666;
            font-size: 12px;
        }}
        .btn {{
            display: inline-block;
            padding: 10px 20px;
            background: #4caf50;
            color: white;
            text-decoration: none;
            border-radius: 6px;
            margin-top: 10px;
        }}
        .btn:hover {{ background: #45a049; }}
    </style>
</head>
<body>
    <h1>🐾 Pet Care Dashboard</h1>
    <div class="container">
        <div class="card">
            <h2>📷 Live Camera Feed</h2>
            <img id="liveFeed" alt="Loading...">
            <div class="feed-status" id="feedStatus">Connecting to camera...</div>
            <div style="text-align:center;">
                <a class="btn" href="http://{ESP32_MAIN_IP}/test_feed" target="_blank">Trigger Test Feed</a>
            </div>
        </div>

        <div class="card">
            <h2>📊 System Status</h2>
            <div id="status">
                <div class="status-row">
                    <span class="label">Last Detection:</span>
                    <span class="value" id="detected">-</span>
                </div>
                <div class="status-row">
                    <span class="label">Eating:</span>
                    <span class="value" id="eating">-</span>
                </div>
                <div class="status-row">
                    <span class="label">Last Check:</span>
                    <span class="value" id="lasttime">-</span>
                </div>
                <div class="status-row">
                    <span class="label">CAM IP:</span>
                    <span class="value">{ESP32_CAM_IP}</span>
                </div>
                <div class="status-row">
                    <span class="label">Main ESP32:</span>
                    <span class="value">{ESP32_MAIN_IP}</span>
                </div>
            </div>

            <h2 style="margin-top: 25px;">📝 Recent Events</h2>
            <div class="events" id="events">Loading...</div>
        </div>
    </div>

    <div class="footer">
        Auto-refresh every 2 seconds | Smart Pet Care System v4
    </div>

<script>
const CAM_IP = "{ESP32_CAM_IP}";
const STREAM_URL = `http://${{CAM_IP}}:81/stream`;
const SNAPSHOT_URL = `http://${{CAM_IP}}/snapshot`;

const feedImg = document.getElementById('liveFeed');
const feedStatus = document.getElementById('feedStatus');

let usingSnapshot = false;
let snapshotInterval = null;

function startStream() {{
    feedStatus.textContent = "Trying live stream...";
    feedImg.src = STREAM_URL;

    const timeout = setTimeout(() => {{
        if (!feedImg.complete || feedImg.naturalWidth === 0) {{
            console.log("Stream timed out, falling back to snapshot polling");
            switchToSnapshot();
        }}
    }}, 4000);

    feedImg.onload = () => {{
        clearTimeout(timeout);
        if (!usingSnapshot) {{
            feedStatus.textContent = "Live stream active";
        }}
    }};

    feedImg.onerror = () => {{
        clearTimeout(timeout);
        console.log("Stream error, falling back to snapshot polling");
        switchToSnapshot();
    }};
}}

function switchToSnapshot() {{
    if (usingSnapshot) return;
    usingSnapshot = true;
    feedStatus.textContent = "Live stream unavailable - using 1s snapshot polling";
    refreshSnapshot();
    snapshotInterval = setInterval(refreshSnapshot, 1000);
}}

function refreshSnapshot() {{
    feedImg.src = SNAPSHOT_URL + "?t=" + Date.now();
}}

async function refreshStatus() {{
    try {{
        const res = await fetch('/status');
        const data = await res.json();

        const det = data.last_detection;
        const detEl = document.getElementById('detected');
        detEl.textContent = det.detected ? `${{det.class || 'pet'}} ✓` : 'No pet';
        detEl.className = 'value ' + (det.detected ? 'ok' : 'warn');

        const eatEl = document.getElementById('eating');
        eatEl.textContent = det.eating ? 'Yes ✓' : 'No';
        eatEl.className = 'value ' + (det.eating ? 'ok' : 'warn');

        document.getElementById('lasttime').textContent = det.time || 'Never';

        const eventsDiv = document.getElementById('events');
        if (data.events.length === 0) {{
            eventsDiv.innerHTML = '<div class="event-item">No events yet</div>';
        }} else {{
            eventsDiv.innerHTML = data.events.map(e => {{
                let cls = '';
                if (e.includes('dispense')) cls = 'dispense';
                else if (e.includes('cancel')) cls = 'cancel';
                else if (e.includes('not_eating')) cls = 'not_eating';
                else if (e.includes('eating')) cls = 'eating';
                return `<div class="event-item ${{cls}}">${{e}}</div>`;
            }}).join('');
        }}
    }} catch (e) {{
        console.error('Refresh failed:', e);
    }}
}}

startStream();
refreshStatus();
setInterval(refreshStatus, 2000);
</script>
</body>
</html>
    """
    return html


@app.get("/")
def root():
    return {"status": "Pet Care AI Server v4 running",
            "dashboard": "/dashboard",
            "main_esp32": ESP32_MAIN_IP,
            "cam": ESP32_CAM_IP}


# ==================== RUN ====================
if __name__ == "__main__":
    print(f"\n{'='*55}")
    print(f"  Dashboard: http://localhost:8000/dashboard")
    print(f"  Status:    http://localhost:8000/status")
    print(f"  Main ESP:  http://{ESP32_MAIN_IP}/")
    print(f"  CAM:       http://{ESP32_CAM_IP}/  (or :81/stream)")
    print(f"{'='*55}\n")
    uvicorn.run(app, host="0.0.0.0", port=8000)
