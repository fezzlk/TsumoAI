#!/usr/bin/env python3
"""
Download and convert public mahjong tile datasets for training.

Datasets:
1. Kaggle "Mahjong" (mexwell/mahjong) - ~55MB, individual tile images
2. Existing Camerash dataset (already in ml/tiles-resized/)

Usage:
  # With Kaggle API key configured (~/.kaggle/kaggle.json):
  python ml/scripts/download_datasets.py

  # Or manually download from Kaggle and extract:
  python ml/scripts/download_datasets.py --kaggle-dir /path/to/extracted/mahjong
"""
from __future__ import annotations

import argparse
import csv
import os
import shutil
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
OUTPUT_DIR = BASE_DIR / "training_data"
TILES_RESIZED = BASE_DIR / "tiles-resized"
DATA_CSV = BASE_DIR / "data.csv"

# Mapping from various dataset label formats to our tile codes
TILE_CODE_MAP = {
    # Kaggle "Mahjong" dataset uses folder names like "1m", "2p", etc.
    "1m": "1m", "2m": "2m", "3m": "3m", "4m": "4m", "5m": "5m",
    "6m": "6m", "7m": "7m", "8m": "8m", "9m": "9m",
    "1p": "1p", "2p": "2p", "3p": "3p", "4p": "4p", "5p": "5p",
    "6p": "6p", "7p": "7p", "8p": "8p", "9p": "9p",
    "1s": "1s", "2s": "2s", "3s": "3s", "4s": "4s", "5s": "5s",
    "6s": "6s", "7s": "7s", "8s": "8s", "9s": "9s",
    "east": "E", "south": "S", "west": "W", "north": "N",
    "red": "C", "green": "F", "white": "P",
    "ton": "E", "nan": "S", "sha": "W", "pei": "N",
    "chun": "C", "hatsu": "F", "haku": "P",
    # Camerash label names
    "dots-1": "1p", "dots-2": "2p", "dots-3": "3p", "dots-4": "4p",
    "dots-5": "5p", "dots-6": "6p", "dots-7": "7p", "dots-8": "8p", "dots-9": "9p",
    "bamboo-1": "1s", "bamboo-2": "2s", "bamboo-3": "3s", "bamboo-4": "4s",
    "bamboo-5": "5s", "bamboo-6": "6s", "bamboo-7": "7s", "bamboo-8": "8s", "bamboo-9": "9s",
    "characters-1": "1m", "characters-2": "2m", "characters-3": "3m", "characters-4": "4m",
    "characters-5": "5m", "characters-6": "6m", "characters-7": "7m", "characters-8": "8m",
    "characters-9": "9m",
    "honors-east": "E", "honors-south": "S", "honors-west": "W", "honors-north": "N",
    "honors-red": "C", "honors-green": "F", "honors-white": "P",
}

# Valid Japanese mahjong tile codes (34 types)
VALID_TILES = {
    *(f"{i}m" for i in range(1, 10)),
    *(f"{i}p" for i in range(1, 10)),
    *(f"{i}s" for i in range(1, 10)),
    "E", "S", "W", "N", "P", "F", "C",
}


