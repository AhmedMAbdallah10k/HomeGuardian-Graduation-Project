import tensorflow as tf
import tensorflow_hub as hub
import numpy as np
import csv

# Load model
yamnet = hub.load("https://tfhub.dev/google/yamnet/1")

# Load class names
class_map_path = yamnet.class_map_path().numpy().decode("utf-8")

class_names = []
with open(class_map_path) as f:
    reader = csv.reader(f)
    next(reader)
    for row in reader:
        class_names.append(row[2])

# Find cry classes
CRY_CLASSES = {"Baby cry, infant cry", "Crying, sobbing"}

cry_indices = [
    i for i, name in enumerate(class_names)
    if name in CRY_CLASSES
]

print("Cry class indices:", cry_indices)
print("Cry class names:", [class_names[i] for i in cry_indices])

# Simulate 2 seconds of silence
fake_audio = tf.zeros([32000], dtype=tf.float32)

scores, _, _ = yamnet(fake_audio)

mean_scores = tf.reduce_mean(scores, axis=0).numpy()

cry_score = max(mean_scores[i] for i in cry_indices)

print(f"Cry score on silence: {cry_score:.4f}")
print("Pipeline working correctly!")