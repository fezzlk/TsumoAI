import json
from pathlib import Path

import pytest

from app.hand_analysis import analyze_call_options
from app.schemas import CallAnalysisRequest


CONTEXT = dict(
    win_type="ron", is_dealer=False, round_wind="E", seat_wind="S",
    riichi=False, ippatsu=False, haitei=False, houtei=False,
    rinshan=False, chankan=False,
)
EVALUATION = json.loads(
    (Path(__file__).resolve().parents[1] / "data/call_outlook_eval_v1.json").read_text()
)


def analyze_case(case, **updates):
    payload = dict(
        closed_tiles=case["tiles"], rules=case.get("rules", {}),
        context=None if case.get("without_context") else {**CONTEXT, **case.get("context", {})},
    )
    payload.update(updates)
    result = analyze_call_options(CallAnalysisRequest(**payload))
    kind, tile, consumed = case["call"]
    return next(item for item in result.calls if
                (item.call_type, item.call_tile, item.consumed_tiles) == (kind, tile, consumed))


@pytest.mark.parametrize("case", EVALUATION["cases"], ids=lambda case: case["id"])
def test_call_outlook_evaluation_v1(case):
    assert EVALUATION["schema_version"] == 1
    call = analyze_case(case)
    outlook = call.outlook
    assert outlook.status == case["status"]
    assert (outlook.score_estimate is not None) == case["estimate"]
    if "yaku" in case:
        assert case["yaku"] in [item.name for item in outlook.yaku]
    if "warning_contains" in case:
        assert any(case["warning_contains"] in warning for warning in outlook.warnings)
    if "nearby_yaku" in case:
        names = {item.name for item in outlook.nearby_yaku}
        assert set(case["nearby_yaku"]) <= names
        assert not names.intersection(case["excluded_nearby_yaku"])
        assert all(item.condition for item in outlook.nearby_yaku)
        assert not outlook.yaku  # Future routes are not currently available yaku.
        assert any(discard.call_outlook.nearby_yaku for discard in call.discards)
    if outlook.status == "no_yaku":
        assert outlook.no_yaku_tiles
        assert not outlook.winning_tiles
    if outlook.status == "available":
        assert any(discard.call_outlook.winning_tiles for discard in call.discards)


def test_score_opt_out_still_checks_yaku_without_exposing_points():
    call = analyze_case(EVALUATION["cases"][1], include_score_predictions=False)
    assert call.outlook.status == "available"
    assert call.outlook.score_estimate is None
    assert all(wait.ron_points is None and wait.tsumo_dealer_pay is None
               for discard in call.discards for wait in discard.call_outlook.winning_tiles)


def test_special_win_flags_do_not_rescue_yakuless_call():
    call = analyze_case(EVALUATION["cases"][0], context={**CONTEXT, "houtei": True})
    assert call.outlook.status == "no_yaku"


def test_sanshoku_reference_is_open_one_han_and_not_a_promised_score():
    call = analyze_case(EVALUATION["cases"][3])
    sanshoku = next(item for item in call.outlook.yaku if item.name == "三色同順")
    assert sanshoku.han == 1
    assert "123" in sanshoku.condition
    assert "成立した場合" in call.outlook.score_estimate.basis


def test_waits_distinguish_sanshoku_and_no_yaku():
    case = dict(tiles=["3m", "4m", "3p", "4p", "5p", "4s", "5s", "7p", "7p", "7p", "9s", "9s", "C"],
                call=["chi", "5m", ["3m", "4m"]])
    call = analyze_case(case)
    discard = next(item for item in call.discards if item.discard == "C")
    outlook = discard.call_outlook
    assert outlook.status == "available"
    assert {wait.tile for wait in outlook.winning_tiles} == {"3s"}
    assert outlook.no_yaku_tiles == ["6s"]
    assert {wait.win_type for wait in outlook.winning_tiles} == {"ron", "tsumo"}
    assert outlook.score_estimate.min_points == 1000  # 1 han, 30 fu, non-dealer ron
    assert all(wait.tsumo_dealer_pay is None for wait in outlook.winning_tiles if wait.win_type == "ron")
    assert all(wait.ron_points is None for wait in outlook.winning_tiles if wait.win_type == "tsumo")


def test_tsumo_only_sanankou_is_not_reported_as_no_yaku():
    case = dict(tiles=["1m", "2m", "2p", "2p", "2p", "4p", "4p", "4p", "7s", "7s", "8p", "8p", "E"],
                call=["chi", "3m", ["1m", "2m"]])
    call = analyze_case(case)
    outlook = next(item for item in call.discards if item.discard == "E").call_outlook
    assert outlook.status == "available"
    assert all(wait.win_type == "tsumo" for wait in outlook.winning_tiles)
    assert "三暗刻" in {name for wait in outlook.winning_tiles for name in wait.yaku}
    assert outlook.score_estimate.win_type == "tsumo"
    assert not outlook.no_yaku_tiles
    assert any("ツモでのみ" in warning for warning in outlook.warnings)


def test_red_five_in_called_meld_contributes_to_score():
    case = dict(tiles=["4m", "5mr", *EVALUATION["cases"][1]["tiles"][2:]], call=["chi", "6m", ["4m", "5m"]])
    call = analyze_case(case)
    outlook = next(item for item in call.discards if item.discard == "C").call_outlook
    assert all(wait.han >= 2 for wait in outlook.winning_tiles)
    assert outlook.score_estimate.min_points >= 2000


def test_discarding_red_five_removes_its_bonus():
    case = dict(tiles=["5pr", "2m", "3m", "4m", "4p", "5p", "6p", "6s", "7s", "8s", "4p", "F", "F"],
                call=["pon", "F", ["F", "F"]],
                context={"aka_dora_count": 1})
    call = analyze_case(case)
    outlook = next(item for item in call.discards if item.discard == "5p").call_outlook
    assert all(wait.han == 1 for wait in outlook.winning_tiles)


def test_missing_or_failed_score_is_unknown_not_no_yaku():
    from app.call_outlook import assess_call_branch
    from app.schemas import Meld, WaitAnalysis
    request = CallAnalysisRequest(closed_tiles=["2p"] * 2, context=CONTEXT,
                                  melds=[Meld(type="chi", tiles=["1m", "2m", "3m"], open=True)])
    outcome = assess_call_branch(request, request.closed_tiles, 0,
                                [WaitAnalysis(tile="3p", remaining=1, score_error="unexpected scoring failure")],
                                [WaitAnalysis(tile="3p", remaining=1, score_error="unexpected scoring failure")])
    assert outcome.status == "unknown"
    assert outcome.score_estimate is None


def test_tiles_locked_in_unrelated_meld_cannot_make_sanshoku_prospect():
    from app.call_outlook import assess_call_branch
    from app.schemas import Meld
    request = CallAnalysisRequest(
        closed_tiles=["1p", "2p", "3p", "1s", "2s", "5p", "5p"], context=CONTEXT,
        melds=[Meld(type="chi", tiles=["1m", "2m", "3m"], open=True),
               Meld(type="chi", tiles=["3s", "4s", "5s"], open=True),
               Meld(type="pon", tiles=["E", "E", "E"], open=True)],
    )
    outcome = assess_call_branch(request, request.closed_tiles, 1, [])
    assert "三色同順" not in {item.name for item in outcome.yaku}
