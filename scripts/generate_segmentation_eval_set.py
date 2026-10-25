#!/usr/bin/env python3
"""Generate the synthetic tile-segmentation evaluation set (FEZ-245).

Renders tile illustrations (`mobile/assets/tiles/`) onto a felt-coloured
background with exact per-tile boxes, so the segmenter can be measured on
the layouts it is known to struggle with — more than 14 tiles (槓子), gaps
between groups (melds set apart), and rows that are not one straight line —
alongside the baseline it already handles. Deterministic for a given seed.

Usage:
  python scripts/generate_segmentation_eval_set.py [--out DIR] [--seed N]

Writes DIR/<case_id>.png and DIR/manifest.json:
  {"version": 1, "cases": [{"case_id", "category", "image", "tile_count",
    "boxes": [[x, y, w, h], ...] (left to right, then top to bottom)}]}
"""

import argparse
import json
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
TILES = sorted((ROOT / "mobile/assets/tiles").glob("Mpu*.png"))
VERSION = 1
CANVAS = (1600, 900)  # landscape 16:9, like the app's framed capture


def felt(rng: random.Random) -> Image.Image:
    base = (rng.randint(20, 40), rng.randint(95, 125), rng.randint(60, 85))
    img = Image.new("RGB", CANVAS, base)
    noise = Image.effect_noise(CANVAS, 18).convert("RGB")
    img = Image.blend(img, noise, 0.08)
    # A soft lighting gradient, as on a real table.
    shade = Image.linear_gradient("L").rotate(rng.choice([0, 90, 180, 270])).resize(CANVAS)
    dark = Image.new("RGB", CANVAS, (0, 0, 0))
    return Image.composite(img, Image.blend(img, dark, 0.25), shade)


