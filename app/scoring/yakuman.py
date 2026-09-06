from __future__ import annotations

from collections import Counter

from app.domain.tiles import normalize_tile
from app.schemas import ContextInput, HandInput, RuleSet
from app.scoring.hand_yaku import _all_meld_patterns_with_pair, _all_tiles

TERMINAL_HONOR_TILES = {"1m", "9m", "1p", "9p", "1s", "9s", "E", "S", "W", "N", "P", "F", "C"}
GREEN_TILES = {"2s", "3s", "4s", "6s", "8s", "F"}

_normalize_tile = normalize_tile

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

def _has_suuankou(hand: HandInput, context: ContextInput) -> bool:
    if any(m.open for m in hand.melds):
        return False
    win = _normalize_tile(hand.win_tile)
    for pattern, pair in _all_meld_patterns_with_pair(hand):
        if not all(kind == "pon" for kind, _ in pattern):
            continue
        if context.win_type == "ron":
            if _normalize_tile(pair) != win:
                continue
        return True
    return False

def _is_suuankou_tanki(hand: HandInput, context: ContextInput) -> bool:
    if any(m.open for m in hand.melds):
        return False
    win = _normalize_tile(hand.win_tile)
    for pattern, pair in _all_meld_patterns_with_pair(hand):
        if not all(kind == "pon" for kind, _ in pattern):
            continue
        if _normalize_tile(pair) == win:
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
    if _has_suuankou(hand, context):
        if _is_suuankou_tanki(hand, context):
            hits.append("四暗刻単騎")
            multiplier += 2 if rules.double_yakuman_ari else 1
        else:
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
