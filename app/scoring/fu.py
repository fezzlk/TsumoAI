from __future__ import annotations

from app.domain.tiles import normalize_tile, tile_to_index
from app.schemas import ContextInput, FuBreakdownItem, HandInput, RuleSet


def calculate_fu(
    melds: list[tuple[str, str]],
    pair: str,
    hand: HandInput,
    context: ContextInput,
    rules: RuleSet,
    has_pinfu: bool,
    declared_meld_count: int,
) -> tuple[int, list[FuBreakdownItem]]:
    if has_pinfu and context.win_type == "tsumo":
        return 20, [FuBreakdownItem(name="副底", fu=20)]
    if has_pinfu and context.win_type == "ron":
        return 30, [FuBreakdownItem(name="副底", fu=20), FuBreakdownItem(name="門前ロン", fu=10)]

    base = [FuBreakdownItem(name="副底", fu=20)]
    if context.win_type == "tsumo":
        base.append(FuBreakdownItem(name="ツモ", fu=2))
    if context.win_type == "ron" and not any(meld.open for meld in hand.melds):
        base.append(FuBreakdownItem(name="門前ロン", fu=10))

    entries: list[dict] = [
        {"kind": kind, "tile": tile, "open": False} for kind, tile in melds[declared_meld_count:]
    ]
    for declared in hand.melds:
        tiles = [normalize_tile(tile) for tile in declared.tiles]
        kind = "chi" if declared.type == "chi" else "pon" if declared.type == "pon" else "kan"
        base_tile = min(tiles, key=tile_to_index) if kind == "chi" else tiles[0]
        entries.append({"kind": kind, "tile": base_tile, "open": declared.open})

    win = normalize_tile(hand.win_tile)
    targets: list[tuple[str, int]] = []
    if normalize_tile(pair) == win:
        targets.append(("pair", -1))
    for index, meld in enumerate(entries):
        if win in _meld_tiles(meld["kind"], meld["tile"]):
            targets.append(("meld", index))
    if not targets:
        targets = [("meld", -1)]

    best_total = sum(item.fu for item in base)
    best_breakdown = base
    for target_type, target_index in targets:
        details = base.copy()
        total = sum(item.fu for item in details)

        pair_fu = _pair_fu(pair, context, rules)
        if pair_fu:
            details.append(FuBreakdownItem(name="雀頭", fu=pair_fu))
            total += pair_fu

        if _has_wait_fu(target_type, target_index, entries, pair, win):
            details.append(FuBreakdownItem(name="待ち", fu=2))
            total += 2

        for index, meld in enumerate(entries):
            is_open = meld["open"] or (
                context.win_type == "ron"
                and index == target_index
                and meld["kind"] == "pon"
                and not meld["open"]
            )
            meld_fu = _meld_fu(meld["kind"], meld["tile"], is_open)
            if meld_fu:
                details.append(FuBreakdownItem(name="面子", fu=meld_fu))
                total += meld_fu

        rounded = ((total + 9) // 10) * 10
        if rounded > total:
            details.append(FuBreakdownItem(name="切り上げ", fu=rounded - total))
        if rounded >= best_total:
            best_total, best_breakdown = rounded, details
    return best_total, best_breakdown


def _has_wait_fu(target_type: str, target_index: int, entries: list[dict], pair: str, win: str) -> bool:
    if target_type == "pair":
        return True
    if target_index < 0 or entries[target_index]["kind"] != "chi":
        return False
    start = int(normalize_tile(entries[target_index]["tile"])[0])
    number = int(win[0])
    return number == start + 1 or (start == 1 and number == 3) or (start == 7 and number == 7)


def _pair_fu(pair: str, context: ContextInput, rules: RuleSet) -> int:
    tile = normalize_tile(pair)
    if tile in {"P", "F", "C"}:
        return 2
    if tile == context.round_wind.value and tile == context.seat_wind.value:
        return rules.renpu_fu
    return 2 if tile in {context.round_wind.value, context.seat_wind.value} else 0


def _meld_fu(kind: str, tile: str, is_open: bool) -> int:
    if kind == "chi":
        return 0
    terminal_or_honor = _is_terminal_or_honor(tile)
    if kind == "pon":
        return 4 if terminal_or_honor and is_open else 8 if terminal_or_honor else 2 if is_open else 4
    return 16 if terminal_or_honor and is_open else 32 if terminal_or_honor else 8 if is_open else 16


def _meld_tiles(kind: str, tile: str) -> list[str]:
    normalized = normalize_tile(tile)
    if kind == "chi":
        return [f"{int(normalized[0]) + offset}{normalized[1]}" for offset in range(3)]
    return [normalized] * (3 if kind == "pon" else 4)


def _is_terminal_or_honor(tile: str) -> bool:
    normalized = normalize_tile(tile)
    return len(normalized) == 1 or normalized[0] in {"1", "9"}
