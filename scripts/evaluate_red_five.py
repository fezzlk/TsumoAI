#!/usr/bin/env python3
"""Evaluate the red-five (赤5) colour check on the training store.

Mirrors `mobile/lib/services/red_five_detector.dart`: for each 5m/5p/5s and
5mr/5pr/5sr crop in `training-data/index.json`, measure the share of ink that
is red and report how well `--threshold` separates red from plain fives.

Usage:
  python scripts/evaluate_red_five.py --bucket correctdata [--threshold 0.8]

Needs `gcloud` access to the bucket. Images are cached under `--cache`.
"""

import argparse
import colorsys
import json
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image

CODES = ("5m", "5p", "5s", "5mr", "5pr", "5sr")


def red_ink_share(path: Path) -> float:
    img = Image.open(path).convert("RGB").resize((96, 128), Image.BILINEAR)
    a = np.asarray(img, dtype=np.float32) / 255.0
    h, w, _ = a.shape
    a = a[int(h * 0.12):int(h * 0.88), int(w * 0.12):int(w * 0.88)]
    hsv = np.array([colorsys.rgb_to_hsv(*p) for p in a.reshape(-1, 3)])
    hue, sat, val = hsv[:, 0], hsv[:, 1], hsv[:, 2]
    dark = (val < 0.35) | ((val < 0.62) & (sat < 0.3))
    coloured = (sat > 0.35) & (val > 0.25)
    ink = dark | coloured
    red = coloured & ((hue < 0.05) | (hue > 0.93))
    n = int(ink.sum())
    return float(red.sum() / n) if n else 0.0


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bucket", default="correctdata")
    parser.add_argument("--threshold", type=float, default=0.8)
    parser.add_argument("--cache", default=".cache/red_five")
    args = parser.parse_args()

    cache = Path(args.cache)
    cache.mkdir(parents=True, exist_ok=True)
    index = cache / "index.json"
    subprocess.run(
        ["gcloud", "storage", "cp",
         f"gs://{args.bucket}/training-data/index.json", str(index)],
        check=True,
    )
    entries = [e for e in json.loads(index.read_text()) if e.get("tile_code") in CODES]
    missing = [
        f"gs://{args.bucket}/{e['image_path']}" for e in entries
        if not (cache / Path(e["image_path"]).name).exists()
    ]
    if missing:
        # Some indexed images may have been deleted; skip those.
        subprocess.run(
            ["gcloud", "storage", "cp", "-I", str(cache)],
            input="\n".join(missing), text=True, check=False,
        )

    results: dict[str, list[float]] = {code: [] for code in CODES}
    wrong = []
    for e in entries:
        path = cache / Path(e["image_path"]).name
        if not path.exists():
            continue
        code = e["tile_code"]
        share = red_ink_share(path)
        results[code].append(share)
        if (share >= args.threshold) != code.endswith("r"):
            wrong.append((code, path.name, round(share, 2)))

    for code in CODES:
        values = sorted(results[code])
        if values:
            print(f"{code}: n={len(values)} min={values[0]:.2f} max={values[-1]:.2f}")
    total = sum(len(v) for v in results.values())
    print(f"threshold {args.threshold}: {total - len(wrong)}/{total} correct")
    for item in wrong:
        print("  wrong:", *item)


if __name__ == "__main__":
    main()
