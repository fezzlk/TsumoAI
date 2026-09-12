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
    assert result.han == 4
    assert result.fu == 40
    assert [item.model_dump() for item in result.fu_breakdown] == [{"name": "副底", "fu": 20}, {"name": "門前ロン", "fu": 10}, {"name": "待ち", "fu": 2}, {"name": "面子", "fu": 8}]
    assert result.point_label == "満貫"
    assert result.points.ron == 8000
    assert result.payments.hand_points_received == 8000
    assert result.payments.hand_points_with_honba == 8000
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
    result = score_hand_shape(base_hand(), context, RuleSet())
    assert any(y.name == "門前清自摸和" for y in result.yaku)





def test_score_hand_shape_uses_seat_wind_for_dealer_ron():
    context = base_context(
        win_type="ron",
        is_dealer=False,
        seat_wind="E",
        round_wind="S",
        riichi=True,
        aka_dora_count=2,
        dora_indicators=["4m"],
    )
    result = score_hand_shape(base_hand(), context, RuleSet())
    assert result.points.ron == 12000


def test_score_hand_shape_uses_seat_wind_for_dealer_tsumo():
    context = base_context(
        win_type="tsumo",
        is_dealer=False,
        seat_wind="E",
        round_wind="S",
        riichi=True,
        aka_dora_count=2,
        dora_indicators=["4m"],
    )
    result = score_hand_shape(base_hand(), context, RuleSet())
    assert result.points.tsumo_dealer_pay == 4000
    assert result.points.tsumo_non_dealer_pay == 4000
    assert result.payments.hand_points_received == 12000

def test_score_hand_shape_includes_fu_breakdown_for_pinfu_tsumo():
    hand = HandInput(
        closed_tiles=["1m", "2m", "3m", "4m", "5m", "6m", "3p", "4p", "5p", "6s", "7s", "8s", "5p", "5p"],
        melds=[],
        win_tile="5p",
    )
    context = base_context(
        win_type="tsumo",
        riichi=False,
        aka_dora_count=0,
        dora_indicators=[],
        round_wind="E",
        seat_wind="S",
    )
    result = score_hand_shape(hand, context, RuleSet())
    assert result.fu == 20
    assert [item.model_dump() for item in result.fu_breakdown] == [{"name": "副底", "fu": 20}]


def test_score_hand_shape_payments_breakdown_with_honba_kyotaku():
    context = base_context(
        honba=2,
        kyotaku=1,
    )
    result = score_hand_shape(base_hand(), context, RuleSet())
    assert result.payments.hand_points_received == 8000
    assert result.payments.honba_bonus == 600
    assert result.payments.hand_points_with_honba == 8600
    assert result.payments.kyotaku_bonus == 1000
    assert result.payments.total_received == 9600


