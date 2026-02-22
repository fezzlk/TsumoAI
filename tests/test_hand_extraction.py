from app.hand_extraction import hand_shape_from_estimate_with_warnings


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
