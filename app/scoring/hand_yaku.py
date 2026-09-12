from __future__ import annotations

from collections import Counter

from app.domain.decomposition import standard_decompositions
from app.domain.tiles import normalize_tile, tile_to_index, tiles_to_counts
from app.schemas import ContextInput, HandInput, RuleSet, YakuItem


def _normalize_tile(tile: str) -> str:
    return normalize_tile(tile)


def _all_tiles(hand: HandInput) -> list[str]:
    tiles = [_normalize_tile(t) for t in hand.closed_tiles]
    for meld in hand.melds:
        tiles.extend(_normalize_tile(t) for t in meld.tiles)
    return tiles


def _wind_name(tile: str) -> str:
    return {"E": "東", "S": "南", "W": "西", "N": "北"}[tile]


def _append_yakuhai_yaku(yaku: list[YakuItem], hand: HandInput, context: ContextInput) -> int:
    han = 0
    counts = Counter(_all_tiles(hand))

    if counts.get(context.round_wind.value, 0) >= 3:
        yaku.append(YakuItem(name=f"場風 {_wind_name(context.round_wind.value)}", han=1))
        han += 1
    if counts.get(context.seat_wind.value, 0) >= 3:
        yaku.append(YakuItem(name=f"自風 {_wind_name(context.seat_wind.value)}", han=1))
        han += 1

    for tile, name in {"P": "役牌 白", "F": "役牌 發", "C": "役牌 中"}.items():
        if counts.get(tile, 0) >= 3:
            yaku.append(YakuItem(name=name, han=1))
            han += 1
    return han


def _tile_to_index(tile: str) -> int:
    return tile_to_index(tile)


def _closed_tile_counts(hand: HandInput) -> list[int]:
    return list(tiles_to_counts(hand.closed_tiles))


def _open_meld_patterns(hand: HandInput) -> list[tuple[str, str]]:
    open_melds: list[tuple[str, str]] = []
    for meld in hand.melds:
        tiles = [_normalize_tile(t) for t in meld.tiles]
        if meld.type == "chi":
            open_melds.append(("chi", min(tiles, key=_tile_to_index)))
        else:
            open_melds.append(("pon", tiles[0]))
    return open_melds


def _all_meld_patterns_with_pair(hand: HandInput) -> list[tuple[list[tuple[str, str]], str]]:
    open_melds = _open_meld_patterns(hand)
    decompositions = standard_decompositions(tiles_to_counts(hand.closed_tiles), len(open_melds))
    return [
        (open_melds + [(meld.kind, meld.tile) for meld in decomposition.melds], decomposition.pair)
        for decomposition in decompositions
    ]


def _has_chiitoitsu(hand: HandInput) -> bool:
    if hand.melds:
        return False
    counts = _closed_tile_counts(hand)
    return sum(1 for c in counts if c == 2) == 7 and all(c in {0, 2} for c in counts)


def _is_terminal_or_honor(tile: str) -> bool:
    t = _normalize_tile(tile)
    if len(t) == 1:
        return True
    if len(t) == 2 and t[0] in {"1", "9"} and t[1] in {"m", "p", "s"}:
        return True
    return False


def _has_honroutou(hand: HandInput) -> bool:
    return all(_is_terminal_or_honor(tile) for tile in _all_tiles(hand))


def _is_simple_tile(tile: str) -> bool:
    t = _normalize_tile(tile)
    return len(t) == 2 and t[1] in {"m", "p", "s"} and t[0] in {"2", "3", "4", "5", "6", "7", "8"}


def _has_tanyao(hand: HandInput, rules: RuleSet) -> bool:
    if any(m.open for m in hand.melds) and not rules.kuitan_ari:
        return False
    return all(_is_simple_tile(tile) for tile in _all_tiles(hand))


def _meld_has_terminal_or_honor(kind: str, tile: str) -> bool:
    t = _normalize_tile(tile)
    if kind == "chi":
        return len(t) == 2 and t[1] in {"m", "p", "s"} and t[0] in {"1", "7"}
    return _is_terminal_or_honor(t)


def _has_honitsu(hand: HandInput) -> bool:
    suits = {t[1] for t in (_normalize_tile(x) for x in _all_tiles(hand)) if len(t) == 2}
    has_honor = any(len(_normalize_tile(x)) == 1 for x in _all_tiles(hand))
    return len(suits) == 1 and has_honor


def _has_chinitsu(hand: HandInput) -> bool:
    suits = {t[1] for t in (_normalize_tile(x) for x in _all_tiles(hand)) if len(t) == 2}
    has_honor = any(len(_normalize_tile(x)) == 1 for x in _all_tiles(hand))
    return len(suits) == 1 and not has_honor


def _has_shousangen(hand: HandInput) -> bool:
    counts = Counter(_all_tiles(hand))
    dragon_triplets = sum(1 for t in ("P", "F", "C") if counts[t] >= 3)
    dragon_pairs = sum(1 for t in ("P", "F", "C") if counts[t] == 2)
    return dragon_triplets == 2 and dragon_pairs == 1


def _has_sankantsu(hand: HandInput) -> bool:
    return sum(1 for m in hand.melds if m.type in {"kan", "ankan", "kakan"}) == 3


