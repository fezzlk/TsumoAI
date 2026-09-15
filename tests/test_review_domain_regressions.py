"""Regression contracts for overall-review findings R03 and R07–R11."""

import pytest
from fastapi.testclient import TestClient

from app.domain.analysis import enumerate_improving_tiles
from app.domain.decomposition import is_winning_hand
from app.domain.shanten import standard_shanten
from app.domain.tiles import tiles_to_counts
from app.main import app


client = TestClient(app)


def context(**updates):
    value = {
        "win_type": "ron", "is_dealer": False, "round_wind": "E", "seat_wind": "S",
        "riichi": False, "ippatsu": False, "haitei": False, "houtei": False,
        "rinshan": False, "chankan": False,
    }
    value.update(updates)
    return value


def open_tanyao_payload():
    return {
        "hand": {
            "closed_tiles": ["2m", "3m", "4m", "3p", "4p", "5p", "6s", "7s", "8s", "2p", "2p"],
            "melds": [{"type": "chi", "tiles": ["2s", "3s", "4s"], "open": True}],
            "win_tile": "4m",
        },
        "context": context(), "rules": {},
    }


def score_result(payload):
    response = client.post("/api/v1/score", json=payload)
    assert response.status_code == 200, response.text
    return response.json()["result"]


@pytest.mark.parametrize("completed_melds", [0, 1])
def test_shanpon_pairs_count_as_head_and_incomplete_meld(completed_melds):
    tiles = ["1m"] * 3 + ["2p", "3p", "4p"] + ["5s"] * 3 + ["6p"] * 2 + ["7s"] * 2
    if completed_melds:
        tiles = tiles[3:]
    counts = tiles_to_counts(tiles)
    assert standard_shanten(counts, completed_melds) == 0
    assert {wait.tile for wait in enumerate_improving_tiles(counts, completed_melds)} == {"6p", "7s"}
    for tile in ("6p", "7s"):
        completed = tiles_to_counts([*tiles, tile])
        assert is_winning_hand(completed, completed_melds)
        assert standard_shanten(completed, completed_melds) == -1


def test_shanpon_tenpai_returns_both_wait_scores():
    response = client.post("/api/v1/tenpai/analyze", json={
        "closed_tiles": ["1m"] * 3 + ["2p", "3p", "4p"] + ["5s"] * 3 + ["6p"] * 2 + ["7s"] * 2,
        "context": context(riichi=True),
    })
    assert response.status_code == 200
    assert response.json()["shanten"] == 0
    waits = response.json()["improving_tiles"]
    assert {wait["tile"] for wait in waits} == {"6p", "7s"}
    assert all(wait["score"] is not None and wait["score_error"] is None for wait in waits)


def test_open_pinfu_shape_ron_is_thirty_fu():
    result = score_result(open_tanyao_payload())
    assert (result["han"], result["fu"], result["points"]["ron"]) == (1, 30, 1000)
    assert sum(item["fu"] for item in result["fu_breakdown"]) == 30


def test_open_pinfu_shape_tsumo_still_rounds_twenty_two_fu():
    payload = open_tanyao_payload()
    payload["context"]["win_type"] = "tsumo"
    result = score_result(payload)
    assert result["fu"] == 30
    assert {item["name"] for item in result["fu_breakdown"]} == {"副底", "ツモ", "切り上げ"}


def test_honroutou_does_not_gain_chanta():
    payload = open_tanyao_payload()
    payload["hand"] = {
        "closed_tiles": ["9m"] * 3 + ["1p"] * 3 + ["E"] * 3 + ["S"] * 2,
        "melds": [{"type": "pon", "tiles": ["1m"] * 3, "open": True}], "win_tile": "S",
    }
    result = score_result(payload)
    assert {item["name"] for item in result["yaku"]} == {"場風 東", "混老頭", "対々和", "三暗刻"}
    assert (result["han"], result["points"]["ron"]) == (7, 12000)


def test_ura_dora_requires_riichi_and_aka_dora_obeys_rules():
    payload = open_tanyao_payload()
    payload["context"].update(ura_dora_indicators=["1p"], aka_dora_count=1)
    payload["rules"]["aka_ari"] = False
    result = score_result(payload)
    assert result["dora"] == {"dora": 0, "aka_dora": 0, "ura_dora": 0}
    assert result["han"] == 1


@pytest.mark.parametrize("riichi_flags", [{"riichi": True}, {"double_riichi": True}])
def test_ura_dora_counts_for_either_riichi(riichi_flags):
    payload = {
        "hand": {"closed_tiles": ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "2p", "2p"], "win_tile": "2p"},
        "context": context(**riichi_flags, ura_dora_indicators=["1p"]), "rules": {},
    }
    assert score_result(payload)["dora"]["ura_dora"] == 2


