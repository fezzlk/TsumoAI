from app.hand_extraction import (
    _fallback_result,
    _merge_slot_estimates,
    _normalize_candidates,
    _slot_options,
    hand_shape_from_estimate_with_warnings,
)


def _slots_from_tiles(tiles: list[str]) -> list[dict]:
    return [
        {
            "index": idx,
            "top": tile,
            "candidates": [{"tile": tile, "confidence": 0.9}],
            "ambiguous": False,
        }
        for idx, tile in enumerate(tiles)
    ]


def test_hand_shape_from_estimate_returns_top_when_already_winning():
    tiles = ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "2p", "2p"]
    hand, warnings = hand_shape_from_estimate_with_warnings({"slots": _slots_from_tiles(tiles)})
    assert hand.closed_tiles == tiles
    assert hand.win_tile == "2p"
    assert warnings == []


def test_hand_shape_from_estimate_uses_candidates_to_make_winning_shape():
    top_tiles = ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "5mr", "5pr"]
    slots = _slots_from_tiles(top_tiles)
    slots[12]["candidates"].append({"tile": "2p", "confidence": 0.8})
    slots[13]["candidates"].append({"tile": "2p", "confidence": 0.8})
    slots[12]["ambiguous"] = True
    slots[13]["ambiguous"] = True

    hand, warnings = hand_shape_from_estimate_with_warnings({"slots": slots})
    assert hand.closed_tiles[-2:] == ["2p", "2p"]
    assert any("adjusted from top-1" in warning for warning in warnings)


def test_normalize_candidates_accepts_slots_as_stringified_json_objects():
    raw_slots = [
        '{"index":0,"top":"1m","candidates":[{"tile":"1m","confidence":0.9}],"ambiguous":false}',
        '{"index":1,"top":"2m","candidates":["2m"],"ambiguous":true}',
    ]
    slots = _normalize_candidates(raw_slots)
    assert slots[0]["top"] == "1m"
    assert slots[1]["top"] == "2m"
    assert slots[1]["candidates"][0]["tile"] == "2m"


def test_normalize_candidates_accepts_slots_dict():
    raw_slots = {
        "0": {"index": 0, "top": "1m", "candidates": [{"tile": "1m", "confidence": 0.9}], "ambiguous": False},
        "1": {"index": 1, "top": "2m", "candidates": [{"tile": "2m", "confidence": 0.8}], "ambiguous": True},
    }
    slots = _normalize_candidates(raw_slots)
    assert len(slots) == 2
    assert slots[0]["index"] == 0
    assert slots[1]["index"] == 1


def test_merge_slot_estimates_prefers_consensus_tile():
    slots_a = [
        {"index": 0, "top": "4s", "candidates": [{"tile": "4s", "confidence": 0.9}], "ambiguous": False},
        {"index": 1, "top": "5s", "candidates": [{"tile": "5s", "confidence": 0.9}], "ambiguous": False},
    ]
    slots_b = [
        {"index": 0, "top": "4s", "candidates": [{"tile": "4s", "confidence": 0.8}], "ambiguous": True},
        {"index": 1, "top": "5s", "candidates": [{"tile": "5s", "confidence": 0.8}], "ambiguous": False},
    ]
    slots_c = [
        {"index": 0, "top": "1p", "candidates": [{"tile": "1p", "confidence": 0.9}], "ambiguous": False},
        {"index": 1, "top": "2p", "candidates": [{"tile": "2p", "confidence": 0.9}], "ambiguous": False},
    ]
    merged = _merge_slot_estimates([(slots_a, 1.0), (slots_b, 0.95), (slots_c, 0.7)])
    assert merged[0]["top"] == "4s"
    assert merged[1]["top"] == "5s"
    assert merged[0]["ambiguous"] is True


def test_normalize_candidates_uses_candidate_when_top_is_invalid():
    raw_slots = [
        {"index": 0, "top": "", "candidates": [{"tile": "1m", "confidence": 0.8}], "ambiguous": True},
        {"index": 1, "top": "2m", "candidates": [], "ambiguous": False},
    ]
    slots = _normalize_candidates(raw_slots)
    assert slots[0]["top"] == "1m"
    assert slots[1]["top"] == "2m"


def test_fallback_result_can_omit_missing_api_key_warning():
    result = _fallback_result(extra_warnings=["x"], include_missing_api_key_warning=False)
    assert "OPENAI_API_KEY is not set; fallback result is used." not in result["warnings"]
    assert "x" in result["warnings"]


def test_slot_options_allows_candidate_to_beat_low_confidence_top():
    slot = {
        "index": 0,
        "top": "1p",
        "top_confidence": 0.1,
        "candidates": [
            {"tile": "1p", "confidence": 0.1},
            {"tile": "4s", "confidence": 0.9},
        ],
        "ambiguous": True,
    }
    ranked = sorted(_slot_options(slot), key=lambda x: x["confidence"], reverse=True)
    assert ranked[0]["tile"] == "4s"
