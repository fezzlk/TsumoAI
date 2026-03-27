#!/usr/bin/env python3
"""
Train a MobileNetV2 tile classifier.

Data sources (merged):
  1. Local CSV dataset (tiles-resized/ + data.csv) — legacy Camerash
  2. GCS training data (training-data/index.json) — user uploads + public datasets

Outputs:
  - tile_classifier.tflite  (float16 quantized)
  - labels.txt

Usage:
  # Local only (legacy)
  python train.py --epochs 50

  # Include GCS data
  python train.py --epochs 50 --gcs-bucket correctdata

  # Cloud Build (GCS data + upload result)
  python train.py --gcs-bucket correctdata --upload
"""

import argparse
import csv
import io
import json
import os
import shutil
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models
from tensorflow.keras.applications import MobileNetV2
from tensorflow.keras.callbacks import EarlyStopping, ReduceLROnPlateau

# ──────────── Config ────────────

IMG_SIZE = 224
BATCH_SIZE = 32
DEFAULT_EPOCHS = 50
SEED = 42

BASE_DIR = Path(__file__).parent
TILES_DIR = BASE_DIR / "tiles-resized"
DATA_CSV = BASE_DIR / "data.csv"
LABEL_CSV = BASE_DIR / "label.csv"
OUTPUT_DIR = BASE_DIR / "output"

# All known tile codes → label names (superset)
TILE_CODE_TO_LABEL = {
    "1m": "characters-1", "2m": "characters-2", "3m": "characters-3",
    "4m": "characters-4", "5m": "characters-5", "6m": "characters-6",
    "7m": "characters-7", "8m": "characters-8", "9m": "characters-9",
    "1p": "dots-1", "2p": "dots-2", "3p": "dots-3",
    "4p": "dots-4", "5p": "dots-5", "6p": "dots-6",
    "7p": "dots-7", "8p": "dots-8", "9p": "dots-9",
    "1s": "bamboo-1", "2s": "bamboo-2", "3s": "bamboo-3",
    "4s": "bamboo-4", "5s": "bamboo-5", "6s": "bamboo-6",
    "7s": "bamboo-7", "8s": "bamboo-8", "9s": "bamboo-9",
    "E": "honors-east", "S": "honors-south", "W": "honors-west", "N": "honors-north",
    "C": "honors-red", "F": "honors-green", "P": "honors-white",
}


# ──────────── Data loading ────────────

