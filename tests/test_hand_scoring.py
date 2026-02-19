from app.hand_scoring import score_hand_shape
from app.schemas import ContextInput, HandInput, RuleSet


def base_hand() -> HandInput:
    return HandInput(
        closed_tiles=["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "2p", "2p"],
        melds=[],
        win_tile="2p",
    )


def base_context(**kwargs) -> ContextInput:
    payload = {
        "win_type": "ron",
        "is_dealer": False,
        "round_wind": "E",
        "seat_wind": "S",
        "riichi": True,
        "double_riichi": False,
        "ippatsu": False,
        "haitei": False,
        "houtei": False,
        "rinshan": False,
        "chankan": False,
        "chiihou": False,
        "tenhou": False,
        "dora_indicators": ["4m"],
        "aka_dora_count": 2,
        "honba": 0,
        "kyotaku": 0,
    }
    payload.update(kwargs)
    return ContextInput.model_validate(payload)


def test_score_hand_shape_ron_non_dealer():
    result = score_hand_shape(base_hand(), base_context(), RuleSet())
    assert result.han == 4
    assert result.fu == 30
    assert result.point_label == "通常"
    assert result.points.ron == 7700
    assert result.payments.total_received == 7700


def test_score_hand_shape_tsumo_dealer():
    context = base_context(win_type="tsumo", is_dealer=True, riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(base_hand(), context, RuleSet())
    assert result.han == 0
    assert result.points.tsumo_dealer_pay == 300
    assert result.points.tsumo_non_dealer_pay == 300
    assert result.payments.total_received == 900


def test_score_hand_shape_limit_label_haneman():
    context = base_context(
        win_type="ron",
        riichi=True,
        ippatsu=True,
        haitei=True,
        houtei=False,
        rinshan=True,
        chankan=True,
        aka_dora_count=1,
        dora_indicators=["1m"],
    )
    result = score_hand_shape(base_hand(), context, RuleSet())
    assert result.han == 7
    assert result.point_label == "跳満"
    assert result.points.ron == 12000


def test_score_hand_shape_double_riichi():
    context = base_context(riichi=False, double_riichi=True, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(base_hand(), context, RuleSet())
    assert result.han == 2
    assert any(y.name == "ダブル立直" for y in result.yaku)
