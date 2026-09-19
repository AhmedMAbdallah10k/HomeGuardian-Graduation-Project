# Phone Setup Checklist ✅

## Your Current Configuration:
- **Your Computer's IP**: `10.90.186.34` ✅
- **Flutter App API URL**: `http://10.90.186.34:3000` ✅ (Already configured correctly!)
- **FastAPI Server**: Configured to accept connections from network ✅

## Step-by-Step Setup:

### 1. ✅ FastAPI Server Configuration
The server is already configured correctly in `server/main.py`:
- Host: `0.0.0.0` (accepts connections from any network interface)
- Port: `3000`
- CORS: Enabled for all origins

### 2. ✅ Flutter App Configuration
The app is already configured in `lib/pages/signup_page.dart`:
- API URL: `http://10.90.186.34:3000` ✅

### 3. ⚠️ Important: Make Sure Both Devices Are on Same Network
- Your computer and phone must be connected to the **same Wi-Fi network**
- Check your phone's Wi-Fi settings to confirm

### 4. 🔥 Windows Firewall Configuration
You may need to allow the connection through Windows Firewall:

**Option A: Allow Python through Firewall**
1. Open Windows Defender Firewall
2. Click "Allow an app or feature through Windows Firewall"
3. Find "Python" and check both "Private" and "Public"
4. If Python is not listed, click "Allow another app" and add Python

**Option B: Allow Port 3000**
1. Open Windows Defender Firewall
2. Click "Advanced settings"
3. Click "Inbound Rules" → "New Rule"
4. Select "Port" → Next
5. Select "TCP" and enter port `3000`
6. Allow the connection
7. Apply to all profiles

### 5. 🚀 Start the FastAPI Server
In the `server` folder, run:
```bash
cd server
python main.py
```

You should see:
```
Users table ready
INFO:     Uvicorn running on http://0.0.0.0:3000
```

### 6. 🧪 Test the Connection
Before testing on your phone, test from your computer's browser:
- Open: http://10.90.186.34:3000/api/health
- You should see: `{"status":"OK","message":"Server is running"}`

### 7. 📱 Test on Your Phone
1. Make sure your phone is on the same Wi-Fi network
2. Run your Flutter app on your phone
3. Go to Sign Up page
4. Enter your name
5. Click "Scan Face"
6. You should see a success message!

## Troubleshooting:

### ❌ Connection Error on Phone
- **Check**: Both devices on same Wi-Fi? ✅
- **Check**: Server running? (See step 5)
- **Check**: Firewall blocking? (See step 4)
- **Test**: Can you access http://10.90.186.34:3000/api/health from your phone's browser?

### ❌ "Connection refused" or "Connection timeout"
- Make sure the FastAPI server is running
- Check Windows Firewall settings
- Verify the IP address hasn't changed (run `ipconfig` again)

### ❌ IP Address Changed
If your computer's IP changes, update it in `lib/pages/signup_page.dart`:
```dart
static const String apiBaseUrl = 'http://YOUR_NEW_IP:3000';
```

## Quick Test Commands:

**Check if server is accessible from network:**
```bash
# From your phone's browser, try:
http://10.90.186.34:3000/api/health

# Or from another computer on same network:
curl http://10.90.186.34:3000/api/health
```

**Check your current IP (if it changes):**
```bash
ipconfig
# Look for "Wireless LAN adapter Wi-Fi" → "IPv4 Address"
```

