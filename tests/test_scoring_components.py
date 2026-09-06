from app.scoring.fu import calculate_fu
from app.scoring.dora import evaluate_dora
from app.scoring.payments import base_points, calculate_payments, point_label, yakuman_label
from app.scoring.yaku import evaluate_context_yaku
from app.schemas import ContextInput, HandInput, RuleSet


def context(**updates) -> ContextInput:
    data = {
        "win_type": "ron", "is_dealer": False, "round_wind": "E", "seat_wind": "S",
        "riichi": False, "ippatsu": False, "haitei": False, "houtei": False,
        "rinshan": False, "chankan": False,
    }
    data.update(updates)
    return ContextInput.model_validate(data)


def test_limit_labels_and_base_points():
    assert point_label(4, 40) == "満貫"
    assert point_label(6, 30) == "跳満"
    assert point_label(13, 30) == "数え役満"
    assert base_points(4, 40) == 2000
    assert yakuman_label(2) == "ダブル役満"


def test_ron_payment_includes_honba_and_kyotaku():
    points, payments = calculate_payments(context(honba=2, kyotaku=1), han=4, fu=40)
    assert points.ron == 8000
    assert payments.hand_points_with_honba == 8600
    assert payments.total_received == 9600


def test_context_yaku_are_independent_from_decomposition():
    hand = HandInput(closed_tiles=["1m"] * 14, melds=[], win_tile="1m")
    result = evaluate_context_yaku(hand, context(riichi=True, ippatsu=True))
    assert [(item.name, item.han) for item in result.items] == [("立直", 1), ("一発", 1)]
    assert result.han == 2


def test_fu_component_calculates_pinfu_tsumo():
    hand = HandInput(
        closed_tiles=["1m", "2m", "3m", "4m", "5m", "6m", "3p", "4p", "5p", "6s", "7s", "8s", "5p", "5p"],
        melds=[], win_tile="5p",
    )
    fu, breakdown = calculate_fu(
        [("chi", "1m"), ("chi", "4m"), ("chi", "3p"), ("chi", "6s")],
        "5p", hand, context(win_type="tsumo"), RuleSet(), True, 0,
    )
    assert fu == 20
    assert [item.model_dump() for item in breakdown] == [{"name": "副底", "fu": 20}]


def test_dora_component_handles_normal_red_and_ura_dora():
    hand = HandInput(closed_tiles=["5mr", "5m", "2p"], melds=[], win_tile="2p")
    breakdown, items = evaluate_dora(
        hand, context(dora_indicators=["4m"], ura_dora_indicators=["1p"], aka_dora_count=1)
    )
    assert breakdown.model_dump() == {"dora": 2, "aka_dora": 1, "ura_dora": 1}
    assert [item.name for item in items] == ["ドラ", "赤ドラ", "裏ドラ"]
