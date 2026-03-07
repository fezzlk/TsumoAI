from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from PIL import Image


TILE34 = [
    "1m",
    "2m",
    "3m",
    "4m",
    "5m",
    "6m",
    "7m",
    "8m",
    "9m",
    "1p",
    "2p",
    "3p",
    "4p",
    "5p",
    "6p",
    "7p",
    "8p",
    "9p",
    "1s",
    "2s",
    "3s",
    "4s",
    "5s",
    "6s",
    "7s",
    "8s",
    "9s",
    "E",
    "S",
    "W",
    "N",
    "P",
    "F",
    "C",
]


def _tile_to_filename(tile: str) -> str:
    if len(tile) == 2 and tile[0].isdigit() and tile[1] in {"m", "p", "s"}:
        return f"Mpu{tile[0]}{tile[1]}.png"
    honor_map = {"E": "1", "S": "2", "W": "3", "N": "4", "P": "5", "F": "6", "C": "7"}
    return f"Mpu{honor_map[tile]}z.png"


def _crop_orange_header(image: Image.Image) -> Image.Image:
    rgb = image.convert("RGB")
    w, h = rgb.size
    stable = 0
    cut_y = 6
    for y in range(min(24, h)):
        row = [rgb.getpixel((x, y)) for x in range(0, w, 2)]
        count = max(len(row), 1)
        r = sum(px[0] for px in row) / count
        g = sum(px[1] for px in row) / count
        b = sum(px[2] for px in row) / count
        orange_like = (r - b) > 35 and (g - b) > 20
        if orange_like:
            stable = 0
            continue
        stable += 1
        if stable >= 2:
            cut_y = max(0, y - 1)
            break
    cut_y = max(0, min(cut_y, h - 1))
    return rgb.crop((0, cut_y, w, h))


def _feature_vector(image: Image.Image, size: tuple[int, int] = (32, 48)) -> list[float]:
    gray = image.convert("L").resize(size)
    pixels = [gray.getpixel((x, y)) / 255.0 for y in range(size[1]) for x in range(size[0])]
    mean = sum(pixels) / max(len(pixels), 1)
    centered = [p - mean for p in pixels]
    norm = sum(v * v for v in centered) ** 0.5 or 1.0
    return [v / norm for v in centered]


def _cosine(a: list[float], b: list[float]) -> float:
    return max(-1.0, min(1.0, sum(x * y for x, y in zip(a, b))))


@dataclass(frozen=True)
class TileWeightModel:
    reliability: dict[str, float]
    similarity: dict[str, dict[str, float]]


@lru_cache(maxsize=1)
def build_tile_weight_model() -> TileWeightModel:
    tile_dir = Path(__file__).resolve().parent / "static" / "tiles"
    vectors: dict[str, list[float]] = {}
    for tile in TILE34:
        path = tile_dir / _tile_to_filename(tile)
        with Image.open(path) as img:
            cropped = _crop_orange_header(img)
            vectors[tile] = _feature_vector(cropped)

    similarity: dict[str, dict[str, float]] = {}
    reliability: dict[str, float] = {}
    for t in TILE34:
        row: dict[str, float] = {}
        for u in TILE34:
            if t == u:
                continue
            sim = (_cosine(vectors[t], vectors[u]) + 1.0) / 2.0
            row[u] = sim
        similarity[t] = row

        hardest = sorted(row.values(), reverse=True)[:4]
        mean_hardest = sum(hardest) / max(len(hardest), 1)
        distinctiveness = 1.0 - mean_hardest
        weight = 0.9 + (distinctiveness * 0.4)
        reliability[t] = max(0.85, min(1.15, weight))

    return TileWeightModel(reliability=reliability, similarity=similarity)


def tile_reliability_weight(tile: str) -> float:
    return build_tile_weight_model().reliability.get(tile, 1.0)


def tile_similarity(a: str, b: str) -> float:
    if a == b:
        return 1.0
    return build_tile_weight_model().similarity.get(a, {}).get(b, 0.0)