def convert_camerash():
    """Convert existing Camerash dataset."""
    if not DATA_CSV.exists() or not TILES_RESIZED.exists():
        print("Camerash dataset not found, skipping")
        return 0

    output = OUTPUT_DIR / "camerash"
    output.mkdir(parents=True, exist_ok=True)
    count = 0

    with open(DATA_CSV, encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            label_name = row["label-name"]
            tile_code = TILE_CODE_MAP.get(label_name)
            if tile_code is None or tile_code not in VALID_TILES:
                continue

            src = TILES_RESIZED / row["image-name"]
            if not src.exists():
                continue

            # Create tile_code directory
            tile_dir = output / tile_code
            tile_dir.mkdir(exist_ok=True)
            shutil.copy2(src, tile_dir / src.name)
            count += 1

    print(f"Camerash: {count} images converted")
    return count


def convert_kaggle(kaggle_dir: Path):
    """Convert Kaggle 'Mahjong' dataset.

    Expected structure: kaggle_dir/train/<class_name>/*.jpg
    or: kaggle_dir/<class_name>/*.jpg
    """
    if not kaggle_dir.exists():
        print(f"Kaggle directory not found: {kaggle_dir}")
        return 0

    output = OUTPUT_DIR / "kaggle"
    output.mkdir(parents=True, exist_ok=True)
    count = 0

    # Try to find class directories
    for class_dir in sorted(kaggle_dir.rglob("*")):
        if not class_dir.is_dir():
            continue

        # Try to map directory name to tile code
        dir_name = class_dir.name.lower().replace(" ", "").replace("-", "")
        tile_code = None

        # Try direct mapping
        for key, code in TILE_CODE_MAP.items():
            if dir_name == key.lower().replace("-", ""):
                tile_code = code
                break

        # Try number+suit pattern (e.g., "1man", "2pin", "3sou")
        if tile_code is None:
            for i in range(1, 10):
                if dir_name in (f"{i}man", f"man{i}", f"{i}m"):
                    tile_code = f"{i}m"
                elif dir_name in (f"{i}pin", f"pin{i}", f"{i}p"):
                    tile_code = f"{i}p"
                elif dir_name in (f"{i}sou", f"sou{i}", f"{i}s"):
                    tile_code = f"{i}s"

        if tile_code is None or tile_code not in VALID_TILES:
            continue

        tile_dir = output / tile_code
        tile_dir.mkdir(exist_ok=True)

        for img_file in class_dir.iterdir():
            if img_file.suffix.lower() in (".jpg", ".jpeg", ".png"):
                shutil.copy2(img_file, tile_dir / f"kaggle_{img_file.name}")
                count += 1

    print(f"Kaggle: {count} images converted")
    return count


def download_kaggle():
    """Download Kaggle dataset using kaggle CLI."""
    try:
        import kaggle
        kaggle_dir = BASE_DIR / "kaggle_mahjong"
        kaggle_dir.mkdir(exist_ok=True)
        print("Downloading Kaggle 'mexwell/mahjong' dataset...")
        os.system(f"kaggle datasets download -d mexwell/mahjong -p {kaggle_dir} --unzip")
        return kaggle_dir
    except Exception as e:
        print(f"Kaggle download failed: {e}")
        print("Please download manually from https://www.kaggle.com/datasets/mexwell/mahjong")
        print("Then run: python ml/scripts/download_datasets.py --kaggle-dir /path/to/extracted")
        return None


def print_stats():
    """Print dataset statistics."""
    if not OUTPUT_DIR.exists():
        return

    print("\n=== Dataset Statistics ===")
    total = 0
    for source_dir in sorted(OUTPUT_DIR.iterdir()):
        if not source_dir.is_dir():
            continue
        source_total = 0
        for tile_dir in sorted(source_dir.iterdir()):
            if tile_dir.is_dir():
                count = len(list(tile_dir.glob("*")))
                source_total += count
        print(f"{source_dir.name}: {source_total} images")
        total += source_total

    print(f"\nTotal: {total} images")

    # Per-tile stats
    tile_counts: dict[str, int] = {}
    for source_dir in OUTPUT_DIR.iterdir():
        if not source_dir.is_dir():
            continue
        for tile_dir in source_dir.iterdir():
            if tile_dir.is_dir():
                count = len(list(tile_dir.glob("*")))
                tile_counts[tile_dir.name] = tile_counts.get(tile_dir.name, 0) + count

    print("\nPer tile:")
    for tile in sorted(tile_counts.keys()):
        print(f"  {tile}: {tile_counts[tile]}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--kaggle-dir", type=str, help="Path to manually downloaded Kaggle dataset")
    parser.add_argument("--skip-camerash", action="store_true")
    parser.add_argument("--skip-kaggle", action="store_true")
    args = parser.parse_args()

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    if not args.skip_camerash:
        convert_camerash()

    if not args.skip_kaggle:
        if args.kaggle_dir:
            convert_kaggle(Path(args.kaggle_dir))
        else:
            kaggle_dir = download_kaggle()
            if kaggle_dir:
                convert_kaggle(kaggle_dir)

    print_stats()


if __name__ == "__main__":
    main()
