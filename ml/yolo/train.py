#!/usr/bin/env python3
"""
Train YOLOv8n tile detector and export to TFLite.

Usage:
  pip install ultralytics
  python ml/yolo/train.py
  python ml/yolo/train.py --epochs 100 --imgsz 640
"""

import argparse
import shutil
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
DATASET_DIR = BASE_DIR / "dataset"
OUTPUT_DIR = BASE_DIR.parent / "output"


def train(epochs: int, imgsz: int, batch: int):
    from ultralytics import YOLO

    data_yaml = DATASET_DIR / "data.yaml"
    if not data_yaml.exists():
        print("Dataset not found. Run generate_synthetic.py first.")
        return

    # Train YOLOv8n (nano - smallest, fastest)
    model = YOLO("yolov8n.pt")
    results = model.train(
        data=str(data_yaml),
        epochs=epochs,
        imgsz=imgsz,
        batch=batch,
        device="cpu",  # Use "0" for GPU
        project=str(BASE_DIR / "runs"),
        name="tile_detector",
        exist_ok=True,
        patience=20,
        save=True,
        plots=True,
    )

    # Export to TFLite
    best_model_path = BASE_DIR / "runs" / "tile_detector" / "weights" / "best.pt"
    if not best_model_path.exists():
        print(f"Best model not found at {best_model_path}")
        return

    print("\n=== Exporting to TFLite ===")
    best_model = YOLO(str(best_model_path))
    best_model.export(format="tflite", imgsz=imgsz)

    # Copy outputs
    OUTPUT_DIR.mkdir(exist_ok=True)

    # Find the exported tflite file
    tflite_src = best_model_path.with_suffix(".tflite")
    if not tflite_src.exists():
        # ultralytics might put it in a different location
        export_dir = best_model_path.parent
        tflite_candidates = list(export_dir.glob("*.tflite")) + list(
            export_dir.parent.glob("**/*.tflite")
        )
        if tflite_candidates:
            tflite_src = tflite_candidates[0]
        else:
            print("TFLite export file not found")
            return

    tflite_dst = OUTPUT_DIR / "tile_detector.tflite"
    shutil.copy2(tflite_src, tflite_dst)
    print(f"TFLite model saved: {tflite_dst}")
    print(f"Size: {tflite_dst.stat().st_size / 1024 / 1024:.1f} MB")

    # Copy to Flutter assets
    flutter_assets = BASE_DIR.parent.parent / "mobile" / "assets" / "ml"
    flutter_assets.mkdir(parents=True, exist_ok=True)
    shutil.copy2(tflite_dst, flutter_assets / "tile_detector.tflite")
    print(f"Copied to Flutter assets: {flutter_assets}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=int, default=50)
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--batch", type=int, default=16)
    args = parser.parse_args()
    train(args.epochs, args.imgsz, args.batch)
