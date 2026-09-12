from __future__ import annotations

from functools import lru_cache

from app.domain.tiles import TERMINAL_HONOR_INDICES, validate_counts


@lru_cache(maxsize=500_000)
def _standard_search(
    counts: tuple[int, ...], completed_melds: int, melds: int, pairs: int, shapes: int
) -> int:
    first = next((index for index, count in enumerate(counts) if count), -1)
    if first < 0:
        usable_shapes = min(shapes, 4 - completed_melds - melds)
        return 8 - 2 * (completed_melds + melds) - usable_shapes - min(pairs, 1)

    def branch(removals: tuple[int, ...], next_melds: int, next_pairs: int, next_shapes: int) -> int:
        work = list(counts)
        for index in removals:
            work[index] -= 1
        return _standard_search(tuple(work), completed_melds, next_melds, next_pairs, next_shapes)

    # Ignoring an isolated tile is necessary to explore all incomplete forms.
    best = branch((first,), melds, pairs, shapes)
    if counts[first] >= 3:
        best = min(best, branch((first, first, first), melds + 1, pairs, shapes))
    if first < 27 and first % 9 <= 6 and counts[first + 1] and counts[first + 2]:
        best = min(best, branch((first, first + 1, first + 2), melds + 1, pairs, shapes))
    if counts[first] >= 2:
        best = min(best, branch((first, first), melds, pairs + 1, shapes))
    if first < 27 and first % 9 <= 7 and counts[first + 1]:
        best = min(best, branch((first, first + 1), melds, pairs, shapes + 1))
    if first < 27 and first % 9 <= 6 and counts[first + 2]:
        best = min(best, branch((first, first + 2), melds, pairs, shapes + 1))
    return best


@lru_cache(maxsize=100_000)
def standard_shanten(counts: tuple[int, ...], completed_melds: int = 0) -> int:
    validate_counts(counts)
    return _standard_search(counts, completed_melds, 0, 0, 0)


def seven_pairs_shanten(counts: tuple[int, ...]) -> int:
    pairs = sum(count >= 2 for count in counts)
    distinct = sum(count > 0 for count in counts)
    return 6 - pairs + max(0, 7 - distinct)


def thirteen_orphans_shanten(counts: tuple[int, ...]) -> int:
    distinct = sum(counts[index] > 0 for index in TERMINAL_HONOR_INDICES)
    pair = any(counts[index] >= 2 for index in TERMINAL_HONOR_INDICES)
    return 13 - distinct - int(pair)


def calculate_shanten(counts: tuple[int, ...], completed_melds: int = 0) -> int:
    values = [standard_shanten(counts, completed_melds)]
    if completed_melds == 0:
        values.extend((seven_pairs_shanten(counts), thirteen_orphans_shanten(counts)))
    return min(values)
