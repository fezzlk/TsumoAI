from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache

from app.domain.tiles import TERMINAL_HONOR_INDICES, index_to_tile, validate_counts


@dataclass(frozen=True)
class MeldPattern:
    kind: str
    tile: str


@dataclass(frozen=True)
class StandardDecomposition:
    pair: str
    melds: tuple[MeldPattern, ...]


@lru_cache(maxsize=100_000)
def _collect_melds(counts: tuple[int, ...], needed: int) -> tuple[tuple[MeldPattern, ...], ...]:
    if needed == 0:
        return ((),) if not any(counts) else ()
    first = next((index for index, count in enumerate(counts) if count), -1)
    if first < 0:
        return ()

    found: list[tuple[MeldPattern, ...]] = []
    work = list(counts)
    if work[first] >= 3:
        work[first] -= 3
        for rest in _collect_melds(tuple(work), needed - 1):
            found.append((MeldPattern("pon", index_to_tile(first)), *rest))
        work[first] += 3
    if first < 27 and first % 9 <= 6 and work[first + 1] and work[first + 2]:
        work[first] -= 1
        work[first + 1] -= 1
        work[first + 2] -= 1
        for rest in _collect_melds(tuple(work), needed - 1):
            found.append((MeldPattern("chi", index_to_tile(first)), *rest))
    return tuple(found)


def standard_decompositions(counts: tuple[int, ...], completed_melds: int = 0) -> tuple[StandardDecomposition, ...]:
    validate_counts(counts)
    needed = 4 - completed_melds
    if needed < 0 or sum(counts) != needed * 3 + 2:
        return ()
    results: list[StandardDecomposition] = []
    for pair_index, count in enumerate(counts):
        if count < 2:
            continue
        work = list(counts)
        work[pair_index] -= 2
        for melds in _collect_melds(tuple(work), needed):
            results.append(StandardDecomposition(index_to_tile(pair_index), melds))
    return tuple(results)


def is_seven_pairs(counts: tuple[int, ...], completed_melds: int = 0) -> bool:
    return completed_melds == 0 and sum(count == 2 for count in counts) == 7 and all(count in (0, 2) for count in counts)


def is_thirteen_orphans(counts: tuple[int, ...], completed_melds: int = 0) -> bool:
    if completed_melds:
        return False
    return all(counts[index] >= 1 for index in TERMINAL_HONOR_INDICES) and any(
        counts[index] >= 2 for index in TERMINAL_HONOR_INDICES
    ) and not any(counts[index] for index in range(34) if index not in TERMINAL_HONOR_INDICES)


def is_winning_hand(counts: tuple[int, ...], completed_melds: int = 0) -> bool:
    validate_counts(counts)
    return bool(standard_decompositions(counts, completed_melds)) or is_seven_pairs(
        counts, completed_melds
    ) or is_thirteen_orphans(counts, completed_melds)
