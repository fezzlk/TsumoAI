#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path


SUPPORTED_EXTS = {".jpg", ".jpeg", ".png", ".heic", ".heif", ".webp"}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Initialize recognition evaluation set JSONL.")
    p.add_argument("--images-dir", default="data/eval_images", help="Directory containing hand images")
    p.add_argument("--output", default="data/recognition_eval_set.jsonl", help="Output JSONL path")
    p.add_argument("--limit", type=int, default=20, help="Number of cases to include")
    return p.parse_args()


def iter_images(images_dir: Path) -> list[Path]:
    return sorted(
        p for p in images_dir.rglob("*") if p.is_file() and p.suffix.lower() in SUPPORTED_EXTS
    )


def main() -> int:
    args = parse_args()
    images_dir = Path(args.images_dir)
    output = Path(args.output)

    if not images_dir.exists():
        print(f"images directory not found: {images_dir}")
        return 1

    images = iter_images(images_dir)[: args.limit]
    if not images:
        print(f"no supported images found in: {images_dir}")
        return 1

    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8") as f:
        for idx, path in enumerate(images, start=1):
            row = {
                "case_id": f"case-{idx:03d}",
                "image_path": str(path),
                "corrected_tiles": [],
                "note": "",
            }
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    print(f"created: {output}")
    print(f"cases: {len(images)}")
    print("next: fill corrected_tiles with exactly 14 tile codes for each case.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
