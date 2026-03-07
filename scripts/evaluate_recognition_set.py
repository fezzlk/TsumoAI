#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from io import BytesIO
from pathlib import Path

from PIL import Image

try:  # pragma: no cover
    from pillow_heif import register_heif_opener

    register_heif_opener()
except Exception:  # pragma: no cover
    pass

from app.hand_extraction import extract_hand_from_image
from app.validators import validate_tile


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Evaluate recognition accuracy on labeled eval set.")
    p.add_argument("--input", default="data/recognition_eval_set.jsonl", help="Eval JSONL path")
    p.add_argument("--top", type=int, default=20, help="Top confusion pairs to print")
    return p.parse_args()


def _load_rows(path: Path) -> list[dict]:
    rows: list[dict] = []
    if not path.exists():
        return rows
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def _to_jpeg_bytes(image_path: Path) -> bytes:
    with Image.open(image_path) as img:
        rgb = img.convert("RGB")
        out = BytesIO()
        rgb.save(out, format="JPEG", quality=95)
        return out.getvalue()


def _validate_gt(gt: list[str]) -> bool:
    if len(gt) != 14:
        return False
    try:
        for t in gt:
            validate_tile(t)
    except Exception:
        return False
    return True


def main() -> int:
    args = parse_args()
    rows = _load_rows(Path(args.input))
    if not rows:
        print(f"no rows found: {args.input}")
        return 1

    valid_rows = [r for r in rows if _validate_gt(r.get("corrected_tiles", []))]
    if not valid_rows:
        print("no labeled rows (corrected_tiles length must be 14)")
        return 1

    tile_total = 0
    tile_correct = 0
    exact_total = 0
    exact_correct = 0
    confusion: dict[tuple[str, str], int] = {}
    failed_cases = 0

    for row in valid_rows:
        image_path = Path(row["image_path"])
        if not image_path.exists():
            failed_cases += 1
            continue

        try:
            payload = extract_hand_from_image(_to_jpeg_bytes(image_path))
            pred = [slot["top"] for slot in payload.get("slots", [])]
        except Exception:
            failed_cases += 1
            continue

        gt = row["corrected_tiles"]
        if len(pred) != 14:
            failed_cases += 1
            continue

        exact_total += 1
        if pred == gt:
            exact_correct += 1

        for p, g in zip(pred, gt):
            tile_total += 1
            if p == g:
                tile_correct += 1
            else:
                confusion[(g, p)] = confusion.get((g, p), 0) + 1

    if exact_total == 0 or tile_total == 0:
        print("evaluation failed: no successful cases")
        return 1

    print(f"cases_total={len(valid_rows)} cases_scored={exact_total} cases_failed={failed_cases}")
    print(f"tile_accuracy={(tile_correct / tile_total) * 100:.2f}%")
    print(f"exact_match_rate={(exact_correct / exact_total) * 100:.2f}%")
    print("top confusions (ground_truth -> predicted):")
    for (g, p), c in sorted(confusion.items(), key=lambda x: x[1], reverse=True)[: args.top]:
        print(f"{g:>3} -> {p:<3} : {c}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
