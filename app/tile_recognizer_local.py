"""Local TFLite-based mahjong tile recognizer.

Uses MobileNetV2 TFLite model to classify individual tiles from a hand image.
Tile segmentation uses HSV-based white-pixel detection and histogram projection.
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


def _segment_tiles(image: np.ndarray) -> list[np.ndarray]:
    """Segment individual tiles from a hand image using histogram projection.

    Steps:
    1. Convert to HSV and detect white pixels (tiles on green mat)
    2. Horizontal projection to find the tile band (row range)
    3. Vertical projection within the band to find column boundaries
    4. Extract individual tile images
    """
    hsv = cv2.cvtColor(image, cv2.COLOR_RGB2HSV)

    # White pixel mask: low saturation, high value
    lower_white = np.array([0, 0, 160])
    upper_white = np.array([180, 80, 255])
    mask = cv2.inRange(hsv, lower_white, upper_white)

    # Apply morphological operations to clean up
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)

    # Horizontal projection (sum of white pixels per row)
    h_proj = np.sum(mask, axis=1) / 255
    h_threshold = np.max(h_proj) * 0.3

    rows = np.where(h_proj > h_threshold)[0]
    if len(rows) == 0:
        return []

    row_start = rows[0]
    row_end = rows[-1]
    # Add small padding
    pad = int((row_end - row_start) * 0.05)
    row_start = max(0, row_start - pad)
    row_end = min(image.shape[0], row_end + pad)

    band = mask[row_start:row_end, :]

    # Vertical projection (sum of white pixels per column in the band)
    v_proj = np.sum(band, axis=0) / 255
    v_threshold = np.max(v_proj) * 0.15

    cols = np.where(v_proj > v_threshold)[0]
    if len(cols) == 0:
        return []

    # Find contiguous column groups (individual tiles separated by gaps)
    groups: list[tuple[int, int]] = []
    group_start = cols[0]
    prev = cols[0]
    band_h = row_end - row_start
    min_gap = max(3, int(band_h * 0.05))  # small gaps within a tile are noise

    for c in cols[1:]:
        if c - prev > min_gap:
            groups.append((group_start, prev))
            group_start = c
        prev = c
    groups.append((group_start, prev))

    # Filter out groups that are too narrow (noise) or too wide (background)
    min_tile_w = band_h * 0.3
    max_tile_w = band_h * 1.5
    groups = [(s, e) for s, e in groups if min_tile_w <= (e - s + 1) <= max_tile_w]

    # Filter by white pixel density: reject sparse noise/reflections on the mat
    v_peak = np.max(v_proj)
    density_threshold = v_peak * 0.30
    groups = [
        (s, e) for s, e in groups
        if np.mean(v_proj[s:e + 1]) >= density_threshold
    ]

    if not groups:
        return []

    # For wide groups that likely contain multiple tiles, subdivide
    tiles: list[np.ndarray] = []
    expected_tile_w = band_h * 0.72  # typical tile aspect ratio ~0.72

    for g_start, g_end in groups:
        w = g_end - g_start + 1
        n_sub = max(1, round(w / expected_tile_w))
        sub_w = w / n_sub
        for i in range(n_sub):
            x_start = g_start + int(i * sub_w)
            x_end = g_start + int((i + 1) * sub_w)
            tile_img = image[row_start:row_end, x_start:x_end]
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