def load_label_map() -> dict[int, str]:
    label_map = {}
    with open(LABEL_CSV, encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            label_map[int(row["label-index"])] = row["label-name"]
    return label_map


def load_local_dataset(label_to_idx: dict[str, int]) -> tuple[list, list]:
    """Load legacy CSV dataset (tiles-resized/)."""
    images, labels = [], []
    if not DATA_CSV.exists():
        return images, labels
    label_map = load_label_map()
    with open(DATA_CSV, encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            img_path = TILES_DIR / row["image-name"]
            if not img_path.exists():
                continue
            label_name = label_map.get(int(row["label"]))
            if label_name not in label_to_idx:
                continue
            img = tf.keras.utils.load_img(img_path, target_size=(IMG_SIZE, IMG_SIZE))
            images.append(tf.keras.utils.img_to_array(img))
            labels.append(label_to_idx[label_name])
    print(f"  Local CSV: {len(images)} images")
    return images, labels


def load_gcs_dataset(bucket_name: str, label_to_idx: dict[str, int]) -> tuple[list, list]:
    """Load training data from GCS index.json."""
    from google.cloud import storage
    client = storage.Client()
    bucket = client.bucket(bucket_name)

    # Load index
    index_blob = bucket.blob("training-data/index.json")
    if not index_blob.exists():
        print("  GCS: index.json not found, skipping")
        return [], []

    entries = json.loads(index_blob.download_as_text())
    print(f"  GCS: {len(entries)} entries in index")

    images, labels = [], []
    skipped = 0
    for entry in entries:
        tile_code = entry.get("tile_code", "")
        label_name = TILE_CODE_TO_LABEL.get(tile_code)
        if label_name is None or label_name not in label_to_idx:
            skipped += 1
            continue

        image_path = entry.get("image_path", "")
        if not image_path:
            skipped += 1
            continue

        try:
            blob = bucket.blob(image_path)
            data = blob.download_as_bytes()
            img = tf.keras.utils.load_img(io.BytesIO(data), target_size=(IMG_SIZE, IMG_SIZE))
            images.append(tf.keras.utils.img_to_array(img))
            labels.append(label_to_idx[label_name])
        except Exception as e:
            skipped += 1
            continue

    print(f"  GCS: loaded {len(images)} images, skipped {skipped}")
    return images, labels


# ──────────── tf.data pipeline with augmentation ────────────

def augment(image, label):
    """Data augmentation applied on [0,255] images."""
    image = tf.image.random_flip_left_right(image)
    image = tf.image.random_brightness(image, max_delta=40.0)
    image = tf.image.random_contrast(image, lower=0.7, upper=1.3)
    image = tf.image.random_saturation(image, lower=0.8, upper=1.2)
    # Random rotation via affine transform
    angle = tf.random.uniform([], -0.15, 0.15)
    image = rotate_image(image, angle)
    image = tf.clip_by_value(image, 0.0, 255.0)
    return image, label


def rotate_image(image, angle):
    """Rotate image by angle (radians)."""
    cos_a = tf.math.cos(angle)
    sin_a = tf.math.sin(angle)
    transform = [cos_a, -sin_a, 0.0, sin_a, cos_a, 0.0, 0.0, 0.0]
    image = tf.raw_ops.ImageProjectiveTransformV3(
        images=tf.expand_dims(image, 0),
        transforms=tf.expand_dims(transform, 0),
        output_shape=[IMG_SIZE, IMG_SIZE],
        interpolation="BILINEAR",
        fill_mode="REFLECT",
        fill_value=0.0,
    )
    return tf.squeeze(image, 0)


def preprocess(image, label):
    """Scale [0,255] → [-1,1] for MobileNetV2."""
    image = image / 127.5 - 1.0
    return image, label


def make_dataset(images, labels, augment_data=False, repeat=True):
    ds = tf.data.Dataset.from_tensor_slices((images, labels))
    if augment_data:
        ds = ds.shuffle(len(images), seed=SEED)
        if repeat:
            ds = ds.repeat()
        ds = ds.map(augment, num_parallel_calls=tf.data.AUTOTUNE)
    ds = ds.map(preprocess, num_parallel_calls=tf.data.AUTOTUNE)
    ds = ds.batch(BATCH_SIZE)
    ds = ds.prefetch(tf.data.AUTOTUNE)
    return ds


# ──────────── Model ────────────

def build_model(num_classes: int):
    base = MobileNetV2(
        input_shape=(IMG_SIZE, IMG_SIZE, 3),
        include_top=False,
        weights="imagenet",
    )
    base.trainable = False

    inputs = layers.Input(shape=(IMG_SIZE, IMG_SIZE, 3))
    x = base(inputs, training=False)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dropout(0.3)(x)
    x = layers.Dense(128, activation="relu")(x)
    x = layers.Dropout(0.2)(x)
    outputs = layers.Dense(num_classes, activation="softmax")(x)

    model = models.Model(inputs, outputs)
    return model, base


# ──────────── Training ────────────

def train(epochs: int, gcs_bucket: str | None = None, upload: bool = False):
    # Build label index from label.csv (canonical)
    label_map = load_label_map()
    # label_map: {1: "dots-1", 2: "dots-2", ...}
    label_names = [label_map[i] for i in sorted(label_map.keys())]
    label_to_idx = {name: idx for idx, name in enumerate(label_names)}
    num_classes = len(label_names)

    # Load data from all sources
    print("Loading datasets...")
    all_images, all_labels = [], []

    local_imgs, local_lbls = load_local_dataset(label_to_idx)
    all_images.extend(local_imgs)
    all_labels.extend(local_lbls)

    if gcs_bucket:
        gcs_imgs, gcs_lbls = load_gcs_dataset(gcs_bucket, label_to_idx)
        all_images.extend(gcs_imgs)
        all_labels.extend(gcs_lbls)

    if not all_images:
        print("ERROR: No training data found!")
        return

    images = np.array(all_images, dtype=np.float32)
    labels = np.array(all_labels, dtype=np.int32)
    print(f"\nTotal: {len(images)} images, {num_classes} classes")

    # Print per-class counts
    unique, counts = np.unique(labels, return_counts=True)
    for idx, count in zip(unique, counts):
        print(f"  {label_names[idx]}: {count}")

    from sklearn.model_selection import train_test_split
    X_train, X_val, y_train, y_val = train_test_split(
        images, labels, test_size=0.2, random_state=SEED, stratify=labels,
    )
    print(f"Train: {len(X_train)}, Val: {len(X_val)}")

    train_ds = make_dataset(X_train, y_train, augment_data=True)
    val_ds = make_dataset(X_val, y_val, augment_data=False, repeat=False)
    steps_per_epoch = max(1, len(X_train) // BATCH_SIZE)

    model, base = build_model(num_classes)

    # Phase 1: Train head only
    model.compile(
        optimizer=tf.keras.optimizers.Adam(1e-3),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    print("\n=== Phase 1: Training classification head ===")
    model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=max(10, epochs // 3),
        steps_per_epoch=steps_per_epoch,
        callbacks=[
            EarlyStopping(patience=5, restore_best_weights=True),
            ReduceLROnPlateau(patience=3, factor=0.5),
        ],
    )

    # Phase 2: Fine-tune top layers
    base.trainable = True
    for layer in base.layers[:-30]:
        layer.trainable = False

    model.compile(
        optimizer=tf.keras.optimizers.Adam(1e-4),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    print("\n=== Phase 2: Fine-tuning top layers ===")

    train_ds2 = make_dataset(X_train, y_train, augment_data=True)
    val_ds2 = make_dataset(X_val, y_val, augment_data=False, repeat=False)

    model.fit(
        train_ds2,
        validation_data=val_ds2,
        epochs=epochs,
        steps_per_epoch=steps_per_epoch,
        callbacks=[
            EarlyStopping(patience=8, restore_best_weights=True),
            ReduceLROnPlateau(patience=4, factor=0.5),
        ],
    )

    # Evaluate
    val_ds3 = make_dataset(X_val, y_val, augment_data=False, repeat=False)
    val_loss, val_acc = model.evaluate(val_ds3, verbose=0)
    print(f"\nValidation accuracy: {val_acc:.4f}")

    # ──────────── Export ────────────
    OUTPUT_DIR.mkdir(exist_ok=True)

    keras_path = OUTPUT_DIR / "tile_classifier.keras"
    model.save(keras_path)
    print(f"Keras model saved: {keras_path}")

    # Convert to TFLite (float16 quantized)
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    tflite_model = converter.convert()

    tflite_path = OUTPUT_DIR / "tile_classifier.tflite"
    tflite_path.write_bytes(tflite_model)
    print(f"TFLite model saved: {tflite_path} ({len(tflite_model) / 1024 / 1024:.1f} MB)")

    # Save labels
    labels_path = OUTPUT_DIR / "labels.txt"
    with open(labels_path, "w") as f:
        for name in label_names:
            f.write(f"{name}\n")
    print(f"Labels saved: {labels_path}")

    # Copy to Flutter assets (local dev)
    flutter_assets_env = os.environ.get("FLUTTER_ASSETS_DIR")
    if flutter_assets_env:
        flutter_assets = Path(flutter_assets_env)
    else:
        flutter_assets = BASE_DIR.parent / "mobile" / "assets" / "ml"
    flutter_assets.mkdir(parents=True, exist_ok=True)
    shutil.copy2(tflite_path, flutter_assets / "tile_classifier.tflite")
    shutil.copy2(labels_path, flutter_assets / "labels.txt")
    print(f"Copied to Flutter assets: {flutter_assets}")

    # Upload to GCS for dynamic model loading
    if upload and gcs_bucket:
        _upload_model_to_gcs(gcs_bucket, tflite_model, labels_path.read_text(), val_acc)


def _upload_model_to_gcs(bucket_name: str, tflite_bytes: bytes, labels_txt: str, val_acc: float):
    from google.cloud import storage
    client = storage.Client()
    bucket = client.bucket(bucket_name)

    now = datetime.now(timezone.utc)
    version = now.strftime("%Y%m%d%H%M%S")

    # Upload versioned model
    blob = bucket.blob(f"models/{version}/tile_classifier.tflite")
    blob.upload_from_string(tflite_bytes, content_type="application/octet-stream")

    blob = bucket.blob(f"models/{version}/labels.txt")
    blob.upload_from_string(labels_txt, content_type="text/plain")

    # Upload model metadata
    meta = {
        "version": version,
        "val_accuracy": val_acc,
        "created_at": now.isoformat(),
    }
    blob = bucket.blob(f"models/{version}/meta.json")
    blob.upload_from_string(json.dumps(meta), content_type="application/json")

    # Update latest pointer
    blob = bucket.blob("models/latest.json")
    blob.upload_from_string(json.dumps(meta), content_type="application/json")

    print(f"\nUploaded model to GCS: models/{version}/")
    print(f"  Version: {version}, Accuracy: {val_acc:.4f}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=int, default=DEFAULT_EPOCHS)
    parser.add_argument("--gcs-bucket", type=str, default=None,
                        help="GCS bucket to load training data from")
    parser.add_argument("--upload", action="store_true",
                        help="Upload trained model to GCS")
    args = parser.parse_args()
    train(args.epochs, gcs_bucket=args.gcs_bucket, upload=args.upload)
