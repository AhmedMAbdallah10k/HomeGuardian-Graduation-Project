# How to View Saved Images

## Method 1: Direct File Access (Easiest)

The images are saved in the `server/uploads/` folder on your computer.

1. **Navigate to the folder**:
   ```
   D:\flutter_application_1\flutter_application_1\server\uploads\
   ```

2. **Open the folder**:
   - Open File Explorer
   - Go to: `D:\flutter_application_1\flutter_application_1\server\uploads\`
   - You'll see all saved images there (named like `user_1_profile_20250101_120000.jpg`)

3. **Double-click any image** to open it with your default image viewer

## Method 2: Via Web Browser (If Server is Running)

If your FastAPI server is running, you can view images directly in your browser:

1. **Find the image filename** from the database (see Method 3 below)

2. **Open in browser**:
   ```
   http://10.90.186.34:3000/uploads/user_1_profile_20250101_120000.jpg
   ```
   (Replace with your actual image filename)

3. **Or from your phone's browser**:
   ```
   http://10.90.186.34:3000/uploads/user_1_profile_20250101_120000.jpg
   ```

## Method 3: Check Database for Image Filenames

1. **Open PostgreSQL** (pgAdmin or psql)

2. **Run this query**:
   ```sql
   SELECT id, name, profile_image, created_at 
   FROM users 
   ORDER BY created_at DESC;
   ```

3. **The `profile_image` column** will show the filename like:
   - `uploads/user_1_profile_20250101_120000.jpg`

4. **Then use Method 1 or 2** to view the image

## Method 4: List All Images via Terminal

Open a terminal in the `server` folder and run:

**Windows (PowerShell)**:
```powershell
cd server\uploads
dir
```

**Windows (CMD)**:
```cmd
cd server\uploads
dir
```

**Mac/Linux**:
```bash
cd server/uploads
ls -la
```

## Quick Access Shortcut

1. Open File Explorer
2. Press `Win + R` (Windows) or navigate to the path
3. Type or paste: `D:\flutter_application_1\flutter_application_1\server\uploads`
4. Press Enter

## Image Naming Convention

Images are named with this pattern:
```
user_{user_id}_profile_{timestamp}.jpg
```

Example:
- `user_1_profile_20250101_143022.jpg`
  - User ID: 1
  - Timestamp: January 1, 2025 at 14:30:22

## Troubleshooting

**If you don't see the `uploads` folder:**
- Make sure you've run the FastAPI server at least once
- The folder is created automatically when the server starts
- Check: `D:\flutter_application_1\flutter_application_1\server\uploads\`

**If images aren't showing in browser:**
- Make sure the FastAPI server is running
- Check that the image filename matches exactly (case-sensitive)
- Try accessing: `http://10.90.186.34:3000/api/health` first to verify server is running
