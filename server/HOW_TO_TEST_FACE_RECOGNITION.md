# How to Test Face Recognition

## ✅ Status: DeepFace is Working!

Your face recognition system is ready to test using DeepFace.

## Quick Test

### Step 1: Check if system is ready
```bash
cd server
python quick_test_face.py
```

Should show: `[OK] DeepFace library available - using DeepFace`

### Step 2: Enroll faces (add people to database)

1. **Create folder structure:**
   ```
   server/
     known_faces/
       Ahmed/
         image1.jpg
         image2.jpg
       Arwa/
         image1.jpg
   ```

2. **Add face images:**
   - Create a folder for each person in `known_faces/`
   - Add 1-3 clear face images per person
   - Images should show the person's face clearly

3. **You can use existing images:**
   ```bash
   # Copy existing user images to test
   mkdir known_faces\Ahmed
   copy uploads\user_3_profile_20251118_022159.jpg known_faces\Ahmed\
   ```

### Step 3: Test recognition

```bash
python quick_test_face.py uploads/user_3_profile_20251118_022159.jpg
```

Or test with any image:
```bash
python quick_test_face.py path/to/test_image.jpg
```

## Expected Results

### ✅ Success:
```
[SUCCESS] ✅ FACE RECOGNIZED!
  Name: Ahmed
  Confidence: 95.2%
  Distance: 0.0480
```

### ❌ Not recognized:
```
[INFO] ❌ Face not recognized
  Closest: Ahmed (distance: 0.6500, threshold: 0.4000)
```

## Using DeepFace Stream (Real-time)

You can also test with live camera:

```bash
python deepface_stream.py
```

This will:
- Open your webcam
- Show real-time face recognition
- Display names when faces are recognized

## Troubleshooting

1. **"No face detected"** → Image doesn't have a clear face
2. **"Face not recognized"** → Person not enrolled or image quality poor
3. **"Database directory not found"** → Run test once to create it

## Next Steps

Once testing works, we can integrate it into your Flutter app!

