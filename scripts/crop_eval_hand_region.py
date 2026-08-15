#!/usr/bin/env python3
"""Crop the 6 labeled real-photo eval cases down to just the 14 hand tiles.

All 6 photos in data/eval_images/ include extra/unused tiles in the frame
(per each case's "note" in data/recognition_eval_set.jsonl), which makes the
raw detector-count comparison in compare_tile_detectors.py unfair: an
over-detecting model may just be correctly finding the extra tiles.

Crop boxes below were determined by visually inspecting each EXIF-corrected
photo (see Phase A plan) and are fractions (left, top, right, bottom) of the
EXIF-corrected image, generous enough to include the full hand while
excluding the extra tiles visible elsewhere in frame.

Writes cropped JPEGs to data/eval_images_cropped/ and a matching
data/recognition_eval_set_cropped.jsonl (same corrected_tiles, new image_path).
"""

from __future__ import annotations

import json
from pathlib import Path

import pillow_heif
from PIL import Image, ImageOps

pillow_heif.register_heif_opener()

BASE_DIR = Path(__file__).resolve().parent.parent
SRC_JSONL = BASE_DIR / "data" / "recognition_eval_set.jsonl"
OUT_DIR = BASE_DIR / "data" / "eval_images_cropped"
OUT_JSONL = BASE_DIR / "data" / "recognition_eval_set_cropped.jsonl"

# (left, top, right, bottom) as fractions of the EXIF-corrected image.
CROP_BOXES: dict[str, tuple[float, float, float, float]] = {
    "case-001": (0.352, 0.021, 0.533, 0.950),
    "case-002": (0.352, 0.021, 0.533, 0.964),
    "case-003": (0.333, 0.000, 0.495, 0.936),
    "case-004": (0.352, 0.000, 0.533, 0.936),
    "case-005": (0.343, 0.000, 0.514, 0.964),
    "case-006": (0.390, 0.000, 0.581, 0.993),
}


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    cases = [json.loads(line) for line in SRC_JSONL.read_text().splitlines() if line.strip()]

    out_rows = []
    for case in cases:
        case_id = case["case_id"]
        box = CROP_BOXES.get(case_id)
        if box is None:
            continue  # unlabeled cases (case-007/008) skipped

        src_path = BASE_DIR / case["image_path"]
        with Image.open(src_path) as img:
            img = ImageOps.exif_transpose(img).convert("RGB")
            w, h = img.size
            left, top, right, bottom = box
            crop_box = (int(left * w), int(top * h), int(right * w), int(bottom * h))
            cropped = img.crop(crop_box)

        out_path = OUT_DIR / f"{case_id}.jpg"
        cropped.save(out_path, quality=95)
        print(f"{case_id}: {src_path.name} {w}x{h} -> {out_path.name} {cropped.size}")

        out_rows.append(
            {
                "case_id": case_id,
                "image_path": str(out_path.relative_to(BASE_DIR)),
                "corrected_tiles": case["corrected_tiles"],
                "note": "cropped to hand-only region from " + case["image_path"],
            }
        )

    with OUT_JSONL.open("w") as f:
        for row in out_rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    print(f"\n{len(out_rows)}件のトリミング済みケースを書き出し: {OUT_JSONL.relative_to(BASE_DIR)}")


if __name__ == "__main__":
    main()
