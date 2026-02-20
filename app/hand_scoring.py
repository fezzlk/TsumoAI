from __future__ import annotations

from collections import Counter

from app.schemas import (
    ContextInput,
    DoraBreakdown,
    HandInput,
    Payments,
    Points,
    FuBreakdownItem,
    RuleSet,
    ScoreResult,
    YakuItem,
)

TERMINAL_HONOR_TILES = {"1m", "9m", "1p", "9p", "1s", "9s", "E", "S", "W", "N", "P", "F", "C"}
GREEN_TILES = {"2s", "3s", "4s", "6s", "8s", "F"}


def _normalize_tile(tile: str) -> str:
    if tile in {"5mr", "5pr", "5sr"}:
        return tile[:2]
    return tile


def _all_tiles(hand: HandInput) -> list[str]:
    tiles = [_normalize_tile(t) for t in hand.closed_tiles]
    for meld in hand.melds:
        tiles.extend(_normalize_tile(t) for t in meld.tiles)
    return tiles


def _next_dora_tile(indicator: str) -> str:
    t = _normalize_tile(indicator)
    if len(t) == 2 and t[1] in {"m", "p", "s"}:
        n = int(t[0])
        return f"{1 if n == 9 else n + 1}{t[1]}"
    if t in {"E", "S", "W", "N"}:
        order = ["E", "S", "W", "N"]
        return order[(order.index(t) + 1) % len(order)]
    if t in {"P", "F", "C"}:
        order = ["P", "F", "C"]
        return order[(order.index(t) + 1) % len(order)]
    return t


def _count_dora(hand: HandInput, indicators: list[str]) -> int:
    counts = Counter(_all_tiles(hand))
    return sum(counts.get(_next_dora_tile(ind), 0) for ind in indicators)


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
    t = _normalize_tile(tile)
    if len(t) == 2 and t[0].isdigit():
        num = int(t[0])
        suit = t[1]
        base = {"m": 0, "p": 9, "s": 18}[suit]
        return base + (num - 1)
    honor_map = {"E": 27, "S": 28, "W": 29, "N": 30, "P": 31, "F": 32, "C": 33}
    return honor_map[t]


