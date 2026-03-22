#!/usr/bin/env python3
"""
Convert YOLOv8n ONNX model to TFLite.

Run this on Google Colab or an environment with compatible TensorFlow:

  pip install ultralytics tensorflow onnx
  python ml/yolo/convert_to_tflite.py

Or use the Colab approach:
  1. Upload best.pt to Colab
  2. Run: from ultralytics import YOLO; YOLO('best.pt').export(format='tflite', imgsz=320)
  3. Download the .tflite file
"""

import shutil
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
WEIGHTS_DIR = BASE_DIR / "runs" / "tile_detector" / "weights"
OUTPUT_DIR = BASE_DIR.parent / "output"


def convert():
    from ultralytics import YOLO

    best_pt = WEIGHTS_DIR / "best.pt"
    if not best_pt.exists():
        print(f"Model not found: {best_pt}")
        return

    print("Loading model...")
    model = YOLO(str(best_pt))

    print("Exporting to TFLite (imgsz=320)...")
    model.export(format="tflite", imgsz=320)

    # Find and copy the tflite file
    tflite_candidates = list(WEIGHTS_DIR.glob("**/*.tflite"))
    if not tflite_candidates:
        print("TFLite file not found after export")
        return

    tflite_src = tflite_candidates[0]
    OUTPUT_DIR.mkdir(exist_ok=True)
    tflite_dst = OUTPUT_DIR / "tile_detector.tflite"
    shutil.copy2(tflite_src, tflite_dst)
    print(f"Saved: {tflite_dst} ({tflite_dst.stat().st_size / 1024 / 1024:.1f} MB)")

    # Copy to Flutter assets
    flutter_assets = BASE_DIR.parent.parent / "mobile" / "assets" / "ml"
    flutter_assets.mkdir(parents=True, exist_ok=True)
    shutil.copy2(tflite_src, flutter_assets / "tile_detector.tflite")
    print(f"Copied to: {flutter_assets}")


if __name__ == "__main__":
    convert()