def _is_value_pair(tile: str, context: ContextInput) -> bool:
    t = _normalize_tile(tile)
    return t in {context.round_wind.value, context.seat_wind.value, "P", "F", "C"}


def _is_ryanmen_wait(start_tile: str, win_tile: str) -> bool:
    s = _normalize_tile(start_tile)
    w = _normalize_tile(win_tile)
    if len(s) != 2 or len(w) != 2:
        return False
    if s[1] != w[1]:
        return False
    start = int(s[0])
    win = int(w[0])
    if win not in {start, start + 1, start + 2}:
        return False
    if win == start + 1:
        return False  # kanchan
    if win == start and start == 7:
        return False  # penchan 7 wait (8-9)
    if win == start + 2 and start == 1:
        return False  # penchan 3 wait (1-2)
    return True


def _check_pattern_yaku(
    melds: list[tuple[str, str]],
    pair: str,
    hand: HandInput,
    context: ContextInput,
    rules: RuleSet,
    is_open: bool,
    n_open: int,
    has_honor: bool,
) -> tuple[list[YakuItem], int, bool]:
    """Check pattern-dependent yaku for a specific (melds, pair) decomposition."""
    yaku: list[YakuItem] = []
    han = 0
    has_pinfu = False
    win = _normalize_tile(hand.win_tile)
    closed_melds = melds[n_open:]

    # 平和
    if (
        not is_open
        and len(win) == 2
        and all(k == "chi" for k, _ in melds)
        and not _is_value_pair(pair, context)
        and any(_is_ryanmen_wait(t, hand.win_tile) for k, t in melds if k == "chi")
    ):
        yaku.append(YakuItem(name="平和", han=1))
        han += 1
        has_pinfu = True

    # 一盃口 / 二盃口
    if not is_open:
        seq_counts: dict[tuple[str, int], int] = {}
        for k, t in melds:
            nt = _normalize_tile(t)
            if k == "chi" and len(nt) == 2 and nt[1] in {"m", "p", "s"}:
                key = (nt[1], int(nt[0]))
                seq_counts[key] = seq_counts.get(key, 0) + 1
        pairs_count = sum(v // 2 for v in seq_counts.values())
        if pairs_count >= 2:
            yaku.append(YakuItem(name="二盃口", han=3))
            han += 3
        elif pairs_count == 1:
            yaku.append(YakuItem(name="一盃口", han=1))
            han += 1

    # 三色同順 / 一気通貫 (共通の chi_starts を使う)
    chi_starts: dict[str, set[int]] = {"m": set(), "p": set(), "s": set()}
    for k, t in melds:
        nt = _normalize_tile(t)
        if k == "chi" and len(nt) == 2 and nt[1] in {"m", "p", "s"}:
            chi_starts[nt[1]].add(int(nt[0]))

    if chi_starts["m"] & chi_starts["p"] & chi_starts["s"]:
        s_han = 1 if is_open else 2
        yaku.append(YakuItem(name="三色同順", han=s_han))
        han += s_han

    for suit in ("m", "p", "s"):
        if {1, 4, 7} <= chi_starts[suit]:
            i_han = 1 if is_open else 2
            yaku.append(YakuItem(name="一気通貫", han=i_han))
            han += i_han
            break

    # 純全帯么九 / 混全帯么九
    if _is_terminal_or_honor(pair) and all(_meld_has_terminal_or_honor(k, t) for k, t in melds):
        pair_is_number = len(_normalize_tile(pair)) == 2
        if not has_honor and pair_is_number:
            j_han = 2 if is_open else 3
            yaku.append(YakuItem(name="純全帯么九", han=j_han))
            han += j_han
        elif has_honor:
            c_han = 1 if is_open else 2
            yaku.append(YakuItem(name="混全帯么九", han=c_han))
            han += c_han

    # 対々和
    if all(k == "pon" for k, _ in melds):
        yaku.append(YakuItem(name="対々和", han=2))
        han += 2

    # 三色同刻
    pon_ranks: dict[str, set[int]] = {"m": set(), "p": set(), "s": set()}
    for k, t in melds:
        nt = _normalize_tile(t)
        if k == "pon" and len(nt) == 2 and nt[0].isdigit() and nt[1] in {"m", "p", "s"}:
            pon_ranks[nt[1]].add(int(nt[0]))
    if pon_ranks["m"] & pon_ranks["p"] & pon_ranks["s"]:
        yaku.append(YakuItem(name="三色同刻", han=2))
        han += 2

    # 三暗刻
    closed_pon_count = sum(1 for k, _ in closed_melds if k == "pon")
    ankan_count = sum(1 for m in hand.melds if not m.open)
    concealed_pon_total = closed_pon_count + ankan_count
    if context.win_type == "ron" and _normalize_tile(pair) != win:
        for k, t in closed_melds:
            if k == "pon" and _normalize_tile(t) == win:
                concealed_pon_total -= 1
                break
    if concealed_pon_total >= 3:
        yaku.append(YakuItem(name="三暗刻", han=2))
        han += 2

    return yaku, han, has_pinfu