def _index_to_tile(index: int) -> str:
    if index < 27:
        suit = ("m", "p", "s")[index // 9]
        num = (index % 9) + 1
        return f"{num}{suit}"
    honor = {27: "E", 28: "S", 29: "W", 30: "N", 31: "P", 32: "F", 33: "C"}
    return honor[index]


def _closed_tile_counts(hand: HandInput) -> list[int]:
    counts = [0] * 34
    for tile in hand.closed_tiles:
        counts[_tile_to_index(tile)] += 1
    return counts


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

    needed_closed_melds = 4 - len(open_melds)
    if needed_closed_melds < 0:
        return []

    counts = _closed_tile_counts(hand)
    patterns: list[tuple[list[tuple[str, str]], str]] = []
    for i, c in enumerate(counts):
        if c < 2:
            continue
        work = counts[:]
        work[i] -= 2
        pair_tile = _index_to_tile(i)
        closed_patterns = _collect_closed_meld_patterns(work, needed_closed_melds)
        for closed in closed_patterns:
            patterns.append((open_melds + closed, pair_tile))
    return patterns


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


def _is_kokushi(hand: HandInput) -> bool:
    if hand.melds:
        return False
    counts = Counter(_all_tiles(hand))
    if set(counts.keys()) - TERMINAL_HONOR_TILES:
        return False
    if not TERMINAL_HONOR_TILES.issubset(counts.keys()):
        return False
    return any(counts[t] >= 2 for t in TERMINAL_HONOR_TILES)


def _is_kokushi_13_wait(hand: HandInput, win_tile: str) -> bool:
    if not _is_kokushi(hand):
        return False
    w = _normalize_tile(win_tile)
    counts = Counter(_all_tiles(hand))
    if w not in TERMINAL_HONOR_TILES:
        return False
    if counts[w] != 2:
        return False
    return all(counts[t] == (2 if t == w else 1) for t in TERMINAL_HONOR_TILES)


def _has_daisangen(hand: HandInput) -> bool:
    counts = Counter(_all_tiles(hand))
    return all(counts[t] >= 3 for t in ("P", "F", "C"))


def _has_shousuushii(hand: HandInput) -> bool:
    counts = Counter(_all_tiles(hand))
    wind_triplets = sum(1 for w in ("E", "S", "W", "N") if counts[w] >= 3)
    wind_pairs = sum(1 for w in ("E", "S", "W", "N") if counts[w] == 2)
    return wind_triplets == 3 and wind_pairs == 1


def _has_daisuushii(hand: HandInput) -> bool:
    counts = Counter(_all_tiles(hand))
    return all(counts[w] >= 3 for w in ("E", "S", "W", "N"))


def _has_tsuuiisou(hand: HandInput) -> bool:
    return all(len(_normalize_tile(t)) == 1 for t in _all_tiles(hand))


def _has_ryuuiisou(hand: HandInput) -> bool:
    return all(_normalize_tile(t) in GREEN_TILES for t in _all_tiles(hand))


def _has_chinroutou(hand: HandInput) -> bool:
    for tile in _all_tiles(hand):
        t = _normalize_tile(tile)
        if len(t) != 2:
            return False
        if t[0] not in {"1", "9"} or t[1] not in {"m", "p", "s"}:
            return False
    return True


def _has_suukantsu(hand: HandInput) -> bool:
    return sum(1 for m in hand.melds if m.type in {"kan", "ankan", "kakan"}) == 4


def _has_suuankou(hand: HandInput) -> bool:
    if any(m.open for m in hand.melds):
        return False
    for pattern in _all_meld_patterns(hand):
        if all(kind == "pon" for kind, _ in pattern):
            return True
    return False


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


def _has_sanankou(hand: HandInput) -> bool:
    open_pon_like_count = sum(
        1 for meld in hand.melds if meld.open and meld.type in {"pon", "kan", "ankan", "kakan"}
    )
    for melds in _all_meld_patterns(hand):
        concealed_pon_count = sum(1 for kind, _ in melds if kind == "pon") - open_pon_like_count
        if concealed_pon_count >= 3:
            return True
    return False


def _has_iipeikou(hand: HandInput) -> bool:
    if hand.melds:
        return False
    for melds, _ in _all_meld_patterns_with_pair(hand):
        seq_counts: dict[tuple[str, int], int] = {}
        for kind, tile in melds:
            t = _normalize_tile(tile)
            if kind == "chi" and len(t) == 2 and t[1] in {"m", "p", "s"}:
                key = (t[1], int(t[0]))
                seq_counts[key] = seq_counts.get(key, 0) + 1
        if any(v >= 2 for v in seq_counts.values()):
            return True
    return False


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


def _chuuren_info(hand: HandInput) -> tuple[bool, bool]:
    if hand.melds:
        return False, False
    tiles = [_normalize_tile(t) for t in hand.closed_tiles]
    if any(len(t) != 2 for t in tiles):
        return False, False
    suits = {t[1] for t in tiles}
    if len(suits) != 1:
        return False, False
    suit = next(iter(suits))
    if suit not in {"m", "p", "s"}:
        return False, False

    counts = Counter(int(t[0]) for t in tiles)
    if sum(counts.values()) != 14:
        return False, False
    base = {1: 3, 9: 3, 2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1}
    if any(counts[n] < base[n] for n in range(1, 10)):
        return False, False
    extras = [n for n in range(1, 10) for _ in range(counts[n] - base[n])]
    if len(extras) != 1:
        return False, False

    win = _normalize_tile(hand.win_tile)
    is_pure = win == f"{extras[0]}{suit}"
    return True, is_pure


def _yakuman_hits(hand: HandInput, context: ContextInput, rules: RuleSet) -> tuple[list[str], int]:
    hits: list[str] = []
    multiplier = 0

    if context.tenhou:
        hits.append("天和")
        multiplier += 1
    if context.chiihou:
        hits.append("地和")
        multiplier += 1

    if _is_kokushi(hand):
        if _is_kokushi_13_wait(hand, hand.win_tile):
            hits.append("国士無双十三面待ち")
            multiplier += 2 if rules.double_yakuman_ari else 1
        else:
            hits.append("国士無双")
            multiplier += 1

    chuuren, pure_chuuren = _chuuren_info(hand)
    if chuuren:
        if pure_chuuren:
            hits.append("純正九蓮宝燈")
            multiplier += 2 if rules.double_yakuman_ari else 1
        else:
            hits.append("九蓮宝燈")
            multiplier += 1

    if _has_daisuushii(hand):
        hits.append("大四喜")
        multiplier += 2 if rules.double_yakuman_ari else 1
    elif _has_shousuushii(hand):
        hits.append("小四喜")
        multiplier += 1

    if _has_daisangen(hand):
        hits.append("大三元")
        multiplier += 1
    if _has_suuankou(hand):
        hits.append("四暗刻")
        multiplier += 1
    if _has_suukantsu(hand):
        hits.append("四槓子")
        multiplier += 1
    if _has_tsuuiisou(hand):
        hits.append("字一色")
        multiplier += 1
    if _has_ryuuiisou(hand):
        hits.append("緑一色")
        multiplier += 1
    if _has_chinroutou(hand):
        hits.append("清老頭")
        multiplier += 1

    return hits, multiplier


def _yakuman_label(multiplier: int) -> str:
    if multiplier <= 1:
        return "役満"
    if multiplier == 2:
        return "ダブル役満"
    return f"{multiplier}倍役満"


def _point_label_from_han_fu(han: int, fu: int) -> str:
    if han >= 13:
        return "数え役満"
    if han >= 11:
        return "三倍満"
    if han >= 8:
        return "倍満"
    if han >= 6:
        return "跳満"
    if han == 5 or (han == 4 and fu >= 40) or (han == 3 and fu >= 70):
        return "満貫"
    return "通常"


def _base_points(han: int, fu: int) -> int:
    label = _point_label_from_han_fu(han, fu)
    if label == "満貫":
        return 2000
    if label == "跳満":
        return 3000
    if label == "倍満":
        return 4000
    if label == "三倍満":
        return 6000
    if label == "数え役満":
        return 8000
    return fu * (2 ** (han + 2))


def _calc_points(context: ContextInput, han: int, fu: int, base_override: int | None = None) -> tuple[Points, Payments]:
    base = base_override if base_override is not None else _base_points(han, fu)
    if context.win_type == "ron":
        ron = base * (6 if context.is_dealer else 4)
        rounded = ((ron + 99) // 100) * 100
        honba_bonus = context.honba * 300
        kyotaku_bonus = context.kyotaku * 1000
        hand_points_with_honba = rounded + honba_bonus
        total = hand_points_with_honba + kyotaku_bonus
        return (
            Points(ron=rounded),
            Payments(
                hand_points_received=rounded,
                hand_points_with_honba=hand_points_with_honba,
                honba_bonus=honba_bonus,
                kyotaku_bonus=kyotaku_bonus,
                total_received=total,
            ),
        )

    if context.is_dealer:
        each = ((base * 2 + 99) // 100) * 100
        hand_points_received = each * 3
        honba_bonus = context.honba * 300
        kyotaku_bonus = context.kyotaku * 1000
        hand_points_with_honba = hand_points_received + honba_bonus
        total = hand_points_with_honba + kyotaku_bonus
        return (
            Points(tsumo_dealer_pay=each, tsumo_non_dealer_pay=each),
            Payments(
                hand_points_received=hand_points_received,
                hand_points_with_honba=hand_points_with_honba,
                honba_bonus=honba_bonus,
                kyotaku_bonus=kyotaku_bonus,
                total_received=total,
            ),
        )

    pay_dealer = ((base * 2 + 99) // 100) * 100
    pay_non_dealer = ((base + 99) // 100) * 100
    hand_points_received = pay_dealer + pay_non_dealer * 2
    honba_bonus = context.honba * 300
    kyotaku_bonus = context.kyotaku * 1000
    hand_points_with_honba = hand_points_received + honba_bonus
    total = hand_points_with_honba + kyotaku_bonus
    return (
        Points(tsumo_dealer_pay=pay_dealer, tsumo_non_dealer_pay=pay_non_dealer),
        Payments(
            hand_points_received=hand_points_received,
            hand_points_with_honba=hand_points_with_honba,
            honba_bonus=honba_bonus,
            kyotaku_bonus=kyotaku_bonus,
            total_received=total,
        ),
    )


def _is_closed_hand(hand: HandInput) -> bool:
    return not any(m.open for m in hand.melds)


def _meld_tiles(kind: str, tile: str) -> list[str]:
    t = _normalize_tile(tile)
    if kind == "chi" and len(t) == 2 and t[1] in {"m", "p", "s"}:
        start = int(t[0])
        return [f"{start + i}{t[1]}" for i in range(3)]
    if kind == "pon":
        return [t, t, t]
    return [t, t, t, t]


def _pair_fu(pair_tile: str, context: ContextInput, rules: RuleSet) -> int:
    t = _normalize_tile(pair_tile)
    if t in {"P", "F", "C"}:
        return 2
    if t == context.round_wind.value and t == context.seat_wind.value:
        return rules.renpu_fu
    if t in {context.round_wind.value, context.seat_wind.value}:
        return 2
    return 0


def _meld_fu(kind: str, tile: str, is_open: bool) -> int:
    if kind == "chi":
        return 0
    t = _normalize_tile(tile)
    is_yaochu = _is_terminal_or_honor(t)
    if kind == "pon":
        return 4 if is_yaochu and is_open else 8 if is_yaochu else 2 if is_open else 4
    return 16 if is_yaochu and is_open else 32 if is_yaochu else 8 if is_open else 16


def _calc_regular_fu(hand: HandInput, context: ContextInput, rules: RuleSet, has_pinfu: bool) -> tuple[int, list[FuBreakdownItem]]:
    if has_pinfu and context.win_type == "tsumo":
        return 20, [FuBreakdownItem(name="副底", fu=20)]
    if _has_chiitoitsu(hand):
        return 25, [FuBreakdownItem(name="七対子", fu=25)]

    breakdown_base: list[FuBreakdownItem] = [FuBreakdownItem(name="副底", fu=20)]
    if context.win_type == "tsumo":
        breakdown_base.append(FuBreakdownItem(name="ツモ", fu=2))
    if context.win_type == "ron" and _is_closed_hand(hand):
        breakdown_base.append(FuBreakdownItem(name="門前ロン", fu=10))

    best_total = 20
    best_breakdown = breakdown_base

    for melds, pair in _all_meld_patterns_with_pair(hand):
        meld_entries: list[dict] = []
        for kind, tile in melds:
            meld_entries.append({"kind": kind, "tile": tile, "open": False})
        for meld in hand.melds:
            tiles = [_normalize_tile(t) for t in meld.tiles]
            kind = "chi" if meld.type == "chi" else "pon" if meld.type == "pon" else "kan"
            base_tile = min(tiles, key=_tile_to_index) if kind == "chi" else tiles[0]
            meld_entries.append({"kind": kind, "tile": base_tile, "open": meld.open})

        win = _normalize_tile(hand.win_tile)
        win_targets: list[tuple[str, int]] = []
        if _normalize_tile(pair) == win:
            win_targets.append(("pair", -1))
        for idx, m in enumerate(meld_entries):
            if win in _meld_tiles(m["kind"], m["tile"]):
                win_targets.append(("meld", idx))
        if not win_targets:
            win_targets = [("meld", -1)]

        for target_type, target_idx in win_targets:
            details = breakdown_base.copy()
            total = sum(item.fu for item in details)

            pfu = _pair_fu(pair, context, rules)
            if pfu:
                details.append(FuBreakdownItem(name="雀頭", fu=pfu))
                total += pfu

            wait_fu = 0
            if target_type == "pair":
                wait_fu = 2
            elif target_idx >= 0:
                target_meld = meld_entries[target_idx]
                if target_meld["kind"] == "chi":
                    s = _normalize_tile(target_meld["tile"])
                    start = int(s[0])
                    n = int(win[0])
                    if n == start + 1:
                        wait_fu = 2
                    elif (start == 1 and n == 3) or (start == 7 and n == 7):
                        wait_fu = 2
            if wait_fu:
                details.append(FuBreakdownItem(name="待ち", fu=2))
                total += 2

            for idx, m in enumerate(meld_entries):
                is_open = m["open"]
                if (
                    context.win_type == "ron"
                    and idx == target_idx
                    and m["kind"] == "pon"
                    and not m["open"]
                ):
                    is_open = True
                mfu = _meld_fu(m["kind"], m["tile"], is_open)
                if mfu:
                    details.append(FuBreakdownItem(name="面子", fu=mfu))
                    total += mfu

            rounded = ((total + 9) // 10) * 10
            if rounded > total:
                details.append(FuBreakdownItem(name="切り上げ", fu=rounded - total))

            if rounded >= best_total:
                best_total = rounded
                best_breakdown = details

    return best_total, best_breakdown


def score_hand_shape(hand: HandInput, context: ContextInput, rules: RuleSet) -> ScoreResult:
    """Hand shape -> score. This module must not parse image bytes."""
    yakuman_hits, yakuman_multiplier = _yakuman_hits(hand, context, rules)
    if yakuman_hits:
        han = 13 * yakuman_multiplier
        points, payments = _calc_points(context, han=han, fu=0, base_override=8000 * yakuman_multiplier)
        return ScoreResult(
            han=han,
            fu=0,
            fu_breakdown=[],
            yaku=[],
            yakuman=yakuman_hits,
            dora=DoraBreakdown(dora=0, aka_dora=0, ura_dora=0),
            point_label=_yakuman_label(yakuman_multiplier),
            points=points,
            payments=payments,
            explanation=[
                "PoC scoring mode is active.",
                "Yakuman path was selected.",
                f"yakuman={yakuman_hits}, multiplier={yakuman_multiplier}.",
            ],
        )

    yaku: list[YakuItem] = []
    yaku_han = 0
    if context.double_riichi:
        yaku.append(YakuItem(name="ダブル立直", han=2))
        yaku_han += 2
    elif context.riichi:
        yaku.append(YakuItem(name="立直", han=1))
        yaku_han += 1
    if context.ippatsu:
        yaku.append(YakuItem(name="一発", han=1))
        yaku_han += 1
    if context.haitei:
        yaku.append(YakuItem(name="海底摸月", han=1))
        yaku_han += 1
    if context.houtei:
        yaku.append(YakuItem(name="河底撈魚", han=1))
        yaku_han += 1
    if context.rinshan:
        yaku.append(YakuItem(name="嶺上開花", han=1))
        yaku_han += 1
    if context.chankan:
        yaku.append(YakuItem(name="槍槓", han=1))
        yaku_han += 1
    if context.win_type == "tsumo" and not any(m.open for m in hand.melds):
        yaku.append(YakuItem(name="門前清自摸和", han=1))
        yaku_han += 1
    if context.tenhou:
        yaku.append(YakuItem(name="天和", han=13))
        yaku_han += 13
    if context.chiihou:
        yaku.append(YakuItem(name="地和", han=13))
        yaku_han += 13

    yaku_han += _append_yakuhai_yaku(yaku, hand, context)
    has_pinfu = _has_pinfu(hand, context)

    if _has_tanyao(hand, rules):
        yaku.append(YakuItem(name="断么九", han=1))
        yaku_han += 1
    if has_pinfu:
        yaku.append(YakuItem(name="平和", han=1))
        yaku_han += 1
    if _has_iipeikou(hand):
        yaku.append(YakuItem(name="一盃口", han=1))
        yaku_han += 1
    if _has_sanshoku_doujun(hand):
        sanshoku_han = 1 if any(m.open for m in hand.melds) else 2
        yaku.append(YakuItem(name="三色同順", han=sanshoku_han))
        yaku_han += sanshoku_han
    if _has_ittsuu(hand):
        is_open_hand = any(meld.open for meld in hand.melds)
        ittsuu_han = 1 if is_open_hand else 2
        yaku.append(YakuItem(name="一気通貫", han=ittsuu_han))
        yaku_han += ittsuu_han
    if _has_junchan(hand):
        junchan_han = 2 if any(m.open for m in hand.melds) else 3
        yaku.append(YakuItem(name="純全帯么九", han=junchan_han))
        yaku_han += junchan_han
    elif _has_chanta(hand):
        chanta_han = 1 if any(m.open for m in hand.melds) else 2
        yaku.append(YakuItem(name="混全帯么九", han=chanta_han))
        yaku_han += chanta_han
    if _has_toitoi(hand):
        yaku.append(YakuItem(name="対々和", han=2))
        yaku_han += 2
    if _has_sanshoku_doukou(hand):
        yaku.append(YakuItem(name="三色同刻", han=2))
        yaku_han += 2
    if _has_shousangen(hand):
        yaku.append(YakuItem(name="小三元", han=2))
        yaku_han += 2
    if _has_sanankou(hand):
        yaku.append(YakuItem(name="三暗刻", han=2))
        yaku_han += 2
    if _has_sankantsu(hand):
        yaku.append(YakuItem(name="三槓子", han=2))
        yaku_han += 2
    if _has_chiitoitsu(hand):
        yaku.append(YakuItem(name="七対子", han=2))
        yaku_han += 2
    if _has_honroutou(hand):
        yaku.append(YakuItem(name="混老頭", han=2))
        yaku_han += 2
    if _has_chinitsu(hand):
        chinitsu_han = 5 if any(m.open for m in hand.melds) else 6
        yaku.append(YakuItem(name="清一色", han=chinitsu_han))
        yaku_han += chinitsu_han
    elif _has_honitsu(hand):
        honitsu_han = 2 if any(m.open for m in hand.melds) else 3
        yaku.append(YakuItem(name="混一色", han=honitsu_han))
        yaku_han += honitsu_han

    if yaku_han == 0:
        raise ValueError("No yaku: dora-only hands cannot win")

    dora = DoraBreakdown(
        dora=_count_dora(hand, context.dora_indicators),
        aka_dora=context.aka_dora_count,
        ura_dora=_count_dora(hand, context.ura_dora_indicators),
    )
    if dora.dora > 0:
        yaku.append(YakuItem(name="ドラ", han=dora.dora))
    if dora.aka_dora > 0:
        yaku.append(YakuItem(name="赤ドラ", han=dora.aka_dora))
    if dora.ura_dora > 0:
        yaku.append(YakuItem(name="裏ドラ", han=dora.ura_dora))
    han = yaku_han + context.aka_dora_count + dora.dora + dora.ura_dora
    fu, fu_breakdown = _calc_regular_fu(hand, context, rules, has_pinfu)
    label = _point_label_from_han_fu(han, fu)
    points, payments = _calc_points(context, han, fu)
    return ScoreResult(
        han=han,
        fu=fu,
        fu_breakdown=fu_breakdown,
        yaku=yaku,
        yakuman=[],
        dora=dora,
        point_label=label,
        points=points,
        payments=payments,
        explanation=[
            "PoC scoring mode is active.",
            f"Hand-shape input accepted: closed_tiles={len(hand.closed_tiles)}, melds={len(hand.melds)}.",
            "Current engine calculates points from context flags, yakuhai and dora.",
            f"Rules snapshot: aka_ari={rules.aka_ari}, kuitan_ari={rules.kuitan_ari}, renpu_fu={rules.renpu_fu}.",
        ],
    )
