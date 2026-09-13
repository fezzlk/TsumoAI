from __future__ import annotations

import re
from collections.abc import Iterable

TILE_PATTERN = re.compile(r"^(?:[1-9][mps]|5[mps]r|[ESWNPFC])$")
HONORS = ("E", "S", "W", "N", "P", "F", "C")
TILE_CODES = tuple(
    [f"{number}{suit}" for suit in ("m", "p", "s") for number in range(1, 10)]
    + list(HONORS)
)
TERMINAL_HONOR_INDICES = frozenset({0, 8, 9, 17, 18, 26, *range(27, 34)})


def normalize_tile(tile: str) -> str:
    if tile in {"5mr", "5pr", "5sr"}:
        return tile[:2]
    return tile


def is_tile_code(tile: str) -> bool:
    return bool(TILE_PATTERN.fullmatch(tile))


def tile_to_index(tile: str) -> int:
    normalized = normalize_tile(tile)
    if not is_tile_code(tile):
        raise ValueError(f"invalid tile code: {tile}")
    if len(normalized) == 2:
        return {"m": 0, "p": 9, "s": 18}[normalized[1]] + int(normalized[0]) - 1
    return {tile: 27 + index for index, tile in enumerate(HONORS)}[normalized]


def index_to_tile(index: int) -> str:
    if not 0 <= index < 34:
        raise ValueError(f"tile index out of range: {index}")
    if index < 27:
        return f"{index % 9 + 1}{('m', 'p', 's')[index // 9]}"
    return HONORS[index - 27]


def tiles_to_counts(tiles: Iterable[str]) -> tuple[int, ...]:
    counts = [0] * 34
    for tile in tiles:
        counts[tile_to_index(tile)] += 1
    return tuple(counts)


def validate_counts(counts: tuple[int, ...]) -> None:
    if len(counts) != 34:
        raise ValueError("tile counts must have exactly 34 entries")
    if any(count < 0 or count > 4 for count in counts):
        raise ValueError("each normalized tile count must be between 0 and 4")
