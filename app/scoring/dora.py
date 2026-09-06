from __future__ import annotations

from collections import Counter

from app.domain.tiles import normalize_tile
from app.schemas import ContextInput, DoraBreakdown, HandInput, YakuItem


def evaluate_dora(hand: HandInput, context: ContextInput) -> tuple[DoraBreakdown, tuple[YakuItem, ...]]:
    breakdown = DoraBreakdown(
        dora=_count_dora(hand, context.dora_indicators),
        aka_dora=context.aka_dora_count,
        ura_dora=_count_dora(hand, context.ura_dora_indicators),
    )
    items = []
    if breakdown.dora:
        items.append(YakuItem(name="ドラ", han=breakdown.dora))
    if breakdown.aka_dora:
        items.append(YakuItem(name="赤ドラ", han=breakdown.aka_dora))
    if breakdown.ura_dora:
        items.append(YakuItem(name="裏ドラ", han=breakdown.ura_dora))
    return breakdown, tuple(items)


def _count_dora(hand: HandInput, indicators: list[str]) -> int:
    counts = Counter(_all_tiles(hand))
    return sum(counts.get(_next_dora(indicator), 0) for indicator in indicators)


def _all_tiles(hand: HandInput) -> list[str]:
    tiles = [normalize_tile(tile) for tile in hand.closed_tiles]
    for meld in hand.melds:
        tiles.extend(normalize_tile(tile) for tile in meld.tiles)
    return tiles


def _next_dora(indicator: str) -> str:
    tile = normalize_tile(indicator)
    if len(tile) == 2:
        number = int(tile[0])
        return f"{1 if number == 9 else number + 1}{tile[1]}"
    if tile in {"E", "S", "W", "N"}:
        order = ("E", "S", "W", "N")
    else:
        order = ("P", "F", "C")
    return order[(order.index(tile) + 1) % len(order)]
