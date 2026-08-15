"""Local TFLite-based mahjong tile recognizer.

Uses MobileNetV2 TFLite model to classify individual tiles from a hand image.
Tile segmentation uses connected-component analysis on a white-pixel mask,
followed by autocorrelation-based pitch detection to split a merged run of
touching tiles into individual tiles. Supports a single linear run of tiles
(horizontal row or vertical stack); scattered/non-linear arrangements are not
handled.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image, ImageOps

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
    input_data = np.expand_dims(resized, axis=0).astype(np.float32) / 127.5 - 1.0

    _interpreter.set_tensor(input_details[0]["index"], input_data)
    _interpreter.invoke()
    output_data = _interpreter.get_tensor(output_details[0]["index"])[0]

    idx = int(np.argmax(output_data))
    confidence = float(output_data[idx])
    label = _labels[idx] if idx < len(_labels) else "unknown"
    return label, confidence


def _find_local_maxima(seg: np.ndarray, prominence: float = 0.02) -> list[int]:
    """Find interior local-maxima indices in a 1-D array with a simple
    prominence filter against the nearest valleys on each side. Avoids a
    scipy dependency (scipy is not in requirements.txt)."""
    peaks: list[int] = []
    for i in range(1, len(seg) - 1):
        if seg[i] > seg[i - 1] and seg[i] >= seg[i + 1]:
            left_min = seg[max(0, i - 10):i].min()
            right_min = seg[i + 1:i + 11].min() if i + 1 < len(seg) else seg[i]
            if seg[i] - max(left_min, right_min) >= prominence:
                peaks.append(i)
    return peaks


def _estimate_pitch(profile: np.ndarray, dim: int) -> tuple[int | None, float]:
    """Detect the repeat period (tile pitch) in a 1-D white-fraction profile
    via autocorrelation. Returns (pitch_px, confidence), or (None, 0.0) if no
    genuine interior periodicity is found (i.e. this blob is a single tile)."""
    sig = profile - profile.mean()
    if sig.std() < 1e-6:
        return None, 0.0
    ac = np.correlate(sig, sig, mode="full")
    ac = ac[len(ac) // 2:]
    if ac[0] <= 0:
        return None, 0.0
    ac = ac / ac[0]
    lo, hi = max(3, dim // 20), max(3, dim // 2)
    if hi <= lo + 2:
        return None, 0.0
    seg = ac[lo:hi]
    peaks = _find_local_maxima(seg, prominence=0.02)
    if not peaks:
        return None, 0.0
    tallest = peaks[int(np.argmax(seg[peaks]))]
    tallest_val = seg[tallest]

    # The tallest autocorrelation peak is occasionally a harmonic (2x, 3x the
    # true tile pitch) rather than the fundamental. Only override it with a
    # sub-divided candidate when that candidate is ALSO an independently
    # qualifying peak (passed its own prominence check) and nearly as strong
    # as the tallest peak — this avoids mistaking a merely-present but weaker
    # harmonic for the true fundamental, which over-splits well-behaved cases.
    best = tallest
    for divisor in range(2, 7):
        candidate_target = tallest / divisor
        if candidate_target < 1:
            break
        nearby = [p for p in peaks if abs(p - candidate_target) <= max(1, 0.1 * candidate_target)]
        if not nearby:
            continue
        candidate = max(nearby, key=lambda p: seg[p])
        if seg[candidate] >= 0.85 * tallest_val:
            best = candidate

    return lo + best, float(ac[lo + best])


def _blob_pitch(
    mask_raw: np.ndarray, x: int, y: int, w: int, h: int, vertical: bool,
) -> tuple[int | None, float, int]:
    """Estimate tile pitch for one blob from the RAW (pre-morphology) mask
    restricted to its bounding box. MORPH_CLOSE erases the seam signal
    between touching tiles, so this must read from the mask before that
    step. Returns (pitch_px, confidence, dim) — dim is the blob's extent
    along the run axis."""
    sub = mask_raw[y:y + h, x:x + w].astype(np.float64) / 255.0
    if vertical:
        profile = sub.mean(axis=1)
        dim = h
    else:
        profile = sub.mean(axis=0)
        dim = w
    pitch, confidence = _estimate_pitch(profile, dim)
    return pitch, confidence, dim


def _segment_tiles(image: np.ndarray) -> list[np.ndarray]:
    """Segment individual tiles from a single linear run (horizontal row or
    vertical stack) using connected-component analysis plus pitch detection.

    Steps:
    1. HSV white-pixel mask (kept raw, pre-morphology, for later pitch
       detection) + morphological cleanup for connected-component finding
    2. Connected components to find white blobs
    3. Filter by absolute area/dimension and density
    4. Decide run orientation once, from the spatial spread of all surviving
       components (not any single component's own aspect ratio)
    5. Drop components that substantially overlap an already-kept larger
       component along the run axis (glare/reflection noise)
    6. Estimate a per-blob tile pitch via autocorrelation; for blobs whose
       own pitch estimate is low-confidence, fall back to the median pitch
       of the image's confident blobs (same photo, same tile scale) instead
       of treating the blob as a single tile
    7. Subdivide each kept component into individual tiles using the
       resolved pitch
    """
    hsv = cv2.cvtColor(image, cv2.COLOR_RGB2HSV)

    # White pixel mask: low saturation, high value
    lower_white = np.array([0, 0, 160])
    upper_white = np.array([180, 80, 255])
    mask_raw = cv2.inRange(hsv, lower_white, upper_white)

    # Morphological cleanup (component-finding only; mask_raw is kept intact
    # for pitch detection, since CLOSE bridges the thin gaps between tiles)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
    mask = cv2.morphologyEx(mask_raw, cv2.MORPH_CLOSE, kernel)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)

    # Connected components
    num_labels, _labels, stats, _ = cv2.connectedComponentsWithStats(mask)
    if num_labels <= 1:
        return []

    image_h, image_w = image.shape[:2]
    image_area = image_h * image_w
    min_area = max(300, int(0.003 * image_area))
    min_dim_w = 0.015 * image_w
    min_dim_h = 0.015 * image_h

    components: list[tuple[int, int, int, int, int]] = []  # x, y, w, h, area
    for i in range(1, num_labels):  # skip background (label 0)
        x, y, w, h, area = stats[i]

        if area < min_area or w < min_dim_w or h < min_dim_h:
            continue

        # Density: white pixels should fill at least 20% of bounding box
        bbox_area = w * h
        if bbox_area == 0 or area / bbox_area < 0.20:
            continue

        components.append((x, y, w, h, area))

    if not components:
        return []

    # Decide run orientation once, from how ALL surviving components are
    # spatially arranged — not from a single component's own aspect ratio,
    # which reflects individual tile shape rather than the row/stack
    # direction (e.g. a horizontal row of portrait-shaped, non-touching
    # tiles must still be treated as horizontal).
    span_x = max(x + w for x, y, w, h, _a in components) - min(x for x, y, w, h, _a in components)
    span_y = max(y + h for x, y, w, h, _a in components) - min(y for x, y, w, h, _a in components)
    vertical = span_y >= span_x

    # Drop components whose extent along the run axis substantially overlaps
    # an already-kept larger component (glare/reflection noise).
    kept: list[tuple[int, int, int, int, int]] = []
    for comp in sorted(components, key=lambda c: c[4], reverse=True):
        x, y, w, h, area = comp
        lo, hi = (y, y + h) if vertical else (x, x + w)
        span = hi - lo
        overlap = False
        for kx, ky, kw, kh, _ka in kept:
            klo, khi = (ky, ky + kh) if vertical else (kx, kx + kw)
            inter = max(0, min(hi, khi) - max(lo, klo))
            if span > 0 and inter / span > 0.5:
                overlap = True
                break
        if not overlap:
            kept.append(comp)

    # Restore reading order (top-to-bottom, left-to-right) for stable output.
    kept.sort(key=lambda c: (c[1], c[0]))

    # Pass 1: estimate each blob's own pitch/confidence.
    min_confidence = 0.30
    reference_confidence = 0.50
    blob_pitches = [_blob_pitch(mask_raw, x, y, w, h, vertical) for x, y, w, h, _area in kept]

    # Blobs on the same photo share the same real-world tile scale. A blob
    # whose own periodicity signal is weak/ambiguous (e.g. spans few tiles,
    # or its autocorrelation is noisy) is better estimated from the pitch
    # of the image's confident blobs than trusted on its own.
    confident_pitches = [p for p, conf, _dim in blob_pitches if p is not None and conf >= reference_confidence]
    reference_pitch = float(np.median(confident_pitches)) if confident_pitches else None

    tiles: list[np.ndarray] = []
    for (x, y, w, h, _area), (pitch, confidence, dim) in zip(kept, blob_pitches):
        if pitch is not None and confidence >= reference_confidence:
            n_sub = max(1, round(dim / pitch))
        elif reference_pitch is not None:
            n_sub = max(1, round(dim / reference_pitch))
        elif pitch is not None and confidence >= min_confidence:
            n_sub = max(1, round(dim / pitch))
        else:
            n_sub = 1

        if vertical:
            sub_h = h / n_sub
            for j in range(n_sub):
                sy = y + int(j * sub_h)
                ey = y + int((j + 1) * sub_h)
                tile_img = image[sy:ey, x:x + w]
                if tile_img.shape[0] > 0 and tile_img.shape[1] > 0:
                    tiles.append(tile_img)
        else:
            sub_w = w / n_sub
            for j in range(n_sub):
                sx = x + int(j * sub_w)
                ex = x + int((j + 1) * sub_w)
                tile_img = image[y:y + h, sx:ex]
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
        pil_img = ImageOps.exif_transpose(pil_img)
        rgb = np.array(pil_img.convert("RGB"))
    except Exception as exc:
        logger.warning("Failed to load image for TFLite: %s", exc)
        return None

    tile_images = _segment_tiles(rgb)
    if not tile_images or len(tile_images) not in (13, 14):
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

    if len(slots) not in (13, 14):
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
