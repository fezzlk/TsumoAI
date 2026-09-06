from __future__ import annotations

from dataclasses import dataclass

from app.domain.shanten import calculate_shanten
from app.domain.tiles import index_to_tile, validate_counts


@dataclass(frozen=True)
class Wait:
    tile: str
    remaining: int


@dataclass(frozen=True)
class DiscardAnalysis:
    discard: str
    shanten: int
    waits: tuple[Wait, ...]


def enumerate_improving_tiles(
    counts: tuple[int, ...], completed_melds: int = 0, visible_counts: tuple[int, ...] | None = None
) -> tuple[Wait, ...]:
    validate_counts(counts)
    visible = visible_counts or counts
    current = calculate_shanten(counts, completed_melds)
    waits: list[Wait] = []
    for index in range(34):
        if counts[index] >= 4:
            continue
        work = list(counts)
        work[index] += 1
        if calculate_shanten(tuple(work), completed_melds) < current:
            waits.append(Wait(index_to_tile(index), max(0, 4 - visible[index])))
    return tuple(waits)


def analyze_discards(
    counts: tuple[int, ...], completed_melds: int = 0, visible_counts: tuple[int, ...] | None = None
) -> tuple[DiscardAnalysis, ...]:
    validate_counts(counts)
    visible = visible_counts or counts
    results: list[DiscardAnalysis] = []
    for index, count in enumerate(counts):
        if not count:
            continue
        work = list(counts)
        work[index] -= 1
        reduced = tuple(work)
        results.append(
            DiscardAnalysis(
                discard=index_to_tile(index),
                shanten=calculate_shanten(reduced, completed_melds),
                waits=enumerate_improving_tiles(reduced, completed_melds, visible),
            )
        )
    return tuple(sorted(results, key=lambda item: (item.shanten, -sum(wait.remaining for wait in item.waits), item.discard)))