def test_score_hand_shape_limit_label_haneman():
    context = base_context(
        win_type="ron",
        riichi=True,
        ippatsu=True,
        haitei=True,
        houtei=False,
        rinshan=False,
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
    hand = HandInput(
        closed_tiles=["2m", "2m", "2m", "3p", "3p", "3p", "4s", "4s", "4s", "5s", "5s"],
        melds=[{"type": "pon", "tiles": ["1m", "1m", "1m"], "open": True}],
        win_tile="5s",
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert result.han == 4
    assert any(y.name == "対々和" and y.han == 2 for y in result.yaku)
    assert any(y.name == "三暗刻" and y.han == 2 for y in result.yaku)


def test_score_hand_shape_adds_sanshoku_doukou():
    hand = HandInput(
        closed_tiles=["1p", "1p", "1p", "1s", "1s", "1s", "9m", "9m", "9m", "5p", "5p"],
        melds=[{"type": "pon", "tiles": ["1m", "1m", "1m"], "open": True}],
        win_tile="5p",
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert result.han == 6
    assert any(y.name == "対々和" and y.han == 2 for y in result.yaku)
    assert any(y.name == "三色同刻" and y.han == 2 for y in result.yaku)
    assert any(y.name == "三暗刻" and y.han == 2 for y in result.yaku)


def test_score_hand_shape_does_not_add_sanshoku_doukou_for_sequences():
    hand = base_hand().model_copy(
        update={"closed_tiles": ["1m", "2m", "3m", "1p", "2p", "3p", "1s", "2s", "3s", "7m", "8m", "9m", "5p", "5p"]}
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert all(y.name != "三色同刻" for y in result.yaku)
    assert any(y.name == "三色同順" for y in result.yaku)


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
    hand = HandInput(
        closed_tiles=["9m", "9m", "9m", "1p", "1p", "1p", "E", "E", "E", "9s", "9s"],
        melds=[{"type": "pon", "tiles": ["1m", "1m", "1m"], "open": True}],
        win_tile="9s",
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert any(y.name == "対々和" and y.han == 2 for y in result.yaku)
    assert any(y.name == "混老頭" and y.han == 2 for y in result.yaku)


def test_score_hand_shape_does_not_add_honroutou_when_middle_tile_exists():
    hand = HandInput(
        closed_tiles=["9m", "9m", "9m", "1p", "1p", "1p", "9s", "9s", "9s", "5s", "5s"],
        melds=[{"type": "pon", "tiles": ["1m", "1m", "1m"], "open": True}],
        win_tile="5s",
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


def test_score_hand_shape_adds_daisangen():
    hand = HandInput(
        closed_tiles=["P", "P", "P", "F", "F", "F", "C", "C", "C", "1m", "1m", "1m", "9p", "9p"],
        melds=[],
        win_tile="9p",
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert "大三元" in result.yakuman
    assert "四暗刻単騎" in result.yakuman
    assert result.point_label == "3倍役満"


def test_score_hand_shape_adds_tsuuiisou():
    hand = HandInput(
        closed_tiles=["E", "E", "E", "S", "S", "S", "W", "W", "W", "P", "P", "P", "F", "F"],
        melds=[],
        win_tile="F",
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert "字一色" in result.yakuman


def test_score_hand_shape_adds_ryuuiisou():
    hand = HandInput(
        closed_tiles=["2s", "2s", "2s", "3s", "3s", "3s", "4s", "4s", "4s", "F", "F", "F", "8s", "8s"],
        melds=[],
        win_tile="8s",
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert "緑一色" in result.yakuman


def test_score_hand_shape_adds_chuuren_poutou():
    hand = HandInput(
        closed_tiles=["1m", "1m", "1m", "2m", "3m", "4m", "5m", "6m", "7m", "8m", "9m", "9m", "9m", "5m"],
        melds=[],
        win_tile="5m",
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet(double_yakuman_ari=True))
    assert "純正九蓮宝燈" in result.yakuman
    assert result.point_label == "ダブル役満"


def test_score_hand_shape_adds_tanyao():
    hand = HandInput(
        closed_tiles=["2m", "3m", "4m", "3p", "4p", "5p", "4s", "5s", "6s", "6m", "7m", "8m", "6p", "6p"],
        melds=[],
        win_tile="6p",
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert any(y.name == "断么九" for y in result.yaku)


def test_score_hand_shape_does_not_add_fake_dora_from_indicator():
    hand = base_hand().model_copy(update={"win_tile": "E"})
    context = base_context(riichi=False, double_riichi=False, aka_dora_count=0, dora_indicators=["4m"])
    result = score_hand_shape(hand, context, RuleSet())
    assert result.dora.dora == 0
    assert all(y.name != "ドラ" for y in result.yaku)


def test_score_hand_shape_adds_menzen_tsumo():
    hand = base_hand().model_copy(update={"win_tile": "2p"})
    context = base_context(
        win_type="tsumo",
        round_wind="W",
        seat_wind="S",
        riichi=False,
        double_riichi=False,
        aka_dora_count=0,
        dora_indicators=[],
    )
    result = score_hand_shape(hand, context, RuleSet())
    assert any(y.name == "門前清自摸和" and y.han == 1 for y in result.yaku)


def test_score_hand_shape_adds_sanshoku_doujun():
    hand = HandInput(
        closed_tiles=["1m", "2m", "3m", "1p", "2p", "3p", "1s", "2s", "3s", "7m", "8m", "9m", "5p", "5p"],
        melds=[],
        win_tile="5p",
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert any(y.name == "三色同順" and y.han == 2 for y in result.yaku)


def test_score_hand_shape_adds_chanta():
    hand = HandInput(
        closed_tiles=["1m", "2m", "3m", "7p", "8p", "9p", "E", "E", "E", "9s", "9s", "9s", "1p", "1p"],
        melds=[],
        win_tile="1p",
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert any(y.name == "混全帯么九" and y.han == 2 for y in result.yaku)


def test_score_hand_shape_adds_junchan():
    hand = HandInput(
        closed_tiles=["1m", "2m", "3m", "7p", "8p", "9p", "1s", "2s", "3s", "9m", "9m", "9m", "1p", "1p"],
        melds=[],
        win_tile="1p",
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert any(y.name == "純全帯么九" and y.han == 3 for y in result.yaku)
    assert all(y.name != "混全帯么九" for y in result.yaku)


def test_score_hand_shape_adds_honitsu_and_chinitsu():
    honitsu_hand = HandInput(
        closed_tiles=["1m", "2m", "3m", "4m", "5m", "6m", "7m", "8m", "9m", "E", "E", "E", "1m", "1m"],
        melds=[],
        win_tile="1m",
    )
    chinitsu_hand = HandInput(
        closed_tiles=["1m", "2m", "3m", "4m", "5m", "6m", "7m", "8m", "9m", "2m", "2m", "2m", "5m", "5m"],
        melds=[],
        win_tile="5m",
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    honitsu_result = score_hand_shape(honitsu_hand, context, RuleSet())
    chinitsu_result = score_hand_shape(chinitsu_hand, context, RuleSet())
    assert any(y.name == "混一色" for y in honitsu_result.yaku)
    assert any(y.name == "清一色" for y in chinitsu_result.yaku)


def test_score_hand_shape_adds_sanankou_with_open_chi():
    hand = HandInput(
        closed_tiles=["2m", "2m", "2m", "3p", "3p", "3p", "4s", "4s", "4s", "5s", "5s"],
        melds=[{"type": "chi", "tiles": ["1m", "2m", "3m"], "open": True}],
        win_tile="5s",
    )
    context = base_context(round_wind="W", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert any(y.name == "三暗刻" and y.han == 2 for y in result.yaku)


def test_score_hand_shape_adds_pinfu():
    hand = HandInput(
        closed_tiles=["1m", "2m", "3m", "4m", "5m", "6m", "2p", "3p", "4p", "6s", "7s", "8s", "5p", "5p"],
        melds=[],
        win_tile="2p",
    )
    context = base_context(round_wind="E", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert any(y.name == "平和" and y.han == 1 for y in result.yaku)


def test_score_hand_shape_pinfu_tsumo_is_20_fu():
    hand = HandInput(
        closed_tiles=["1m", "2m", "3m", "4m", "5m", "6m", "2p", "3p", "4p", "6s", "7s", "8s", "5p", "5p"],
        melds=[],
        win_tile="2p",
    )
    context = base_context(
        win_type="tsumo",
        round_wind="E",
        seat_wind="S",
        riichi=False,
        aka_dora_count=0,
        dora_indicators=[],
    )
    result = score_hand_shape(hand, context, RuleSet())
    assert any(y.name == "平和" and y.han == 1 for y in result.yaku)
    assert result.fu == 20


def test_score_hand_shape_suuankou_tanki_tsumo():
    """四暗刻単騎: 4 closed pons + pair with tsumo on pair tile."""
    hand = HandInput(
        closed_tiles=["1m", "1m", "1m", "2m", "2m", "2m", "3m", "3m", "3m", "4m", "4m", "4m", "5p", "5p"],
        melds=[],
        win_tile="5p",
    )
    context = base_context(win_type="tsumo", riichi=False, aka_dora_count=0, dora_indicators=["F"])
    result = score_hand_shape(hand, context, RuleSet(double_yakuman_ari=True))
    assert "四暗刻単騎" in result.yakuman
    assert result.point_label == "ダブル役満"


def test_score_hand_shape_suuankou_not_on_ron_completing_pon():
    """Ron on a tile completing a triplet -> not suuankou."""
    hand = HandInput(
        closed_tiles=["2p", "2p", "1m", "1m", "1m", "2m", "2m", "2m", "3m", "3m", "3m", "4p", "4p", "4p"],
        melds=[],
        win_tile="1m",
    )
    context = base_context(win_type="ron", riichi=False, aka_dora_count=0, dora_indicators=["3m"])
    result = score_hand_shape(hand, context, RuleSet())
    assert all(y not in result.yakuman for y in ["四暗刻", "四暗刻単騎"])
    assert any(y.name == "三暗刻" for y in result.yaku)


def test_score_hand_shape_sanankou_ron_on_pon():
    """Ron completing the 4th triplet -> only sanankou, not suuankou."""
    hand = HandInput(
        closed_tiles=["2p", "2p", "1m", "2m", "3m", "1m", "2m", "3m", "1m", "2m", "3m", "4p", "4p", "4p"],
        melds=[],
        win_tile="1m",
    )
    context = base_context(win_type="ron", riichi=False, aka_dora_count=0, dora_indicators=["3m"])
    result = score_hand_shape(hand, context, RuleSet())
    assert all(y not in result.yakuman for y in ["四暗刻", "四暗刻単騎"])


def test_score_hand_shape_suuankou_tanki_ron():
    """Ron on pair tile with 4 closed triplets -> suuankou tanki."""
    hand = HandInput(
        closed_tiles=["1m", "1m", "1m", "2m", "2m", "2m", "3m", "3m", "3m", "4m", "4m", "4m", "5p", "5p"],
        melds=[],
        win_tile="5p",
    )
    context = base_context(win_type="ron", riichi=False, aka_dora_count=0, dora_indicators=["F"])
    result = score_hand_shape(hand, context, RuleSet(double_yakuman_ari=True))
    assert "四暗刻単騎" in result.yakuman


def test_score_hand_shape_ryanpeikou():
    """Two identical chi pairs = ryanpeikou, not chiitoitsu."""
    hand = HandInput(
        closed_tiles=["1m", "1m", "2m", "2m", "3m", "3m", "4m", "4m", "5m", "5m", "6m", "6m", "7m", "7m"],
        melds=[],
        win_tile="1m",
    )
    context = base_context(win_type="ron", riichi=False, aka_dora_count=0, dora_indicators=["4p"])
    result = score_hand_shape(hand, context, RuleSet())
    assert any(y.name == "二盃口" and y.han == 3 for y in result.yaku)
    assert all(y.name != "七対子" for y in result.yaku)
    assert all(y.name != "一盃口" for y in result.yaku)


def test_score_hand_shape_adds_rinshan_with_kan():
    """Rinshan flag with an actual kan present -> rinshan kaihou is granted."""
    hand = HandInput(
        closed_tiles=["2p", "2p", "1m", "2m", "3m", "2m", "3m", "4m", "5m", "6m", "7m"],
        melds=[{"type": "kan", "tiles": ["9s", "9s", "9s", "9s"], "open": False}],
        win_tile="6m",
    )
    context = base_context(win_type="tsumo", riichi=False, aka_dora_count=0, dora_indicators=["F"], rinshan=True)
    result = score_hand_shape(hand, context, RuleSet())
    assert any(y.name == "嶺上開花" and y.han == 1 for y in result.yaku)


def test_score_hand_shape_rinshan_requires_kan():
    """Rinshan flag without any kan -> rinshan yaku should not be added."""
    hand = HandInput(
        closed_tiles=["2p", "2p", "1m", "2m", "3m", "2m", "3m", "4m", "5m", "6m", "7m", "6p", "7p", "8p"],
        melds=[],
        win_tile="6m",
    )
    context = base_context(win_type="tsumo", riichi=False, aka_dora_count=0, dora_indicators=["F"], rinshan=True)
    result = score_hand_shape(hand, context, RuleSet())
    assert all(y.name != "嶺上開花" for y in result.yaku)


def test_score_hand_shape_pinfu_ron_is_30_fu():
    """Pinfu + ron should always be 30fu regardless of wait interpretation."""
    hand = HandInput(
        closed_tiles=["2p", "2p", "1m", "2m", "3m", "2m", "3m", "4m", "3p", "4p", "5p", "6p", "7p", "8p"],
        melds=[],
        win_tile="2m",
    )
    context = base_context(win_type="ron", riichi=False, aka_dora_count=0, dora_indicators=["3m"])
    result = score_hand_shape(hand, context, RuleSet())
    assert any(y.name == "平和" for y in result.yaku)
    assert result.fu == 30


def test_score_hand_shape_does_not_add_pinfu_for_value_pair():
    hand = HandInput(
        closed_tiles=["1m", "2m", "3m", "4m", "5m", "6m", "2p", "3p", "4p", "6s", "7s", "8s", "E", "E"],
        melds=[],
        win_tile="2p",
    )
    context = base_context(round_wind="E", seat_wind="S", riichi=True, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert all(y.name != "平和" for y in result.yaku)


def test_score_hand_shape_adds_shousangen():
    hand = HandInput(
        closed_tiles=["1m", "2m", "3m", "4p", "5p", "6p", "C", "C"],
        melds=[
            {"type": "pon", "tiles": ["P", "P", "P"], "open": True},
            {"type": "pon", "tiles": ["F", "F", "F"], "open": True},
        ],
        win_tile="C",
    )
    context = base_context(round_wind="W", seat_wind="N", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert result.han == 4
    assert any(y.name == "小三元" and y.han == 2 for y in result.yaku)
    assert any(y.name == "役牌 白" for y in result.yaku)
    assert any(y.name == "役牌 發" for y in result.yaku)


def test_score_hand_shape_adds_sankantsu():
    hand = HandInput(
        closed_tiles=["1m", "2m", "3m", "2p", "2p"],
        melds=[
            {"type": "kan", "tiles": ["E", "E", "E", "E"], "open": True},
            {"type": "kan", "tiles": ["S", "S", "S", "S"], "open": True},
            {"type": "kan", "tiles": ["W", "W", "W", "W"], "open": True},
        ],
        win_tile="2p",
    )
    context = base_context(round_wind="N", seat_wind="N", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert result.han == 2
    assert any(y.name == "三槓子" and y.han == 2 for y in result.yaku)


def test_score_hand_shape_adds_suukantsu():
    """Four kans on number tiles only, to isolate suukantsu from daisuushii."""
    hand = HandInput(
        closed_tiles=["5p", "5p"],
        melds=[
            {"type": "kan", "tiles": ["1m", "1m", "1m", "1m"], "open": True},
            {"type": "kan", "tiles": ["9m", "9m", "9m", "9m"], "open": True},
            {"type": "kan", "tiles": ["1p", "1p", "1p", "1p"], "open": True},
            {"type": "kan", "tiles": ["9s", "9s", "9s", "9s"], "open": True},
        ],
        win_tile="5p",
    )
    context = base_context(round_wind="W", seat_wind="N", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert result.yakuman == ["四槓子"]
    assert result.point_label == "役満"


def test_score_hand_shape_adds_daisuushii_with_suukantsu():
    """All four winds as kans -> compound yakuman (daisuushii + suukantsu)."""
    hand = HandInput(
        closed_tiles=["5p", "5p"],
        melds=[
            {"type": "kan", "tiles": ["E", "E", "E", "E"], "open": True},
            {"type": "kan", "tiles": ["S", "S", "S", "S"], "open": True},
            {"type": "kan", "tiles": ["W", "W", "W", "W"], "open": True},
            {"type": "kan", "tiles": ["N", "N", "N", "N"], "open": True},
        ],
        win_tile="5p",
    )
    context = base_context(round_wind="W", seat_wind="N", riichi=False, aka_dora_count=0, dora_indicators=[])
    result = score_hand_shape(hand, context, RuleSet())
    assert "大四喜" in result.yakuman
    assert "四槓子" in result.yakuman
    assert result.point_label == "3倍役満"


def test_score_hand_shape_adds_tenhou():
    context = base_context(
        win_type="tsumo", is_dealer=True, round_wind="W", seat_wind="N",
        riichi=False, aka_dora_count=0, dora_indicators=[], tenhou=True,
    )
    result = score_hand_shape(base_hand(), context, RuleSet())
    assert result.yakuman == ["天和"]
    assert result.han == 13
    assert result.point_label == "役満"


def test_score_hand_shape_adds_chiihou():
    context = base_context(
        win_type="tsumo", is_dealer=False, round_wind="W", seat_wind="N",
        riichi=False, aka_dora_count=0, dora_indicators=[], chiihou=True,
    )
    result = score_hand_shape(base_hand(), context, RuleSet())
    assert result.yakuman == ["地和"]
    assert result.han == 13


def test_score_hand_shape_adds_haitei():
    context = base_context(
        win_type="tsumo", round_wind="W", seat_wind="N",
        riichi=False, aka_dora_count=0, dora_indicators=[], haitei=True,
    )
    result = score_hand_shape(base_hand(), context, RuleSet())
    assert any(y.name == "海底摸月" and y.han == 1 for y in result.yaku)


def test_score_hand_shape_adds_houtei():
    context = base_context(
        win_type="ron", round_wind="W", seat_wind="N",
        riichi=False, aka_dora_count=0, dora_indicators=[], houtei=True,
    )
    result = score_hand_shape(base_hand(), context, RuleSet())
    assert any(y.name == "河底撈魚" and y.han == 1 for y in result.yaku)


def test_score_hand_shape_adds_chankan():
    context = base_context(
        win_type="ron", round_wind="W", seat_wind="N",
        riichi=False, aka_dora_count=0, dora_indicators=[], chankan=True,
    )
    result = score_hand_shape(base_hand(), context, RuleSet())
    assert any(y.name == "槍槓" and y.han == 1 for y in result.yaku)


def test_score_hand_shape_denies_tanyao_when_kuitan_nashi():
    """Open hand + kuitan_ari=False -> tanyao must not apply, leaving no yaku."""
    hand = HandInput(
        closed_tiles=["2m", "3m", "4m", "3p", "4p", "5p", "4s", "5s", "6s", "6p", "6p"],
        melds=[{"type": "chi", "tiles": ["6m", "7m", "8m"], "open": True}],
        win_tile="6p",
    )
    context = base_context(round_wind="W", seat_wind="N", riichi=False, aka_dora_count=0, dora_indicators=[])
    with pytest.raises(ValueError):
        score_hand_shape(hand, context, RuleSet(kuitan_ari=False))


def test_score_hand_shape_denies_pinfu_for_penchan_1_2_wait():
    """1m2m3m completed on 3m via penchan (1-2 wait) must not grant pinfu."""
    hand = HandInput(
        closed_tiles=["1m", "2m", "3m", "4m", "5m", "6m", "2p", "3p", "4p", "6s", "7s", "8s", "5p", "5p"],
        melds=[],
        win_tile="3m",
    )
    context = base_context(round_wind="E", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    with pytest.raises(ValueError):
        score_hand_shape(hand, context, RuleSet())


def test_score_hand_shape_denies_pinfu_for_penchan_8_9_wait():
    """7m8m9m completed on 7m via penchan (8-9 wait) must not grant pinfu."""
    hand = HandInput(
        closed_tiles=["7m", "8m", "9m", "4m", "5m", "6m", "2p", "3p", "4p", "6s", "7s", "8s", "5p", "5p"],
        melds=[],
        win_tile="7m",
    )
    context = base_context(round_wind="E", seat_wind="S", riichi=False, aka_dora_count=0, dora_indicators=[])
    with pytest.raises(ValueError):
        score_hand_shape(hand, context, RuleSet())


def test_score_hand_shape_tsumo_fu_includes_tsumo_and_rounds_up():
    """Non-pinfu tsumo adds the 2fu 'ツモ' item, and odd totals round up (切り上げ)."""
    context = base_context(
        win_type="tsumo", round_wind="E", seat_wind="S",
        riichi=False, aka_dora_count=0, dora_indicators=[],
    )
    result = score_hand_shape(base_hand(), context, RuleSet())
    assert result.fu == 40
    breakdown = {item.name: item.fu for item in result.fu_breakdown}
    assert breakdown["ツモ"] == 2
    assert breakdown["切り上げ"] == 8
