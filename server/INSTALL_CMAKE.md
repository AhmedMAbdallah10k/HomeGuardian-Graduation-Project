# How to Install CMake for face-recognition (Windows)

The `face-recognition` library requires `dlib`, which needs CMake to build.

## Option 1: Install CMake (Recommended for face-recognition)

### Steps:
1. **Download CMake:**
   - Go to: https://cmake.org/download/
   - Download: "Windows x64 Installer" (cmake-x.x.x-windows-x86_64.msi)

2. **Install CMake:**
   - Run the installer
   - **IMPORTANT:** During installation, check "Add CMake to system PATH"
   - Complete the installation

3. **Verify Installation:**
   ```bash
   cmake --version
   ```
   Should show: `cmake version x.x.x`

4. **Restart Terminal:**
   - Close and reopen your terminal/PowerShell

5. **Install face-recognition:**
   ```bash
   pip install face-recognition
   ```

## Option 2: Use Pre-built dlib Wheel (Easier)

If CMake installation is problematic, try installing a pre-built dlib:

```bash
pip install dlib-binary
pip install face-recognition
```

## Option 3: Use DeepFace Instead (No CMake Needed)

Since you already have `deepface_stream.py`, you can use DeepFace which doesn't require CMake:

```bash
pip install deepface
python test_deepface_only.py
```

DeepFace is already installed and working! ✅

## Recommendation

**Use DeepFace** - it's already installed and doesn't require CMake. Your `deepface_stream.py` file uses DeepFace, so test that system first.

