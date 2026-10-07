"""Regenerate native parity references only after reviewing a model change.

Run with a Python environment containing tensorflow and numpy. These constant
tensors validate runtime equivalence, not the model's real-photo accuracy.
"""
import hashlib
import json
from pathlib import Path

import numpy as np
import tensorflow as tf

root = Path(__file__).resolve().parents[2]
model = root / "assets/ml/tile_classifier.tflite"
interpreter = tf.lite.Interpreter(model_path=str(model), num_threads=1)
interpreter.allocate_tensors()
input_spec = interpreter.get_input_details()[0]
output_spec = interpreter.get_output_details()[0]
cases = []
for name, value in [("black", -1.0), ("midgray", 0.0), ("white", 1.0)]:
    interpreter.set_tensor(input_spec["index"], np.full(input_spec["shape"], value, dtype=np.float32))
    interpreter.invoke()
    cases.append({"id": name, "input_fill": value, "scores": interpreter.get_tensor(output_spec["index"]).reshape(-1).tolist()})
output = root / "test/fixtures/web_recognition_eval_v1.json"
output.write_text(json.dumps({
    "version": 1,
    "model_sha256": hashlib.sha256(model.read_bytes()).hexdigest(),
    "description": "Native TensorFlow Lite reference tensors; runtime parity only, not recognition accuracy.",
    "absolute_tolerance": 0.0001,
    "cases": cases,
}, indent=2) + "\n")
