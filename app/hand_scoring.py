from __future__ import annotations

from collections import Counter

from app.schemas import (
    ContextInput,
    DoraBreakdown,
    HandInput,
    Payments,
    Points,
    RuleSet,
    ScoreResult,
    YakuItem,
)


def _normalize_tile(tile: str) -> str:
    if tile in {"5mr", "5pr", "5sr"}:
        return tile[:2]
    return tile


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


def _calc_points(context: ContextInput, han: int, fu: int) -> tuple[Points, Payments]:
    base = _base_points(han, fu)
    if context.win_type == "ron":
        ron = base * (6 if context.is_dealer else 4)
        rounded = ((ron + 99) // 100) * 100
        honba_bonus = context.honba * 300
        kyotaku_bonus = context.kyotaku * 1000
        total = rounded + honba_bonus + kyotaku_bonus
        return (
            Points(ron=rounded),
            Payments(honba_bonus=honba_bonus, kyotaku_bonus=kyotaku_bonus, total_received=total),
        )

    if context.is_dealer:
        each = ((base * 2 + 99) // 100) * 100
        total = each * 3 + context.honba * 300 + context.kyotaku * 1000
        return (
            Points(tsumo_dealer_pay=each, tsumo_non_dealer_pay=each),
            Payments(
                honba_bonus=context.honba * 300,
                kyotaku_bonus=context.kyotaku * 1000,
                total_received=total,
            ),
        )

    pay_dealer = ((base * 2 + 99) // 100) * 100
    pay_non_dealer = ((base + 99) // 100) * 100
    total = pay_dealer + pay_non_dealer * 2 + context.honba * 300 + context.kyotaku * 1000
    return (
        Points(tsumo_dealer_pay=pay_dealer, tsumo_non_dealer_pay=pay_non_dealer),
        Payments(
            honba_bonus=context.honba * 300,
            kyotaku_bonus=context.kyotaku * 1000,
            total_received=total,
        ),
    )


def score_hand_shape(hand: HandInput, context: ContextInput, rules: RuleSet) -> ScoreResult:
    """Hand shape -> score. This module must not parse image bytes."""
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
    if context.tenhou:
        yaku.append(YakuItem(name="天和", han=13))
        yaku_han += 13
    if context.chiihou:
        yaku.append(YakuItem(name="地和", han=13))
        yaku_han += 13

    yaku_han += _append_yakuhai_yaku(yaku, hand, context)
    if _has_ittsuu(hand):
        is_open_hand = any(meld.open for meld in hand.melds)
        ittsuu_han = 1 if is_open_hand else 2
        yaku.append(YakuItem(name="一気通貫", han=ittsuu_han))
        yaku_han += ittsuu_han

    if yaku_han == 0:
        raise ValueError("No yaku: dora-only hands cannot win")

    dora = DoraBreakdown(
        dora=len(context.dora_indicators),
        aka_dora=context.aka_dora_count,
        ura_dora=len(context.ura_dora_indicators),
    )
    if dora.dora > 0:
        yaku.append(YakuItem(name="ドラ", han=dora.dora))
    if dora.aka_dora > 0:
        yaku.append(YakuItem(name="赤ドラ", han=dora.aka_dora))
    if dora.ura_dora > 0:
        yaku.append(YakuItem(name="裏ドラ", han=dora.ura_dora))
    han = yaku_han + context.aka_dora_count + dora.dora + dora.ura_dora
    fu = 30
    label = _point_label_from_han_fu(han, fu)
    points, payments = _calc_points(context, han, fu)
    return ScoreResult(
        han=han,
        fu=fu,
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
