# Troubleshooting: "Server isn't running" Error

## 🔍 The Problem
Your friend's phone can't connect to the FastAPI server. This usually means:
1. The server isn't running on your computer
2. The IP address in the code is wrong
3. Both devices aren't on the same network
4. Firewall is blocking the connection

---

## ✅ Solution Steps

### Step 1: Make Sure the Server is Running

**On YOUR computer (where the server should run):**

1. Open terminal/command prompt
2. Navigate to the server folder:
   ```bash
   cd D:\flutter_application_1\flutter_application_1\server
   ```

3. Start the FastAPI server:
   ```bash
   python main.py
   ```

4. You should see:
   ```
   Users table ready
   INFO:     Uvicorn running on http://0.0.0.0:3000
   ```

5. **Keep this terminal window open** - the server must stay running!

---

### Step 2: Find Your Computer's IP Address

**On YOUR computer (where server is running):**

**Windows:**
```bash
ipconfig
```
Look for "Wireless LAN adapter Wi-Fi" → "IPv4 Address"
Example: `10.90.186.34`

**Mac/Linux:**
```bash
ifconfig
# or
ip addr
```

---

### Step 3: Update the IP Address in Flutter Code

**The IP address in the code must match YOUR computer's IP (where server is running).**

**Files to update:**
1. `lib/pages/scan_face_page.dart` - Line ~36
2. Check if there are other files with the API URL

**Current code:**
```dart
static const String apiBaseUrl = 'http://10.90.186.34:3000';
```

**Change to YOUR computer's IP:**
```dart
static const String apiBaseUrl = 'http://YOUR_IP_HERE:3000';
```

**Example:**
If your IP is `192.168.1.100`, change to:
```dart
static const String apiBaseUrl = 'http://192.168.1.100:3000';
```

---

### Step 4: Make Sure Both Devices Are on Same Network

**Important:**
- Your computer (running server) and your friend's phone must be on the **same Wi-Fi network**
- They cannot be on different networks
- Mobile data won't work - must use Wi-Fi

**Check:**
- Your computer: Connected to Wi-Fi network "HomeWiFi"
- Friend's phone: Connected to same Wi-Fi network "HomeWiFi"

---

### Step 5: Test the Connection

**On YOUR computer's browser:**
1. Open browser
2. Go to: `http://YOUR_IP:3000/api/health`
   Example: `http://10.90.186.34:3000/api/health`
3. You should see: `{"status":"OK","message":"Server is running"}`

**On your friend's phone browser:**
1. Open phone browser
2. Go to: `http://YOUR_IP:3000/api/health`
   Example: `http://10.90.186.34:3000/api/health`
3. You should see: `{"status":"OK","message":"Server is running"}`

**If this works, the Flutter app should work too!**

---

### Step 6: Check Windows Firewall

**If connection still doesn't work:**

1. Open Windows Defender Firewall
2. Click "Allow an app or feature through Windows Firewall"
3. Find "Python" and check both "Private" and "Public"
4. If Python isn't listed:
   - Click "Allow another app"
   - Browse to Python executable (usually `C:\Python3x\python.exe`)
   - Add it and check both boxes

**OR allow port 3000:**
1. Open Windows Defender Firewall → Advanced settings
2. Inbound Rules → New Rule
3. Port → TCP → Port 3000
4. Allow connection → Apply to all profiles

---

## 🎯 Quick Checklist

Before your friend runs the app:

- [ ] Server is running on YOUR computer (`python main.py`)
- [ ] Server shows "Uvicorn running on http://0.0.0.0:3000"
- [ ] You know YOUR computer's IP address
- [ ] Flutter code has YOUR computer's IP (not your friend's)
- [ ] Both devices on same Wi-Fi network
- [ ] Test `http://YOUR_IP:3000/api/health` works on phone browser
- [ ] Windows Firewall allows Python/port 3000

---

## 🔄 Common Scenarios

### Scenario 1: Friend is at Different Location
**Problem:** Friend is at their home, you're at yours
**Solution:** 
- Option A: Friend must come to your location (same Wi-Fi)
- Option B: Deploy server to cloud (Heroku, AWS, etc.)
- Option C: Use ngrok to create public URL (temporary solution)

### Scenario 2: IP Address Changed
**Problem:** Your computer's IP changed (common with DHCP)
**Solution:** 
- Check IP again with `ipconfig`
- Update Flutter code with new IP
- Or set static IP on your computer

### Scenario 3: Server Crashed
**Problem:** Server was running but stopped
**Solution:**
- Check terminal for errors
- Restart server: `python main.py`
- Check if port 3000 is already in use

---

## 🧪 Test Commands

**On YOUR computer:**
```bash
# Check if server is running
netstat -an | findstr :3000

# Should show something like:
# TCP    0.0.0.0:3000    0.0.0.0:0    LISTENING
```

**On friend's phone (browser):**
```
http://YOUR_IP:3000/api/health
```

---

## 📱 Alternative: Use ngrok (For Testing Across Networks)

If you want to test from different locations:

1. **Install ngrok**: https://ngrok.com/
2. **Start your server**: `python main.py`
3. **In another terminal, run**:
   ```bash
   ngrok http 3000
   ```
4. **Copy the ngrok URL** (e.g., `https://abc123.ngrok.io`)
5. **Update Flutter code**:
   ```dart
   static const String apiBaseUrl = 'https://abc123.ngrok.io';
   ```

**Note:** ngrok URL changes each time you restart it (free version)

---

## 💡 Best Solution for Sharing

**For production/sharing with friends:**

1. **Deploy to cloud** (Heroku, Railway, Render, etc.)
2. **Get permanent URL** (e.g., `https://your-app.herokuapp.com`)
3. **Update Flutter code** with cloud URL
4. **Works from anywhere!**

---

## ❓ Still Not Working?

**Check these:**
1. Is the server actually running? (Check terminal)
2. What's the exact error message?
3. Can you access `http://YOUR_IP:3000/api/health` from YOUR computer's browser?
4. Can your friend access it from their phone's browser?
5. Are both devices on the same Wi-Fi?
6. What's your computer's current IP? (Run `ipconfig`)


