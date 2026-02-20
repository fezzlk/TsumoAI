import pytest

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
    assert result.han == 5
    assert result.fu == 30
    assert result.point_label == "満貫"
    assert result.points.ron == 8000
    assert result.payments.total_received == 8000
    assert any(y.name == "場風 東" for y in result.yaku)


def test_score_hand_shape_tsumo_dealer():
    context = base_context(
        win_type="tsumo",
        is_dealer=True,
        round_wind="W",
        seat_wind="S",
        riichi=False,
        aka_dora_count=0,
        dora_indicators=[],
    )
    with pytest.raises(ValueError):
        score_hand_shape(base_hand(), context, RuleSet())


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
    assert result.han == 8
    assert result.point_label == "倍満"
    assert result.points.ron == 16000


def test_score_hand_shape_double_riichi():
    context = base_context(riichi=False, double_riichi=True, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(base_hand(), context, RuleSet())
    assert result.han == 3
    assert any(y.name == "ダブル立直" for y in result.yaku)


def test_score_hand_shape_rejects_dora_only():
    context = base_context(
        round_wind="W",
        seat_wind="S",
        riichi=False,
        double_riichi=False,
        aka_dora_count=0,
        dora_indicators=["4m"],
    )
    with pytest.raises(ValueError):
        score_hand_shape(base_hand(), context, RuleSet())


def test_score_hand_shape_adds_seat_wind_yakuhai():
    hand = base_hand().model_copy(update={"closed_tiles": ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "S", "S", "S", "2p", "2p"]})
    context = base_context(round_wind="E", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert result.han == 1
    assert any(y.name == "自風 南" for y in result.yaku)


def test_score_hand_shape_adds_double_wind_yakuhai():
    context = base_context(round_wind="E", seat_wind="E", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(base_hand(), context, RuleSet())
    assert result.han == 2
    assert any(y.name == "場風 東" for y in result.yaku)
    assert any(y.name == "自風 東" for y in result.yaku)


def test_score_hand_shape_adds_dragon_yakuhai():
    hand = base_hand().model_copy(update={"closed_tiles": ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "P", "P", "P", "2p", "2p"]})
    context = base_context(round_wind="E", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert result.han == 1
    assert any(y.name == "役牌 白" for y in result.yaku)


def test_score_hand_shape_adds_closed_ittsuu():
    hand = base_hand().model_copy(
        update={"closed_tiles": ["1m", "2m", "3m", "4m", "5m", "6m", "7m", "8m", "9m", "2p", "2p", "2p", "5s", "5s"]}
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert result.han == 2
    assert any(y.name == "一気通貫" and y.han == 2 for y in result.yaku)


def test_score_hand_shape_adds_open_ittsuu():
    hand = HandInput(
        closed_tiles=["4m", "5m", "6m", "7m", "8m", "9m", "2p", "2p", "2p", "5s", "5s"],
        melds=[{"type": "chi", "tiles": ["1m", "2m", "3m"], "open": True}],
        win_tile="5s",
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert result.han == 1
    assert any(y.name == "一気通貫" and y.han == 1 for y in result.yaku)


def test_score_hand_shape_does_not_add_ittsuu_for_near_shape():
    hand = base_hand().model_copy(
        update={"closed_tiles": ["1m", "2m", "3m", "4m", "5m", "6m", "7p", "8p", "9p", "2s", "2s", "2s", "5s", "5s"]}
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    with pytest.raises(ValueError):
        score_hand_shape(hand, context, RuleSet())


def test_score_hand_shape_adds_toitoi():
    hand = base_hand().model_copy(
        update={"closed_tiles": ["1m", "1m", "1m", "2m", "2m", "2m", "3p", "3p", "3p", "4s", "4s", "4s", "5s", "5s"]}
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert result.han == 2
    assert any(y.name == "対々和" and y.han == 2 for y in result.yaku)


def test_score_hand_shape_adds_sanshoku_doukou():
    hand = base_hand().model_copy(
        update={"closed_tiles": ["1m", "1m", "1m", "1p", "1p", "1p", "1s", "1s", "1s", "9m", "9m", "9m", "5p", "5p"]}
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert result.han == 4
    assert any(y.name == "対々和" and y.han == 2 for y in result.yaku)
    assert any(y.name == "三色同刻" and y.han == 2 for y in result.yaku)


def test_score_hand_shape_does_not_add_sanshoku_doukou_for_sequences():
    hand = base_hand().model_copy(
        update={"closed_tiles": ["1m", "2m", "3m", "1p", "2p", "3p", "1s", "2s", "3s", "7m", "8m", "9m", "5p", "5p"]}
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    with pytest.raises(ValueError):
        score_hand_shape(hand, context, RuleSet())


def test_score_hand_shape_adds_chiitoitsu_and_honroutou():
    hand = base_hand().model_copy(
        update={"closed_tiles": ["1m", "1m", "9m", "9m", "1p", "1p", "9p", "9p", "1s", "1s", "9s", "9s", "E", "E"]}
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert result.han == 4
    assert any(y.name == "七対子" and y.han == 2 for y in result.yaku)
    assert any(y.name == "混老頭" and y.han == 2 for y in result.yaku)


def test_score_hand_shape_adds_honroutou_with_toitoi():
    hand = base_hand().model_copy(
        update={"closed_tiles": ["1m", "1m", "1m", "9m", "9m", "9m", "1p", "1p", "1p", "E", "E", "E", "9s", "9s"]}
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert any(y.name == "対々和" and y.han == 2 for y in result.yaku)
    assert any(y.name == "混老頭" and y.han == 2 for y in result.yaku)


def test_score_hand_shape_does_not_add_honroutou_when_middle_tile_exists():
    hand = base_hand().model_copy(
        update={"closed_tiles": ["1m", "1m", "1m", "9m", "9m", "9m", "1p", "1p", "1p", "9s", "9s", "9s", "5s", "5s"]}
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert any(y.name == "対々和" and y.han == 2 for y in result.yaku)
    assert all(y.name != "混老頭" for y in result.yaku)


def test_score_hand_shape_adds_kokushi():
    hand = HandInput(
        closed_tiles=["1m", "1m", "9m", "1p", "9p", "1s", "9s", "E", "S", "W", "N", "P", "F", "C"],
        melds=[],
        win_tile="9m",
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert result.point_label == "役満"
    assert result.points.ron == 32000
    assert result.yakuman == ["国士無双"]


def test_score_hand_shape_adds_kokushi_13_wait_double_yakuman():
    hand = HandInput(
        closed_tiles=["1m", "9m", "9m", "1p", "9p", "1s", "9s", "E", "S", "W", "N", "P", "F", "C"],
        melds=[],
        win_tile="9m",
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet(double_yakuman_ari=True))
    assert result.point_label == "ダブル役満"
    assert result.points.ron == 64000
    assert result.yakuman == ["国士無双十三面待ち"]
