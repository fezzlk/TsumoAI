from __future__ import annotations

from app.scoring.payments import calculate_payments, point_label, yakuman_label
from app.scoring.fu import calculate_fu
from app.scoring.yaku import evaluate_context_yaku
from app.scoring.dora import evaluate_dora
from app.scoring.hand_yaku import (
    _all_meld_patterns_with_pair,
    _all_tiles,
    _append_yakuhai_yaku,
    _check_pattern_yaku,
    _has_chiitoitsu,
    _has_chinitsu,
    _has_honitsu,
    _has_honroutou,
    _has_sankantsu,
    _has_shousangen,
    _has_tanyao,
    _normalize_tile,
)
from app.scoring.yakuman import _yakuman_hits
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

def _yakuman_label(multiplier: int) -> str:
    return yakuman_label(multiplier)


def _point_label_from_han_fu(han: int, fu: int) -> str:
    return point_label(han, fu)


def _calc_points(context: ContextInput, han: int, fu: int, base_override: int | None = None) -> tuple[Points, Payments]:
    return calculate_payments(context, han, fu, base_override)


def _calc_fu_for_pattern(
    melds: list[tuple[str, str]],
    pair: str,
    hand: HandInput,
    context: ContextInput,
    rules: RuleSet,
    has_pinfu: bool,
    n_open: int,
) -> tuple[int, list[FuBreakdownItem]]:
    return calculate_fu(melds, pair, hand, context, rules, has_pinfu, n_open)




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

    # Pre-compute shared data
    is_open = any(m.open for m in hand.melds)
    has_honor = any(len(_normalize_tile(t)) == 1 for t in _all_tiles(hand))
    n_open = len(hand.melds)

    # Context yaku (same for all interpretations)
    context_result = evaluate_context_yaku(hand, context)
    ctx_yaku = list(context_result.items)
    ctx_han = context_result.han

    # Tile-based yaku (same for all interpretations)
    tile_yaku: list[YakuItem] = []
    tile_han = 0
    tile_han += _append_yakuhai_yaku(tile_yaku, hand, context)
    if _has_tanyao(hand, rules):
        tile_yaku.append(YakuItem(name="断么九", han=1))
        tile_han += 1
    if _has_shousangen(hand):
        tile_yaku.append(YakuItem(name="小三元", han=2))
        tile_han += 2
    if _has_sankantsu(hand):
        tile_yaku.append(YakuItem(name="三槓子", han=2))
        tile_han += 2
    if _has_honroutou(hand):
        tile_yaku.append(YakuItem(name="混老頭", han=2))
        tile_han += 2
    if _has_chinitsu(hand):
        chinitsu_han = 5 if is_open else 6
        tile_yaku.append(YakuItem(name="清一色", han=chinitsu_han))
        tile_han += chinitsu_han
    elif _has_honitsu(hand):
        honitsu_han = 2 if is_open else 3
        tile_yaku.append(YakuItem(name="混一色", han=honitsu_han))
        tile_han += honitsu_han

    # Dora (same for all interpretations)
    dora, dora_items = evaluate_dora(hand, context)
    dora_yaku = list(dora_items)
    dora_han_total = dora.dora + dora.aka_dora + dora.ura_dora

    # Enumerate all interpretations, pick the one with highest points
    best_received = -1
    best_result: tuple | None = None

    # Standard meld interpretations
    patterns = _all_meld_patterns_with_pair(hand)
    for melds, pair in patterns:
        pat_yaku, pat_han, has_pinfu = _check_pattern_yaku(
            melds, pair, hand, context, rules, is_open, n_open, has_honor,
        )
        total_yaku_han = ctx_han + tile_han + pat_han
        if total_yaku_han == 0:
            continue
        total_han = total_yaku_han + dora_han_total
        fu, fu_breakdown = _calc_fu_for_pattern(
            melds, pair, hand, context, rules, has_pinfu, n_open,
        )
        all_yaku = ctx_yaku + tile_yaku + pat_yaku + dora_yaku
        label = _point_label_from_han_fu(total_han, fu)
        points, payments = _calc_points(context, total_han, fu)
        if payments.total_received > best_received:
            best_received = payments.total_received
            best_result = (total_han, fu, fu_breakdown, all_yaku, label, points, payments)

    # Chiitoitsu interpretation
    if _has_chiitoitsu(hand):
        pat_yaku = [YakuItem(name="七対子", han=2)]
        pat_han = 2
        total_yaku_han = ctx_han + tile_han + pat_han
        if total_yaku_han > 0:
            total_han = total_yaku_han + dora_han_total
            fu = 25
            fu_breakdown = [FuBreakdownItem(name="七対子", fu=25)]
            all_yaku = ctx_yaku + tile_yaku + pat_yaku + dora_yaku
            label = _point_label_from_han_fu(total_han, fu)
            points, payments = _calc_points(context, total_han, fu)
            if payments.total_received > best_received:
                best_received = payments.total_received
                best_result = (total_han, fu, fu_breakdown, all_yaku, label, points, payments)

    if best_result is None:
        raise ValueError("No yaku: dora-only hands cannot win")

    total_han, fu, fu_breakdown, all_yaku, label, points, payments = best_result
    return ScoreResult(
        han=total_han,
        fu=fu,
        fu_breakdown=fu_breakdown,
        yaku=all_yaku,
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

