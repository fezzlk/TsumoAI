from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageOps

from app.tile_recognizer_local import _segment_tiles

BASE_DIR = Path(__file__).resolve().parents[1]
CASE_001_IMAGE = BASE_DIR / "data" / "eval_images_cropped" / "case-001.jpg"


def _draw_tiles(canvas: np.ndarray, boxes: list[tuple[int, int, int, int]]) -> np.ndarray:
    for x, y, w, h in boxes:
        cv2.rectangle(canvas, (x, y), (x + w, y + h), (240, 240, 235), -1)
    return canvas


def _dark_background(height: int, width: int) -> np.ndarray:
    canvas = np.zeros((height, width, 3), dtype=np.uint8)
    canvas[:, :] = (20, 90, 40)  # dark green playing-mat color
    return canvas


def test_segment_tiles_counts_non_touching_rectangles():
    height, width = 400, 3000
    canvas = _dark_background(height, width)
    tile_w, tile_h, gap = 180, 300, 40
    boxes = []
    x = 50
    for _ in range(8):
        boxes.append((x, 50, tile_w, tile_h))
        x += tile_w + gap
    canvas = _draw_tiles(canvas, boxes)

    tiles = _segment_tiles(canvas)

    assert len(tiles) == 8


def test_segment_tiles_recovers_count_from_touching_rectangles():
    """Regression test for the original bug: tiles placed with only a faint
    (sub-morphological-kernel) gap at a regular pitch used to merge into one
    connected component after MORPH_CLOSE and get badly undercounted by the
    old fixed-aspect-ratio subdivision. The gap here is real but thin enough
    that CLOSE bridges it, mirroring the real photos where inter-tile gaps
    survive in the raw mask but vanish after morphological cleanup."""
    height, width = 4900, 550
    canvas = _dark_background(height, width)
    tile_w, tile_h, gap = 500, 340, 3
    pitch = tile_h + gap
    n_tiles = 14
    boxes = [(25, 20 + i * pitch, tile_w, tile_h) for i in range(n_tiles)]
    canvas = _draw_tiles(canvas, boxes)

    tiles = _segment_tiles(canvas)

    assert len(tiles) == n_tiles


def test_segment_tiles_on_real_photo_is_close_to_fourteen():
    if not CASE_001_IMAGE.exists():
        return  # eval fixture not present in this environment

    with Image.open(CASE_001_IMAGE) as img:
        img = ImageOps.exif_transpose(img)
        rgb = np.array(img.convert("RGB"))

    tiles = _segment_tiles(rgb)

    assert 13 <= len(tiles) <= 15
