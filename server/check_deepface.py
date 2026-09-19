"""Quick check if DeepFace is working"""
try:
    from deepface import DeepFace
    print("[OK] DeepFace imported successfully!")
    print("DeepFace is ready to use")
except ImportError as e:
    print(f"[ERROR] DeepFace import failed: {e}")
    print("\nTry installing:")
    print("  pip install deepface")
except Exception as e:
    print(f"[ERROR] DeepFace error: {e}")
    print("\nDeepFace might need additional dependencies")

