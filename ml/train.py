#!/usr/bin/env python3
"""
Train a MobileNetV2 tile classifier on the Camerash mahjong-dataset.

Outputs:
  - tile_classifier.tflite  (float16 quantized, ~3 MB)
  - labels.txt              (class index → label name)

Usage:
  docker compose --profile ml run --rm ml-train python train.py
  docker compose --profile ml run --rm ml-train python train.py --epochs 50
"""

import argparse
import csv
import os
import shutil
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


# ──────────── Data loading ────────────

def load_label_map() -> dict[int, str]:
    label_map = {}
    with open(LABEL_CSV, encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            label_map[int(row["label-index"])] = row["label-name"]
    return label_map


def load_dataset() -> tuple[np.ndarray, np.ndarray, dict[int, str]]:
    label_map = load_label_map()
    images, labels = [], []
    with open(DATA_CSV, encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            img_path = TILES_DIR / row["image-name"]
            if not img_path.exists():
                continue
            img = tf.keras.utils.load_img(img_path, target_size=(IMG_SIZE, IMG_SIZE))
            images.append(tf.keras.utils.img_to_array(img))  # [0, 255]
            labels.append(int(row["label"]) - 1)  # 1-indexed → 0-indexed
    images = np.array(images, dtype=np.float32)
    labels = np.array(labels, dtype=np.int32)
    print(f"Loaded {len(images)} images, {len(label_map)} classes")
    return images, labels, label_map


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
    # Affine transform matrix for rotation around center
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
    """MobileNetV2 + classification head. No augmentation in the model graph."""
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

def train(epochs: int):
    images, labels, label_map = load_dataset()
    num_classes = len(label_map)

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

    # Re-create datasets (fresh iterator)
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
        for i in range(num_classes):
            f.write(f"{label_map[i + 1]}\n")
    print(f"Labels saved: {labels_path}")

    # Copy to Flutter assets
    flutter_assets_env = os.environ.get("FLUTTER_ASSETS_DIR")
    if flutter_assets_env:
        flutter_assets = Path(flutter_assets_env)
    else:
        flutter_assets = BASE_DIR.parent / "mobile" / "assets" / "ml"
    flutter_assets.mkdir(parents=True, exist_ok=True)
    shutil.copy2(tflite_path, flutter_assets / "tile_classifier.tflite")
    shutil.copy2(labels_path, flutter_assets / "labels.txt")
    print(f"Copied to Flutter assets: {flutter_assets}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=int, default=DEFAULT_EPOCHS)
    args = parser.parse_args()
    train(args.epochs)