def tile_image(rng: random.Random, width: int, sideways: bool = False) -> Image.Image:
    src = Image.open(rng.choice(TILES)).convert("RGBA")
    height = round(width * src.height / src.width)
    tile = src.resize((width, height), Image.LANCZOS)
    # Real tiles show a darker bevel where two faces meet; without it the
    # seams between touching tiles are unrealistically invisible.
    bevel = Image.new("RGBA", tile.size, (0, 0, 0, 0))
    ImageDraw.Draw(bevel).rounded_rectangle(
        [0, 0, width - 1, height - 1], radius=max(2, width // 10),
        outline=(70, 70, 60, 150), width=2,
    )
    tile = Image.alpha_composite(tile, Image.composite(bevel, Image.new("RGBA", tile.size), tile.getchannel("A")))
    return tile.rotate(90, expand=True) if sideways else tile


def place(canvas: Image.Image, tile: Image.Image, x: float, y: float, angle: float):
    """Paste [tile] with its top-left near (x, y), rotated by [angle] degrees
    about its centre; returns the axis-aligned box of the visible tile."""
    rotated = tile.rotate(angle, expand=True, resample=Image.BICUBIC)
    cx = x + tile.width / 2
    cy = y + tile.height / 2
    left = round(cx - rotated.width / 2)
    top = round(cy - rotated.height / 2)
    shadow = Image.new("RGBA", rotated.size, (0, 0, 0, 0))
    shadow.putalpha(rotated.getchannel("A").point(lambda a: int(a * 0.35)))
    canvas.paste(shadow.filter(ImageFilter.GaussianBlur(3)), (left + 4, top + 5), shadow.filter(ImageFilter.GaussianBlur(3)))
    canvas.paste(rotated, (left, top), rotated)
    bbox = rotated.getchannel("A").getbbox()
    return [left + bbox[0], top + bbox[1], bbox[2] - bbox[0], bbox[3] - bbox[1]]


def render(rng: random.Random, groups, *, width: int, gap: int, row_angle: float = 0.0,
           rows=None, stagger: int = 0):
    """groups: list of lists of booleans (True = sideways tile), drawn left
    to right; gap is the space between groups. rows maps group index to row
    number for multi-row layouts; stagger shifts every other group down."""
    canvas = felt(rng)
    tile_h = round(width * 128 / 82)
    rows = rows or [0] * len(groups)
    row_widths = {}
    for g, row in zip(groups, rows):
        w = sum(tile_h if s else width for s in g) + max(0, len(g) - 1) * 1
        row_widths[row] = row_widths.get(row, 0) + w + gap
    n_rows = max(rows) + 1
    boxes = []
    cursor = {r: (CANVAS[0] - (row_widths[r] - gap)) / 2 for r in row_widths}
    top0 = CANVAS[1] / 2 - (n_rows * tile_h + (n_rows - 1) * tile_h * 0.4) / 2
    rad = math.radians(row_angle)
    for index, (group, row) in enumerate(zip(groups, rows)):
        y_row = top0 + row * tile_h * 1.4 + (stagger if index % 2 else 0)
        for sideways in group:
            tile = tile_image(rng, width, sideways)
            x = cursor[row]
            # Tilt the whole row about the canvas centre.
            dx = x - CANVAS[0] / 2
            y = y_row + dx * math.tan(rad) + (tile_h - tile.height if sideways else 0)
            boxes.append(place(canvas, tile, x, y, -row_angle + rng.uniform(-1.2, 1.2)))
            cursor[row] += tile.width + rng.choice([0, 1, 1, 2])
        cursor[row] += gap
    boxes.sort(key=lambda b: (round((b[1] + b[3] / 2) / (tile_h * 0.9)), b[0]))
    return canvas, boxes


def cases(rng: random.Random):
    plain = lambda n: [False] * n  # noqa: E731
    out = []

    def add(category, groups, **kw):
        width = kw.pop("width", rng.randint(62, 80))
        gap = kw.pop("gap", rng.randint(0, 2))
        out.append((category, groups, dict(width=width, gap=gap, **kw)))

    for n in (13, 14, 14, 13, 14):
        add("baseline", [plain(n)])
    # 槓子: 15-18 tiles, closed kans in line, open kans with a sideways tile.
    for kans in (1, 1, 2, 2, 3, 4):
        add("kan_inline", [plain(14 + kans)], width=rng.randint(56, 68))
    for kans in (1, 2, 3):
        groups = [plain(14 - 3 * kans)] + [[False, True, False, False] for _ in range(kans)]
        add("kan_sideways", groups, gap=rng.randint(20, 60), width=rng.randint(56, 66))
    # Gaps: hand plus melds set apart.
    for split in ([11, 3], [8, 3, 3], [5, 3, 3, 3], [10, 4], [7, 7]):
        add("gaps", [plain(k) for k in split], gap=rng.randint(30, 110))
    # Not one straight line.
    add("two_rows", [plain(9), plain(5)], rows=[0, 1], gap=0)
    add("two_rows", [plain(8), plain(3), plain(3)], rows=[0, 1, 1], gap=40)
    add("staggered", [plain(11), plain(3)], gap=50, stagger=60)
    add("staggered", [plain(8), plain(3), plain(3)], gap=40, stagger=45)
    for angle in (6, -9, 14):
        add("tilted", [plain(14)], row_angle=angle)
    return out


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(ROOT / "data/segmentation_eval_v1"))
    parser.add_argument("--seed", type=int, default=245)
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    rng = random.Random(args.seed)
    manifest = {"version": VERSION, "seed": args.seed, "cases": []}
    for index, (category, groups, kw) in enumerate(cases(rng), start=1):
        image, boxes = render(rng, groups, **kw)
        case_id = f"seg-{index:03d}-{category}"
        image.save(out / f"{case_id}.png")
        manifest["cases"].append({
            "case_id": case_id,
            "category": category,
            "image": f"{case_id}.png",
            "tile_count": len(boxes),
            "boxes": boxes,
        })
    (out / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1))
    print(f"{len(manifest['cases'])} cases -> {out}")


if __name__ == "__main__":
    main()
