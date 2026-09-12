from __future__ import annotations

from app.recognition_postprocess import DEFAULT_POLICY, _transition_prior, merge_slot_estimates, pick_winning_tiles


def _slot(tile: str, confidence: float = 0.9) -> dict:
    return {"index": 0, "top": tile, "candidates": [{"tile": tile, "confidence": confidence}], "ambiguous": False}


def test_merge_slot_estimates_skips_pass_shorter_than_max_length():
    long_pass = [_slot("1m"), _slot("2m")]
    short_pass = [_slot("1m")]
    merged = merge_slot_estimates([(long_pass, 1.0), (short_pass, 1.0)])
    assert [slot["top"] for slot in merged] == ["1m", "2m"]


def test_transition_prior_uses_template_similarity_fallback(monkeypatch):
    """Same-suit-far and different-suit pairs fall through to the template-similarity prior."""
    monkeypatch.setattr("app.recognition_postprocess.tile_similarity", lambda a, b: 0.95)
    assert _transition_prior("1m", "9m", DEFAULT_POLICY) == 0.02  # same suit, far apart (>2)


def test_transition_prior_returns_zero_below_similarity_threshold(monkeypatch):
    monkeypatch.setattr("app.recognition_postprocess.tile_similarity", lambda a, b: 0.5)
    assert _transition_prior("1m", "9m", DEFAULT_POLICY) == 0.0


def test_pick_winning_tiles_returns_none_when_a_tile_would_exceed_four_copies():
    """A 5th required copy of the same tile is physically impossible."""
    slots = [_slot("1m") for _ in range(5)]
    assert pick_winning_tiles(slots) is None
