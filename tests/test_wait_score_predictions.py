import json
from pathlib import Path

import pytest

from app.hand_analysis import analyze_tenpai
from app.schemas import TenpaiAnalysisRequest


CONTEXT = dict(win_type="ron", is_dealer=False, round_wind="E", seat_wind="S",
               riichi=False, ippatsu=False, haitei=False, houtei=False, rinshan=False, chankan=False)
EVALUATION = json.loads((Path(__file__).resolve().parents[1] / "data/wait_score_eval_v1.json").read_text())


@pytest.mark.parametrize("case", EVALUATION["cases"], ids=lambda case: case["id"])
def test_wait_score_evaluation_v1(case):
    assert EVALUATION["schema_version"] == 1
    result = analyze_tenpai(TenpaiAnalysisRequest(closed_tiles=case["tiles"], melds=case.get("melds", []), context=CONTEXT))
    assert result.shanten == 0
    for tile, expected in case["waits"].items():
        wait = next(wait for wait in result.improving_tiles if wait.tile == tile)
        for kind in ("ron", "tsumo"):
            score = getattr(wait, f"{kind}_score")
            error = getattr(wait, f"{kind}_score_error")
            if expected.get(f"{kind}_no_yaku"):
                assert score is None
                assert error == "No yaku: dora-only hands cannot win"
            else:
                assert error is None
                assert set(expected[f"{kind}_yaku"]).issubset({item.name for item in score.yaku})
                if f"{kind}_points" in expected:
                    assert score.payments.hand_points_received == expected[f"{kind}_points"]


def test_riichi_red_dora_and_bonuses_are_preserved_for_both_win_types():
    tiles = ["1m", "2m", "3m", "4p", "5pr", "6p", "7s", "8s", "9s", "E", "E", "E", "2p"]
    result = analyze_tenpai(TenpaiAnalysisRequest(closed_tiles=tiles, context={
        **CONTEXT, "riichi": True, "dora_indicators": ["4p"], "honba": 2, "kyotaku": 1,
    }))
    wait = next(wait for wait in result.improving_tiles if wait.tile == "2p")
    for score in (wait.ron_score, wait.tsumo_score):
        assert "立直" in {item.name for item in score.yaku}
        assert score.dora.aka_dora == 1
        assert score.dora.dora == 1
        assert score.payments.honba_bonus == 600
        assert score.payments.kyotaku_bonus == 1000
        assert score.payments.total_received == score.payments.hand_points_received + 1600
    assert wait.score == wait.ron_score


def test_switching_win_type_clears_only_incompatible_context_flags():
    case = EVALUATION["cases"][1]
    result = analyze_tenpai(TenpaiAnalysisRequest(closed_tiles=case["tiles"], context={**CONTEXT, "win_type": "tsumo", "haitei": True}))
    wait = result.improving_tiles[0]
    assert wait.ron_score is None
    assert wait.ron_score_error == "No yaku: dora-only hands cannot win"
    assert wait.tsumo_score is not None
    assert "海底摸月" in {item.name for item in wait.tsumo_score.yaku}
    assert wait.score == wait.tsumo_score


@pytest.mark.parametrize("overrides", [{"context": None}, {"include_score_predictions": False}])
def test_missing_context_or_opt_out_does_not_invent_scores(overrides):
    case = EVALUATION["cases"][1]
    request = dict(closed_tiles=case["tiles"], context=CONTEXT)
    request.update(overrides)
    result = analyze_tenpai(TenpaiAnalysisRequest(**request))
    assert all(wait.ron_score is None and wait.tsumo_score is None
               and wait.ron_score_error is None and wait.tsumo_score_error is None
               for wait in result.improving_tiles)


def test_non_tenpai_improving_tiles_do_not_receive_winning_scores():
    result = analyze_tenpai(TenpaiAnalysisRequest(
        closed_tiles=["1m", "2m", "4m", "5m", "5m", "7p", "8p", "9p", "2s", "3s", "4s", "E", "E"], context=CONTEXT,
    ))
    assert result.shanten > 0
    assert all(wait.ron_score is None and wait.tsumo_score is None for wait in result.improving_tiles)
