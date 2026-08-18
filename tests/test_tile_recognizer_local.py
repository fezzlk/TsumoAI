from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageOps

from app.tile_recognizer_local import _segment_tile_boxes, _segment_tiles

BASE_DIR = Path(__file__).resolve().parents[1]
CASE_001_IMAGE = BASE_DIR / "data" / "eval_images_cropped" / "case-001.jpg"
CASE_003_IMAGE = BASE_DIR / "data" / "eval_images_cropped" / "case-003.jpg"
CASE_006_IMAGE = BASE_DIR / "data" / "eval_images_cropped" / "case-006.jpg"


def _draw_tiles(canvas: np.ndarray, boxes: list[tuple[int, int, int, int]]) -> np.ndarray:
    for x, y, w, h in boxes:
        cv2.rectangle(canvas, (x, y), (x + w, y + h), (240, 240, 235), -1)
    return canvas


def _dark_background(height: int, width: int) -> np.ndarray:
    canvas = np.zeros((height, width, 3), dtype=np.uint8)
    canvas[:, :] = (20, 90, 40)  # dark green playing-mat color
    return canvas


def _fill_rotated_tile(canvas: np.ndarray, cx: float, cy: float, w: float, h: float, angle_deg: float) -> None:
    rad = np.deg2rad(angle_deg)
    cos_a, sin_a = np.cos(rad), np.sin(rad)
    corners = []
    for dx, dy in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)):
        rx = dx * cos_a - dy * sin_a
        ry = dx * sin_a + dy * cos_a
        corners.append([cx + rx, cy + ry])
    pts = np.array([corners], dtype=np.int32)
    cv2.fillPoly(canvas, pts, (240, 240, 235))


def _draw_curved_tiles(
    canvas: np.ndarray,
    n_tiles: int,
    straight_count: int,
    tile_w: float,
    tile_h: float,
    pitch: float,
    start_x: float,
    start_y: float,
    total_bend_deg: float,
) -> list[tuple[float, float, float, float, float]]:
    """Places tiles left-to-right: the first `straight_count` axis-aligned
    on a straight line, then the remainder curving with a heading that
    ramps linearly from 0deg to `total_bend_deg` — simulating a bent
    (non-straight) physical tile row. Returns each tile's true placement as
    (cx, cy, w, h, angle_deg), in placement order; see `_point_in_tile`."""
    placed: list[tuple[float, float, float, float, float]] = []
    cx, cy = start_x + tile_w / 2, start_y
    bend_tiles = n_tiles - straight_count
    for i in range(n_tiles):
        if i < straight_count:
            x, y = int(round(cx - tile_w / 2)), int(round(cy - tile_h / 2))
            cv2.rectangle(canvas, (x, y), (x + int(round(tile_w)), y + int(round(tile_h))), (240, 240, 235), -1)
            placed.append((cx, cy, tile_w, tile_h, 0.0))
            cx += pitch
        else:
            heading = total_bend_deg * (i - straight_count + 1) / bend_tiles
            _fill_rotated_tile(canvas, cx, cy, tile_w, tile_h, heading)
            placed.append((cx, cy, tile_w, tile_h, heading))
            rad = np.deg2rad(heading)
            cx += pitch * np.cos(rad)
            cy += pitch * np.sin(rad)
    return placed


def _point_in_tile(px: float, py: float, tile: tuple[float, float, float, float, float]) -> bool:
    """Whether (px, py) falls within `tile`'s actual (possibly rotated)
    footprint, via inverse-rotation into the tile's own local axes."""
    cx, cy, w, h, angle_deg = tile
    rad = np.deg2rad(-angle_deg)
    dx, dy = px - cx, py - cy
    lx = dx * np.cos(rad) - dy * np.sin(rad)
    ly = dx * np.sin(rad) + dy * np.cos(rad)
    return abs(lx) <= w / 2 and abs(ly) <= h / 2


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