@pytest.mark.parametrize("enabled,points,label", [(True, 32000, "数え役満"), (False, 24000, "三倍満")])
def test_kazoe_yakuman_disabled_caps_at_sanbaiman(enabled, points, label):
    payload = {
        "hand": {"closed_tiles": [f"{number}m" for number in "11223344556688"], "win_tile": "8m"},
        "context": context(riichi=True, ippatsu=True, dora_indicators=["1m"]),
        "rules": {"kazoe_yakuman_ari": enabled},
    }
    result = score_result(payload)
    assert (result["han"], result["points"]["ron"], result["point_label"]) == (13, points, label)


def test_kazoe_limit_does_not_reduce_natural_yakuman():
    payload = {
        "hand": {"closed_tiles": ["1m", "1m", "9m", "1p", "9p", "1s", "9s", "E", "S", "W", "N", "P", "F", "C"], "win_tile": "C"},
        "context": context(), "rules": {"kazoe_yakuman_ari": False},
    }
    result = score_result(payload)
    assert result["point_label"] == "役満"
    assert result["points"]["ron"] == 32000


@pytest.mark.parametrize("meld", [
    {"type": "chi", "tiles": ["2s", "4s", "6s"], "open": True},
    {"type": "chi", "tiles": ["2s", "3p", "4s"], "open": True},
    {"type": "chi", "tiles": ["E", "S", "W"], "open": True},
    {"type": "chi", "tiles": ["2s", "2s", "3s"], "open": True},
    {"type": "chi", "tiles": ["2s", "3s", "4s"], "open": False},
    {"type": "pon", "tiles": ["1s"] * 3, "open": False},
    {"type": "kan", "tiles": ["1s"] * 4, "open": False},
    {"type": "kakan", "tiles": ["1s"] * 4, "open": False},
    {"type": "ankan", "tiles": ["1s"] * 4, "open": True},
])
def test_score_and_analysis_reject_invalid_declared_meld(meld):
    payload = open_tanyao_payload()
    payload["hand"]["melds"] = [meld]
    score = client.post("/api/v1/score", json=payload)
    assert score.status_code == 422
    for endpoint, tiles in [
        ("tenpai", payload["hand"]["closed_tiles"][:-1]),
        ("discards", payload["hand"]["closed_tiles"]),
    ]:
        analysis = client.post(f"/api/v1/{endpoint}/analyze", json={
            "closed_tiles": tiles, "melds": [meld], "include_score_predictions": False,
        })
        assert analysis.status_code == 422
        assert analysis.json()["detail"] == score.json()["detail"]


@pytest.mark.parametrize("win_tile", ["9m", "2s"])
def test_win_tile_must_belong_to_concealed_hand(win_tile):
    payload = open_tanyao_payload()
    payload["hand"]["win_tile"] = win_tile
    response = client.post("/api/v1/score", json=payload)
    assert response.status_code == 422
    assert "win_tile must be present in closed_tiles" in response.text


def test_chi_can_be_unsorted_and_contain_red_five():
    payload = open_tanyao_payload()
    payload["hand"]["melds"][0]["tiles"] = ["5sr", "3s", "4s"]
    assert score_result(payload)["han"] == 1


@pytest.mark.parametrize("updates", [
    {"riichi": True}, {"double_riichi": True},
    {"riichi": True, "double_riichi": True}, {"ippatsu": True},
    {"haitei": True}, {"rinshan": True},
    {"win_type": "tsumo", "houtei": True}, {"win_type": "tsumo", "chankan": True},
    {"tenhou": True}, {"win_type": "tsumo", "tenhou": True},
    {"win_type": "tsumo", "seat_wind": "E", "chiihou": True},
    {"chiihou": True, "tenhou": True},
    {"dora_indicators": ["10m"]}, {"ura_dora_indicators": ["10m"]},
])
@pytest.mark.parametrize("predict", [True, False])
def test_analysis_validates_same_context_as_score(updates, predict):
    payload = open_tanyao_payload()
    payload["context"].update(updates)
    score = client.post("/api/v1/score", json=payload)
    assert score.status_code == 422
    for endpoint, tiles in [
        ("tenpai", payload["hand"]["closed_tiles"][:-1]),
        ("discards", payload["hand"]["closed_tiles"]),
    ]:
        analysis = client.post(f"/api/v1/{endpoint}/analyze", json={
            "closed_tiles": tiles, "melds": payload["hand"]["melds"],
            "context": payload["context"], "include_score_predictions": predict,
        })
        assert analysis.status_code == 422
        assert analysis.json()["detail"] == score.json()["detail"]


def test_exhausted_wait_does_not_score_a_fifth_tile():
    response = client.post("/api/v1/tenpai/analyze", json={
        "closed_tiles": ["1m"] * 3 + ["3s", "4s", "5s", "6s", "7s", "8s", "2p"],
        "melds": [{"type": "pon", "tiles": ["2p"] * 3, "open": True}],
        "context": context(houtei=True),
    })
    assert response.status_code == 200
    wait = next(wait for wait in response.json()["improving_tiles"] if wait["tile"] == "2p")
    assert wait["remaining"] == 0
    assert wait["score"] is None
    assert "five" in wait["score_error"].lower() or "5+" in wait["score_error"] or "four times" in wait["score_error"]
