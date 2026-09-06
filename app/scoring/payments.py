from __future__ import annotations

from app.schemas import ContextInput, Payments, Points


def yakuman_label(multiplier: int) -> str:
    if multiplier <= 1:
        return "役満"
    if multiplier == 2:
        return "ダブル役満"
    return f"{multiplier}倍役満"


def point_label(han: int, fu: int) -> str:
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


def base_points(han: int, fu: int) -> int:
    label = point_label(han, fu)
    limits = {"満貫": 2000, "跳満": 3000, "倍満": 4000, "三倍満": 6000, "数え役満": 8000}
    return limits.get(label, fu * (2 ** (han + 2)))


def calculate_payments(
    context: ContextInput, han: int, fu: int, base_override: int | None = None
) -> tuple[Points, Payments]:
    base = base_override if base_override is not None else base_points(han, fu)
    is_dealer = context.seat_wind.value == "E"
    honba_bonus = context.honba * 300
    kyotaku_bonus = context.kyotaku * 1000

    if context.win_type == "ron":
        received = _round_hundred(base * (6 if is_dealer else 4))
        points = Points(ron=received)
    elif is_dealer:
        each = _round_hundred(base * 2)
        received = each * 3
        points = Points(tsumo_dealer_pay=each, tsumo_non_dealer_pay=each)
    else:
        dealer = _round_hundred(base * 2)
        non_dealer = _round_hundred(base)
        received = dealer + non_dealer * 2
        points = Points(tsumo_dealer_pay=dealer, tsumo_non_dealer_pay=non_dealer)

    with_honba = received + honba_bonus
    return points, Payments(
        hand_points_received=received,
        hand_points_with_honba=with_honba,
        honba_bonus=honba_bonus,
        kyotaku_bonus=kyotaku_bonus,
        total_received=with_honba + kyotaku_bonus,
    )


def _round_hundred(value: int) -> int:
    return ((value + 99) // 100) * 100
