from __future__ import annotations

from collections import Counter

from app.domain.decomposition import standard_decompositions
from app.domain.tiles import index_to_tile, normalize_tile, tile_to_index, tiles_to_counts
from app.schemas import ContextInput, HandInput, RuleSet, YakuItem

TERMINAL_HONOR_TILES = {"1m", "9m", "1p", "9p", "1s", "9s", "E", "S", "W", "N", "P", "F", "C"}
GREEN_TILES = {"2s", "3s", "4s", "6s", "8s", "F"}

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


def _has_ittsuu(hand: HandInput) -> bool:
    counts = Counter(_all_tiles(hand))
    for suit in ("m", "p", "s"):
        if all(counts.get(f"{n}{suit}", 0) >= 1 for n in range(1, 10)):
            return True
    return False


def _tile_to_index(tile: str) -> int:
    return tile_to_index(tile)


def _index_to_tile(index: int) -> str:
    return index_to_tile(index)


def _closed_tile_counts(hand: HandInput) -> list[int]:
    return list(tiles_to_counts(hand.closed_tiles))


def _collect_closed_meld_patterns(counts: list[int], needed_melds: int) -> list[list[tuple[str, str]]]:
    patterns: list[list[tuple[str, str]]] = []

    def dfs(work: list[int], remain: int, current: list[tuple[str, str]]) -> None:
        if remain == 0:
            if all(c == 0 for c in work):
                patterns.append(current.copy())
            return

        first = next((i for i, c in enumerate(work) if c > 0), -1)
        if first == -1:
            return

        if work[first] >= 3:
            work[first] -= 3
            current.append(("pon", _index_to_tile(first)))
            dfs(work, remain - 1, current)
            current.pop()
            work[first] += 3

        if first < 27 and first % 9 <= 6 and work[first + 1] > 0 and work[first + 2] > 0:
            work[first] -= 1
            work[first + 1] -= 1
            work[first + 2] -= 1
            current.append(("chi", _index_to_tile(first)))
            dfs(work, remain - 1, current)
            current.pop()
            work[first] += 1
            work[first + 1] += 1
            work[first + 2] += 1

    dfs(counts[:], needed_melds, [])
    return patterns


def _open_meld_patterns(hand: HandInput) -> list[tuple[str, str]]:
    open_melds: list[tuple[str, str]] = []
    for meld in hand.melds:
        tiles = [_normalize_tile(t) for t in meld.tiles]
        if meld.type == "chi":
            open_melds.append(("chi", min(tiles, key=_tile_to_index)))
        else:
            open_melds.append(("pon", tiles[0]))
    return open_melds


def _all_meld_patterns(hand: HandInput) -> list[list[tuple[str, str]]]:
    return [melds for melds, _ in _all_meld_patterns_with_pair(hand)]


def _all_meld_patterns_with_pair(hand: HandInput) -> list[tuple[list[tuple[str, str]], str]]:
    open_melds = _open_meld_patterns(hand)
    decompositions = standard_decompositions(tiles_to_counts(hand.closed_tiles), len(open_melds))
    return [
        (open_melds + [(meld.kind, meld.tile) for meld in decomposition.melds], decomposition.pair)
        for decomposition in decompositions
    ]


def _has_toitoi(hand: HandInput) -> bool:
    for pattern in _all_meld_patterns(hand):
        if all(kind == "pon" for kind, _ in pattern):
            return True
    return False


def _has_sanshoku_doukou(hand: HandInput) -> bool:
    for pattern in _all_meld_patterns(hand):
        ranks_by_suit = {"m": set(), "p": set(), "s": set()}
        for kind, tile in pattern:
            if kind != "pon":
                continue
            t = _normalize_tile(tile)
            if len(t) == 2 and t[0].isdigit() and t[1] in {"m", "p", "s"}:
                ranks_by_suit[t[1]].add(int(t[0]))
        if ranks_by_suit["m"] & ranks_by_suit["p"] & ranks_by_suit["s"]:
            return True
    return False


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


def _has_chanta(hand: HandInput) -> bool:
    for melds, pair in _all_meld_patterns_with_pair(hand):
        if not _is_terminal_or_honor(pair):
            continue
        if not all(_meld_has_terminal_or_honor(kind, tile) for kind, tile in melds):
            continue
        tiles = _all_tiles(hand)
        if any(len(_normalize_tile(t)) == 1 for t in tiles):
            return True
    return False


def _has_junchan(hand: HandInput) -> bool:
    for melds, pair in _all_meld_patterns_with_pair(hand):
        if not _is_terminal_or_honor(pair):
            continue
        if len(_normalize_tile(pair)) != 2:
            continue
        if not all(_meld_has_terminal_or_honor(kind, tile) for kind, tile in melds):
            continue
        if any(len(_normalize_tile(t)) == 1 for t in _all_tiles(hand)):
            continue
        return True
    return False


def _has_sanshoku_doujun(hand: HandInput) -> bool:
    for melds, _ in _all_meld_patterns_with_pair(hand):
        starts = {"m": set(), "p": set(), "s": set()}
        for kind, tile in melds:
            t = _normalize_tile(tile)
            if kind == "chi" and len(t) == 2 and t[1] in {"m", "p", "s"}:
                starts[t[1]].add(int(t[0]))
        if starts["m"] & starts["p"] & starts["s"]:
            return True
    return False


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


def _has_sanankou(hand: HandInput, context: ContextInput) -> bool:
    open_pon_like_count = sum(
        1 for meld in hand.melds if meld.open and meld.type in {"pon", "kan", "ankan", "kakan"}
    )
    win = _normalize_tile(hand.win_tile)
    for melds, pair in _all_meld_patterns_with_pair(hand):
        concealed_pon_count = sum(1 for kind, _ in melds if kind == "pon") - open_pon_like_count
        if context.win_type == "ron" and _normalize_tile(pair) != win:
            ron_completes_pon = any(
                kind == "pon" and _normalize_tile(tile) == win
                for kind, tile in melds
                if (kind, tile) not in [(k, t) for k, t in _open_meld_patterns(hand)]
            )
            if ron_completes_pon:
                concealed_pon_count -= 1
        if concealed_pon_count >= 3:
            return True
    return False


def _count_peikou(hand: HandInput) -> int:
    if hand.melds:
        return 0
    best = 0
    for melds, _ in _all_meld_patterns_with_pair(hand):
        seq_counts: dict[tuple[str, int], int] = {}
        for kind, tile in melds:
            t = _normalize_tile(tile)
            if kind == "chi" and len(t) == 2 and t[1] in {"m", "p", "s"}:
                key = (t[1], int(t[0]))
                seq_counts[key] = seq_counts.get(key, 0) + 1
        pairs = sum(v // 2 for v in seq_counts.values())
        best = max(best, pairs)
    return best


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


def _has_pinfu(hand: HandInput, context: ContextInput) -> bool:
    if hand.melds:
        return False
    if len(_normalize_tile(hand.win_tile)) != 2:
        return False

    for melds, pair in _all_meld_patterns_with_pair(hand):
        if any(kind != "chi" for kind, _ in melds):
            continue
        if _is_value_pair(pair, context):
            continue
        if any(_is_ryanmen_wait(tile, hand.win_tile) for kind, tile in melds if kind == "chi"):
            return True
    return False






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