def test_segment_tiles_drops_unrelated_blob_past_fourteen():
    """A stray white blob disconnected from the tile run (e.g. a spare tile
    left in frame) must not inflate the count past the known 13/14 hand
    size; regression guard for the case-003 over-detection (a leftover tile
    below the hand was previously force-counted as a 15th tile)."""
    height, width = 5450, 600
    canvas = _dark_background(height, width)
    tile_w, tile_h, gap = 500, 340, 3
    pitch = tile_h + gap
    n_tiles = 14
    boxes = [(25, 20 + i * pitch, tile_w, tile_h) for i in range(n_tiles)]
    canvas = _draw_tiles(canvas, boxes)
    stray_y = 20 + n_tiles * pitch + 150
    canvas = _draw_tiles(canvas, [(40, stray_y, 400, 420)])

    tiles = _segment_tiles(canvas)

    assert len(tiles) == n_tiles


def test_segment_tiles_case_003_real_photo_is_exactly_fourteen():
    if not CASE_003_IMAGE.exists():
        return  # eval fixture not present in this environment

    with Image.open(CASE_003_IMAGE) as img:
        img = ImageOps.exif_transpose(img)
        rgb = np.array(img.convert("RGB"))

    assert len(_segment_tiles(rgb)) == 14


def test_segment_tiles_case_006_real_photo_is_exactly_fourteen():
    if not CASE_006_IMAGE.exists():
        return  # eval fixture not present in this environment

    with Image.open(CASE_006_IMAGE) as img:
        img = ImageOps.exif_transpose(img)
        rgb = np.array(img.convert("RGB"))

    assert len(_segment_tiles(rgb)) == 14


def test_segment_tile_boxes_keeps_each_slot_aligned_to_one_tile_on_curved_row():
    """Regression test for the curved-row bug: the last few tiles of a
    physical hand bend away from a straight line (confirmed on real device
    photos), and the old fixed-cross-axis-per-slice subdivision let a
    slice's box drift onto a neighboring tile plus background."""
    n_tiles = 14
    straight_count = 10
    run_extent, cross_extent, gap = 340.0, 500.0, 80.0
    pitch = run_extent + gap
    total_bend_deg = 30.0
    start_x, start_y = 100.0, 1400.0
    canvas = _dark_background(3000, 6000)
    ground_truth = _draw_curved_tiles(
        canvas, n_tiles, straight_count, run_extent, cross_extent, pitch, start_x, start_y, total_bend_deg,
    )

    boxes = _segment_tile_boxes(canvas)

    assert len(boxes) == n_tiles, "curved row should still resolve to the correct 13/14 hand size"

    # For each detected box, sample a grid of points and classify each by
    # which ground-truth tile's actual (rotated) footprint it falls in.
    # This directly measures "how much of this crop belongs to the wrong
    # tile" — the real symptom confirmed on real device photos — without
    # relying on axis-aligned bbox overlap, which is not a safe proxy for
    # rotated neighbors (two rotated tiles' bboxes can overlap even when
    # the tiles themselves don't).
    grid_n = 8
    for sy, ey, sx, ex in boxes:
        counts = [0] * len(ground_truth)
        total = 0
        for gi in range(grid_n):
            for gj in range(grid_n):
                px = sx + (ex - sx) * (gi + 0.5) / grid_n
                py = sy + (ey - sy) * (gj + 0.5) / grid_n
                total += 1
                for t, tile in enumerate(ground_truth):
                    if _point_in_tile(px, py, tile):
                        counts[t] += 1
                        break  # tiles don't physically overlap; first match is the owner
        match_idx = int(np.argmax(counts))
        match_fraction = counts[match_idx] / total
        assert match_fraction > 0.5, (
            f"box (sy={sy},ey={ey},sx={sx},ex={ex}) should be dominated by a single tile "
            f"(best match tile {match_idx} covers {match_fraction:.0%})"
        )
        for t in range(len(ground_truth)):
            if t == match_idx:
                continue
            fraction = counts[t] / total
            assert fraction < 0.2, (
                f"box (sy={sy},ey={ey},sx={sx},ex={ex}) should not substantially contain "
                f"neighboring tile {t} ({fraction:.0%})"
            )
