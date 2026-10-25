import json
from pathlib import Path

import pytest

from app.domain.rules import ResolvedRules
from app.hand_analysis import analyze_tenpai, analyze_discard_options, analyze_call_options
from app.hand_validation import validate_rule_state
from app.hand_scoring import score_hand_shape
from app.schemas import ContextInput, HandInput, RuleSet, Meld, TenpaiAnalysisRequest, DiscardAnalysisRequest, CallAnalysisRequest
from app.scoring.payments import calculate_payments
from app.scoring.dora import evaluate_dora, _next_dora

SANMA = RuleSet(variant="sanma")
HAND = ["1p", "2p", "3p", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "2s", "2s"]


def context(**updates):
    values = dict(win_type="ron", is_dealer=False, round_wind="E", seat_wind="S", riichi=False,
                  ippatsu=False, haitei=False, houtei=False, rinshan=False, chankan=False)
    return ContextInput(**{**values, **updates})


@pytest.mark.parametrize("case", json.loads((Path(__file__).parents[1] / "data/sanma_domain_eval_v1.json").read_text())["payments"])
def test_standard_payments(case):
    ctx = context(win_type=case["win_type"], seat_wind=case["seat_wind"], honba=case["honba"], kyotaku=1)
    _, payments = calculate_payments(ctx, 5, 30, player_count=3)
    assert payments.hand_points_received == case["received"]
    assert payments.hand_points_with_honba == case["with_honba"]
    assert payments.total_received == case["with_honba"] + 1000


def test_tile_supply_and_dora_cycles():
    supply = ResolvedRules("sanma").tile_supply
    assert sum(supply) == 108
    assert supply[0] == supply[8] == 4
    assert supply[1:8] == (0,) * 7
    assert _next_dora("1m", SANMA) == "9m"
    assert _next_dora("9m", SANMA) == "1m"
    assert _next_dora("1m") == "2m"


@pytest.mark.parametrize("tile", ["2m", "5m", "8m", "5mr"])
def test_unavailable_tiles_rejected_even_without_context(tile):
    with pytest.raises(ValueError, match="unavailable"):
        validate_rule_state([tile], [], [], SANMA)


def test_north_counts_and_chi_and_seat_validation():
    with pytest.raises(ValueError, match="four copies"):
        validate_rule_state(["N"] * 3, [], ["N"] * 2, SANMA)
    with pytest.raises(ValueError, match="Only north"):
        validate_rule_state([], [], ["E"], SANMA)
    with pytest.raises(ValueError, match="three-player"):
        validate_rule_state([], [], ["N"], RuleSet())
    with pytest.raises(ValueError, match="Chi"):
        validate_rule_state([], [Meld(type="chi", tiles=["1p", "2p", "3p"], open=True)], [], SANMA)
    with pytest.raises(ValueError, match="seat wind"):
        validate_rule_state([], [], [], SANMA, context(seat_wind="N"))
    with pytest.raises(ValueError, match="indicator"):
        validate_rule_state([], [], [], SANMA, context(dora_indicators=["2m"]))


def test_nuki_dora_is_independent_and_keeps_menzen():
    hand = HandInput(closed_tiles=HAND, win_tile="2s", extracted_tiles=["N"])
    score = score_hand_shape(hand, context(win_type="tsumo", dora_indicators=["W"]), SANMA)
    assert score.dora.nuki_dora == 1
    assert score.dora.dora == 1
    assert "門前清自摸和" in [y.name for y in score.yaku]
    assert "抜きドラ" in [y.name for y in score.yaku]
    baseline = score_hand_shape(hand.model_copy(update={"extracted_tiles": []}), context(win_type="tsumo"), SANMA)
    assert score.han == baseline.han + 2
    assert score.fu == baseline.fu


def test_nuki_dora_alone_is_not_a_ron_yaku():
    hand = HandInput(closed_tiles=["1p", "2p", "3p", "4p", "5p", "6p", "7s", "8s", "9s", "1s", "2s", "3s", "2s", "2s"], win_tile="2s", extracted_tiles=["N"])
    with pytest.raises(ValueError, match="No yaku"):
        score_hand_shape(hand, context(), SANMA)


def test_ura_requires_riichi_and_extraction_does_not_open_hand():
    hand = HandInput(closed_tiles=HAND, win_tile="2s", extracted_tiles=["N"])
    dora, _ = evaluate_dora(hand, context(ura_dora_indicators=["W"]), SANMA)
    assert dora.ura_dora == 0
    dora, _ = evaluate_dora(hand, context(riichi=True, ura_dora_indicators=["W"]), SANMA)
    assert dora.ura_dora == 1


def test_north_extractions_reduce_visible_waits_without_changing_shape():
    tiles = ["1p", "2p", "3p", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "N"]
    request = TenpaiAnalysisRequest(closed_tiles=tiles, extracted_tiles=["N"] * 3, rules=SANMA)
    result = analyze_tenpai(request)
    assert result.shanten == 0
    assert [(w.tile, w.remaining) for w in result.improving_tiles] == [("N", 0)]


def test_analysis_never_generates_unavailable_tiles_or_chi():
    tiles = HAND[:-1]
    result = analyze_tenpai(TenpaiAnalysisRequest(closed_tiles=tiles, rules=SANMA, context=context()))
    assert all(ResolvedRules("sanma").allows_tile(w.tile) for w in result.improving_tiles)
    discards = analyze_discard_options(DiscardAnalysisRequest(closed_tiles=HAND, rules=SANMA))
    assert all(ResolvedRules("sanma").allows_tile(w.tile) for d in discards.discards for w in d.improving_tiles)
    calls = analyze_call_options(CallAnalysisRequest(closed_tiles=tiles, rules=SANMA))
    assert all(c.call_type != "chi" for c in calls.calls)


def test_call_current_waits_keep_extracted_north_counts():
    tiles = ["1p", "2p", "3p", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "N"]
    result = analyze_call_options(CallAnalysisRequest(closed_tiles=tiles, extracted_tiles=["N"] * 3,
                                                     rules=SANMA, context=context()))
    assert [(wait.tile, wait.remaining) for wait in result.current_waits] == [("N", 0)]
