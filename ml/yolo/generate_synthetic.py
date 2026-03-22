#!/usr/bin/env python3
"""
Generate synthetic training data for YOLO tile detection.

Takes individual tile images and places them on green mat backgrounds
in various arrangements (horizontal rows, vertical stacks, scattered).
Outputs images + YOLO format annotation files.

Usage:
  python ml/yolo/generate_synthetic.py --count 1000
"""

from __future__ import annotations

import argparse
import csv
import random
from pathlib import Path
from typing import List, Tuple

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

SEED = 42
BASE_DIR = Path(__file__).resolve().parent.parent
TILES_DIR = BASE_DIR / "tiles-resized"
DATA_CSV = BASE_DIR / "data.csv"
OUTPUT_DIR = BASE_DIR / "yolo" / "dataset"

# Output image size
IMG_W, IMG_H = 640, 640

# Green mat color range (RGB)
MAT_COLORS = [
    (34, 110, 59),   # dark green
    (40, 120, 65),   # medium green
    (45, 130, 70),   # lighter green
    (30, 100, 50),   # deep green
    (50, 140, 75),   # bright green
]


def load_tile_images() -> list[Image.Image]:
    """Load all tile images from the dataset."""
    tiles = []
    with open(DATA_CSV, encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            img_path = TILES_DIR / row["image-name"]
            if img_path.exists():
                tiles.append(Image.open(img_path).convert("RGBA"))
    print(f"Loaded {len(tiles)} tile images")
    return tiles


def create_mat_background(w: int, h: int) -> Image.Image:
    """Create a green mat background with subtle texture."""
    color = random.choice(MAT_COLORS)
    bg = Image.new("RGB", (w, h), color)

    # Add subtle noise for texture
    noise = np.random.randint(-8, 8, (h, w, 3), dtype=np.int16)
    bg_arr = np.array(bg, dtype=np.int16) + noise
    bg_arr = np.clip(bg_arr, 0, 255).astype(np.uint8)
    bg = Image.fromarray(bg_arr)

    # Slight blur for realism
    bg = bg.filter(ImageFilter.GaussianBlur(radius=0.5))
    return bg


def random_tile_transform(tile: Image.Image, target_h: int) -> Image.Image:
    """Apply random transformations to a tile image."""
    # Maintain aspect ratio, resize to target height
    aspect = tile.width / tile.height
    target_w = int(target_h * aspect)
    tile = tile.resize((target_w, target_h), Image.LANCZOS)

    # Random brightness/contrast
    tile_rgb = tile.convert("RGB")
    tile_rgb = ImageEnhance.Brightness(tile_rgb).enhance(random.uniform(0.8, 1.2))
    tile_rgb = ImageEnhance.Contrast(tile_rgb).enhance(random.uniform(0.85, 1.15))

    # Random slight rotation (-5 to +5 degrees)
    angle = random.uniform(-5, 5)
    tile_rgba = tile_rgb.convert("RGBA")
    tile_rgba = tile_rgba.rotate(angle, expand=True, fillcolor=(0, 0, 0, 0))

    return tile_rgba


def place_horizontal_row(
    bg: Image.Image,
    tiles: list[Image.Image],
    n_tiles: int,
) -> list[tuple[float, float, float, float]]:
    """Place tiles in a horizontal row. Returns list of (x_center, y_center, w, h) normalized."""
    bboxes = []
    tile_h = random.randint(60, 120)
    tile_w = int(tile_h * 0.75)
    gap = random.randint(0, 4)

    total_w = n_tiles * tile_w + (n_tiles - 1) * gap
    if total_w > bg.width - 40:
        tile_h = int((bg.width - 40 - (n_tiles - 1) * gap) / n_tiles / 0.75)
        tile_w = int(tile_h * 0.75)
        total_w = n_tiles * tile_w + (n_tiles - 1) * gap

    start_x = random.randint(20, max(20, bg.width - total_w - 20))
    start_y = random.randint(20, max(20, bg.height - tile_h - 20))

    for i in range(n_tiles):
        tile_img = random.choice(tiles)
        tile_img = random_tile_transform(tile_img, tile_h)

        x = start_x + i * (tile_w + gap)
        y = start_y

        # Paste tile
        bg.paste(tile_img, (x, y), tile_img)

        # YOLO bbox (normalized)
        cx = (x + tile_w / 2) / bg.width
        cy = (y + tile_h / 2) / bg.height
        bw = tile_w / bg.width
        bh = tile_h / bg.height
        bboxes.append((cx, cy, bw, bh))

    return bboxes


def place_vertical_stack(
    bg: Image.Image,
    tiles: list[Image.Image],
    n_tiles: int,
) -> list[tuple[float, float, float, float]]:
    """Place tiles in a vertical stack."""
    bboxes = []
    tile_h = random.randint(50, 90)
    tile_w = int(tile_h * 0.75)
    gap = random.randint(0, 3)

    total_h = n_tiles * tile_h + (n_tiles - 1) * gap
    if total_h > bg.height - 40:
        tile_h = int((bg.height - 40 - (n_tiles - 1) * gap) / n_tiles)
        tile_w = int(tile_h * 0.75)
        total_h = n_tiles * tile_h + (n_tiles - 1) * gap

    start_x = random.randint(20, max(20, bg.width - tile_w - 20))
    start_y = random.randint(20, max(20, bg.height - total_h - 20))

    for i in range(n_tiles):
        tile_img = random.choice(tiles)
        tile_img = random_tile_transform(tile_img, tile_h)

        x = start_x
        y = start_y + i * (tile_h + gap)

        bg.paste(tile_img, (x, y), tile_img)

        cx = (x + tile_w / 2) / bg.width
        cy = (y + tile_h / 2) / bg.height
        bw = tile_w / bg.width
        bh = tile_h / bg.height
        bboxes.append((cx, cy, bw, bh))

    return bboxes


def place_scattered(
    bg: Image.Image,
    tiles: list[Image.Image],
    n_tiles: int,
) -> list[tuple[float, float, float, float]]:
    """Place tiles scattered randomly."""
    bboxes = []
    tile_h = random.randint(50, 100)
    tile_w = int(tile_h * 0.75)

    placed = []
    for _ in range(n_tiles):
        tile_img = random.choice(tiles)
        tile_img = random_tile_transform(tile_img, tile_h)

        # Try to place without too much overlap
        for _attempt in range(20):
            x = random.randint(10, bg.width - tile_w - 10)
            y = random.randint(10, bg.height - tile_h - 10)
            overlap = False
            for px, py in placed:
                if abs(x - px) < tile_w * 0.5 and abs(y - py) < tile_h * 0.5:
                    overlap = True
                    break
            if not overlap:
                break

        placed.append((x, y))
        bg.paste(tile_img, (x, y), tile_img)

        cx = (x + tile_w / 2) / bg.width
        cy = (y + tile_h / 2) / bg.height
        bw = tile_w / bg.width
        bh = tile_h / bg.height
        bboxes.append((cx, cy, bw, bh))

    return bboxes


def generate_one(tiles: list[Image.Image], idx: int) -> tuple[Image.Image, list[tuple[float, float, float, float]]]:
    """Generate one synthetic training image with annotations."""
    bg = create_mat_background(IMG_W, IMG_H)

    # Random arrangement
    arrangement = random.choice(["horizontal", "vertical", "scattered", "horizontal"])
    n_tiles = random.choices(
        [1, 2, 3, 4, 5, 6, 7, 13, 14],
        weights=[2, 3, 5, 5, 5, 5, 5, 10, 15],
    )[0]

    if arrangement == "horizontal":
        bboxes = place_horizontal_row(bg, tiles, n_tiles)
    elif arrangement == "vertical":
        bboxes = place_vertical_stack(bg, tiles, n_tiles)
    else:
        bboxes = place_scattered(bg, tiles, n_tiles)

    # Random overall adjustments
    if random.random() < 0.3:
        bg = ImageEnhance.Brightness(bg).enhance(random.uniform(0.7, 1.3))
    if random.random() < 0.2:
        bg = bg.filter(ImageFilter.GaussianBlur(radius=random.uniform(0.5, 1.5)))

    return bg, bboxes


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=1000, help="Number of images to generate")
    parser.add_argument("--seed", type=int, default=SEED)
    args = parser.parse_args()

    random.seed(args.seed)
    np.random.seed(args.seed)

    tiles = load_tile_images()

    # Create output directories
    for split in ["train", "val"]:
        (OUTPUT_DIR / split / "images").mkdir(parents=True, exist_ok=True)
        (OUTPUT_DIR / split / "labels").mkdir(parents=True, exist_ok=True)

    val_count = max(1, args.count // 5)
    train_count = args.count - val_count

    for i in range(args.count):
        split = "val" if i < val_count else "train"
        img, bboxes = generate_one(tiles, i)

        # Save image
        img_path = OUTPUT_DIR / split / "images" / f"{i:06d}.jpg"
        img.save(img_path, quality=90)

        # Save YOLO annotation (class 0 = tile)
        label_path = OUTPUT_DIR / split / "labels" / f"{i:06d}.txt"
        with open(label_path, "w") as f:
            for cx, cy, bw, bh in bboxes:
                f.write(f"0 {cx:.6f} {cy:.6f} {bw:.6f} {bh:.6f}\n")

        if (i + 1) % 100 == 0:
            print(f"Generated {i + 1}/{args.count}")

    # Create data.yaml for YOLO training
    yaml_path = OUTPUT_DIR / "data.yaml"
    yaml_path.write_text(
        f"path: {OUTPUT_DIR}\n"
        f"train: train/images\n"
        f"val: val/images\n"
        f"nc: 1\n"
        f"names: ['tile']\n"
    )

    print(f"\nDone! Generated {train_count} train + {val_count} val images")
    print(f"Dataset: {OUTPUT_DIR}")
    print(f"Config: {yaml_path}")


if __name__ == "__main__":
    main()
