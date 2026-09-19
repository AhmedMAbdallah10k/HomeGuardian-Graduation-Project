import tensorflow as tf
import tensorflow_hub as hub
import numpy as np
import sounddevice as sd

# Configuration
SAMPLE_RATE = 16000
CHUNK_SECONDS = 2
THRESHOLD = 0.15
CRY_INDICES = [19, 20]

print("Loading YAMNet...")
yamnet = hub.load("https://tfhub.dev/google/yamnet/1")
print("Model ready.")
print("Listening...\n")


def detect_cry(audio_chunk):
    # Convert int16 audio to float32 in [-1,1]
    audio_float = audio_chunk.flatten().astype(np.float32) / 32768.0

    scores, embeddings, spectrogram = yamnet(audio_float)

    mean_scores = tf.reduce_mean(scores, axis=0).numpy()

    cry_score = max(mean_scores[i] for i in CRY_INDICES)

    return cry_score


try:
    while True:
        audio_chunk = sd.rec(
            int(CHUNK_SECONDS * SAMPLE_RATE),
            samplerate=SAMPLE_RATE,
            channels=1,
            dtype='int16'
        )
        sd.wait()

        cry_score = detect_cry(audio_chunk)

        if cry_score > THRESHOLD:
            print(f"🔴 CRYING DETECTED  (score: {cry_score:.3f})")
        else:
            print(f"No cry  (score: {cry_score:.3f})")

except KeyboardInterrupt:
    print("\nStopped.")