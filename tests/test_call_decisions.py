import json
from pathlib import Path

import pytest

from app.hand_analysis import analyze_call_options
from app.schemas import CallAnalysisRequest


CONTEXT = dict(win_type="ron", is_dealer=False, round_wind="E", seat_wind="S",
               riichi=False, ippatsu=False, haitei=False, houtei=False, rinshan=False, chankan=False)
EVALUATION = json.loads((Path(__file__).resolve().parents[1] / "data/call_decision_eval_v1.json").read_text())


def analyze(case, **updates):
    payload = dict(closed_tiles=case["tiles"], melds=case.get("melds", []), context=CONTEXT)
    payload.update(updates)
    return analyze_call_options(CallAnalysisRequest(**payload))


@pytest.mark.parametrize("case", EVALUATION["cases"], ids=lambda case: case["id"])
@pytest.mark.parametrize("include_scores", [True, False])
def test_call_decision_evaluation_v1(case, include_scores):
    assert EVALUATION["schema_version"] == 1
    result = analyze(case, include_score_predictions=include_scores)
    assert result.current_shanten == 0
    assert {w.tile for w in result.current_waits if w.ron_status == "available"} == set(case["ron_tiles"])
    assert {w.tile for w in result.current_waits if w.ron_status == "no_yaku"} == set(case["no_yaku_tiles"])
    assert not any(c.call_tile in case["ron_tiles"] for c in result.calls)
    if "retained_call" in case:
        kind, tile = case["retained_call"]
        call = next(c for c in result.calls if (c.call_type, c.call_tile) == (kind, tile))
        if "tenpai_effect" in case:
            assert call.tenpai_effect == case["tenpai_effect"]
            assert call.shanten_after_call == 0
            assert any(w.win_type == "ron" and "役牌 發" in w.yaku
                       for d in call.discards for w in d.call_outlook.winning_tiles)


def test_missing_context_keeps_unverified_calls():
    result = analyze(EVALUATION["cases"][0], context=None)
    assert all(w.ron_status == "unknown" for w in result.current_waits)
    assert any(c.call_tile == "F" and c.call_type == "pon" for c in result.calls)
    assert all(c.tenpai_effect != "adds_yaku" for c in result.calls)


def test_scoring_failure_keeps_unverified_calls(monkeypatch):
    def fail(*args):
        raise ValueError("scoring failed")
    monkeypatch.setattr("app.hand_analysis.score_hand_shape", fail)
    result = analyze(EVALUATION["cases"][0])
    assert all(w.ron_status == "unknown" for w in result.current_waits)
    assert any(c.call_tile == "F" for c in result.calls)
    assert all(c.tenpai_effect != "adds_yaku" for c in result.calls)


@pytest.mark.parametrize("flag", ["riichi", "double_riichi"])
def test_riichi_shows_ron_waits_without_open_calls(flag):
    result = analyze(EVALUATION["cases"][2], context={**CONTEXT, flag: True})
    assert all(w.ron_status == "available" for w in result.current_waits)
    assert result.calls == []


def test_tenpai_maintenance_and_breakage_are_distinguished():
    regular = analyze(EVALUATION["cases"][2])
    pairs = analyze(dict(tiles=["1m", "1m", "2m", "2m", "4p", "4p", "5p", "5p", "7s", "7s", "8s", "8s", "F"]))
    assert pairs.current_shanten == 0
    assert any(c.tenpai_effect == "breaks" for c in pairs.calls)
    assert any(c.tenpai_effect == "keeps" for c in regular.calls)
    for call in [*regular.calls, *pairs.calls]:
        assert (call.tenpai_effect == "breaks") == (call.shanten_after_call > 0)


def test_non_tenpai_has_no_current_waits_or_tenpai_effects():
    result = analyze(dict(tiles=["1m", "2m", "4m", "5m", "5m", "7p", "8p", "9p", "2s", "3s", "4s", "E", "E"]))
    assert result.current_shanten > 0
    assert result.current_waits == []
    assert all(c.tenpai_effect is None for c in result.calls)
