"""Local TFLite-based mahjong tile recognizer.

Uses MobileNetV2 TFLite model to classify individual tiles from a hand image.
Tile segmentation uses connected-component analysis on a white-pixel mask,
supporting any tile arrangement (horizontal, vertical, scattered).
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image

logger = logging.getLogger(__name__)

_MODEL_DIR = Path(__file__).resolve().parent.parent / "ml" / "output"
_TFLITE_PATH = _MODEL_DIR / "tile_classifier.tflite"
_LABELS_PATH = _MODEL_DIR / "labels.txt"

# Label-to-tile-code mapping
_LABEL_TO_TILE: dict[str, str] = {
    "dots-1": "1p", "dots-2": "2p", "dots-3": "3p", "dots-4": "4p",
    "dots-5": "5p", "dots-6": "6p", "dots-7": "7p", "dots-8": "8p", "dots-9": "9p",
    "bamboo-1": "1s", "bamboo-2": "2s", "bamboo-3": "3s", "bamboo-4": "4s",
    "bamboo-5": "5s", "bamboo-6": "6s", "bamboo-7": "7s", "bamboo-8": "8s", "bamboo-9": "9s",
    "characters-1": "1m", "characters-2": "2m", "characters-3": "3m", "characters-4": "4m",
    "characters-5": "5m", "characters-6": "6m", "characters-7": "7m", "characters-8": "8m", "characters-9": "9m",
    "honors-east": "E", "honors-south": "S", "honors-west": "W", "honors-north": "N",
    "honors-red": "C", "honors-green": "F", "honors-white": "P",
}

_interpreter = None
_labels: list[str] = []


def _load_model() -> None:
    """Lazily load the TFLite interpreter and labels."""
    global _interpreter, _labels

    if _interpreter is not None:
        return

    if not _TFLITE_PATH.exists() or not _LABELS_PATH.exists():
        raise FileNotFoundError(f"TFLite model not found at {_TFLITE_PATH}")

    try:
        import tflite_runtime.interpreter as tflite
        _interpreter = tflite.Interpreter(model_path=str(_TFLITE_PATH))
    except ImportError:
        import tensorflow as tf
        _interpreter = tf.lite.Interpreter(model_path=str(_TFLITE_PATH))

    _interpreter.allocate_tensors()
    _labels = _LABELS_PATH.read_text().strip().splitlines()


def _classify_tile(tile_img: np.ndarray) -> tuple[str, float]:
    """Classify a single tile image. Returns (label, confidence)."""
    _load_model()
    assert _interpreter is not None

    input_details = _interpreter.get_input_details()
    output_details = _interpreter.get_output_details()

    # Resize to model input size (224x224)
    h, w = input_details[0]["shape"][1], input_details[0]["shape"][2]
    resized = cv2.resize(tile_img, (w, h))
    input_data = np.expand_dims(resized, axis=0).astype(np.float32) / 255.0

    _interpreter.set_tensor(input_details[0]["index"], input_data)
    _interpreter.invoke()
    output_data = _interpreter.get_tensor(output_details[0]["index"])[0]

    idx = int(np.argmax(output_data))
    confidence = float(output_data[idx])
    label = _labels[idx] if idx < len(_labels) else "unknown"
    return label, confidence


def _segment_tiles(image: np.ndarray, tile_aspect: float = 0.75) -> list[np.ndarray]:
    """Segment individual tiles using connected-component analysis.

    Works with any tile arrangement (horizontal, vertical, scattered).

    Steps:
    1. HSV white-pixel mask + morphological cleanup
    2. Connected components to find white blobs
    3. Filter by area and density
    4. Subdivide oversized components using tile aspect ratio
    """
    hsv = cv2.cvtColor(image, cv2.COLOR_RGB2HSV)

    # Detect green mat region first (H=35-85 for green, moderate S and V)
    lower_green = np.array([35, 40, 40])
    upper_green = np.array([85, 255, 255])
    green_mask = cv2.inRange(hsv, lower_green, upper_green)

    # Dilate green mask to include tiles sitting on/near the mat edge
    dilate_kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (120, 120))
    mat_region = cv2.dilate(green_mask, dilate_kernel)

    # White pixel mask: low saturation, high value
    lower_white = np.array([0, 0, 160])
    upper_white = np.array([180, 80, 255])
    white_mask = cv2.inRange(hsv, lower_white, upper_white)

    # Restrict white detection to mat region only
    mask = cv2.bitwise_and(white_mask, mat_region)

    # Morphological cleanup
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)

    # Connected components
    num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(mask)

    tiles: list[np.ndarray] = []
    min_area = 500  # minimum pixel area for a tile component

    for i in range(1, num_labels):  # skip background (label 0)
        x, y, w, h, area = stats[i]

        if area < min_area:
            continue

        # Density: white pixels should fill at least 20% of bounding box
        bbox_area = w * h
        if bbox_area == 0 or area / bbox_area < 0.20:
            continue

        # Subdivide if the component spans multiple tiles
        if w >= h:
            expected_tile_w = h * tile_aspect
            n_sub = max(1, round(w / expected_tile_w)) if expected_tile_w > 0 else 1
            sub_w = w / n_sub
            for j in range(n_sub):
                sx = x + int(j * sub_w)
                ex = x + int((j + 1) * sub_w)
                tile_img = image[y:y + h, sx:ex]
                if tile_img.shape[0] > 0 and tile_img.shape[1] > 0:
                    tiles.append(tile_img)
        else:
            expected_tile_h = w / tile_aspect
            n_sub = max(1, round(h / expected_tile_h)) if expected_tile_h > 0 else 1
            sub_h = h / n_sub
            for j in range(n_sub):
                sy = y + int(j * sub_h)
                ey = y + int((j + 1) * sub_h)
                tile_img = image[sy:ey, x:x + w]
                if tile_img.shape[0] > 0 and tile_img.shape[1] > 0:
                    tiles.append(tile_img)

    return tiles


def recognize_tiles_local(image_bytes: bytes) -> dict[str, Any] | None:
    """Recognize mahjong tiles from image bytes using local TFLite model.

    Returns a dict with keys: tiles_count, slots, warnings, model_name
    or None if recognition fails.
    """
    try:
        _load_model()
    except (FileNotFoundError, Exception) as exc:
        logger.warning("TFLite model not available: %s", exc)
        return None

    try:
        pil_img = Image.open(__import__("io").BytesIO(image_bytes))
        rgb = np.array(pil_img.convert("RGB"))
    except Exception as exc:
        logger.warning("Failed to load image for TFLite: %s", exc)
        return None

    tile_images = _segment_tiles(rgb)
    if not tile_images or len(tile_images) < 13:
        logger.info("TFLite segmentation found %d tiles (need 13-14)", len(tile_images) if tile_images else 0)
        return None

    slots: list[dict[str, Any]] = []
    confidences: list[float] = []
    warnings: list[str] = []

    for idx, tile_img in enumerate(tile_images):
        label, confidence = _classify_tile(tile_img)
        tile_code = _LABEL_TO_TILE.get(label)
        if tile_code is None:
            warnings.append(f"slot {idx}: label '{label}' not mapped to tile code")
            continue

        confidences.append(confidence)
        slots.append({
            "index": idx,
            "top": tile_code,
            "candidates": [{"tile": tile_code, "confidence": confidence}],
            "ambiguous": confidence < 0.7,
            "top_confidence": confidence,
        })

    if len(slots) < 13:
        logger.info("TFLite classified only %d valid tiles (need 13-14)", len(slots))
        return None

    avg_confidence = sum(confidences) / len(confidences) if confidences else 0
    if avg_confidence < 0.5:
        logger.info("TFLite average confidence %.2f too low", avg_confidence)
        return None

    # Re-index slots
    for i, slot in enumerate(slots):
        slot["index"] = i

    return {
        "tiles_count": len(slots),
        "slots": slots,
        "warnings": warnings,
        "model_name": "tflite-mobilenetv2",
    }
