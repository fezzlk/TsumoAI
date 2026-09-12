from __future__ import annotations

import pytest

from app.domain.analysis import analyze_discards, enumerate_improving_tiles
from app.domain.decomposition import is_thirteen_orphans, is_winning_hand, standard_decompositions
from app.domain.shanten import calculate_shanten
from app.domain.tiles import index_to_tile, tile_to_index, tiles_to_counts, validate_counts


def counts(tiles: list[str]) -> tuple[int, ...]:
    return tiles_to_counts(tiles)


def test_tile_index_round_trip_and_red_normalization():
    assert tile_to_index("5mr") == tile_to_index("5m")
    assert [index_to_tile(index) for index in range(34)][-7:] == ["E", "S", "W", "N", "P", "F", "C"]


def test_standard_winning_hand_decomposes():
    hand = counts(["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "2p", "2p"])
    assert is_winning_hand(hand)
    assert standard_decompositions(hand)
    assert calculate_shanten(hand) == -1


def test_tenpai_waits_include_all_valid_winning_tiles():
    hand = counts(["1m", "2m", "3m", "4m", "5m", "6m", "7m", "8m", "9m", "2p", "3p", "4p", "5p"])
    assert calculate_shanten(hand) == 0
    waits = {wait.tile for wait in enumerate_improving_tiles(hand)}
    assert waits == {"2p", "5p"}


def test_thirteen_orphans_thirteen_sided_wait():
    hand = counts(["1m", "9m", "1p", "9p", "1s", "9s", "E", "S", "W", "N", "P", "F", "C"])
    assert calculate_shanten(hand) == 0
    assert {wait.tile for wait in enumerate_improving_tiles(hand)} == {
        "1m", "9m", "1p", "9p", "1s", "9s", "E", "S", "W", "N", "P", "F", "C"
    }


def test_discard_analysis_prefers_tenpai_and_counts_remaining_tiles():
    hand = counts(["1m", "2m", "3m", "4m", "5m", "6m", "7m", "8m", "9m", "2p", "3p", "4p", "5p", "C"])
    results = analyze_discards(hand)
    assert results[0].shanten == 0
    discard_c = next(result for result in results if result.discard == "C")
    assert {wait.tile for wait in discard_c.waits} == {"2p", "5p"}
    assert sum(wait.remaining for wait in discard_c.waits) == 6


def test_open_hand_uses_completed_meld_count():
    concealed = counts(["4m", "5m", "6m", "7p", "8p", "9p", "E", "E", "E", "2s"])
    assert calculate_shanten(concealed, completed_melds=1) == 0
    assert {wait.tile for wait in enumerate_improving_tiles(concealed, completed_melds=1)} == {"2s"}


def test_enumerate_improving_tiles_excludes_tile_already_held_four_times():
    """A tile already at 4 copies cannot be drawn again; must be skipped, not crash."""
    hand = counts(["9m", "9m", "9m", "9m", "1p", "2p", "3p", "4p", "5p", "6p", "7p", "8p", "1s"])
    waits = enumerate_improving_tiles(hand)
    assert "9m" not in {wait.tile for wait in waits}


def test_standard_decompositions_returns_empty_for_mismatched_tile_count():
    """A tile count that doesn't total completed_melds*3+2 cannot decompose."""
    hand = counts(["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "2p"])
    assert standard_decompositions(hand) == ()


def test_is_thirteen_orphans_requires_zero_completed_melds():
    """Kokushi musou can never include a called meld."""
    hand = counts(["1m", "1m", "9m", "1p", "9p", "1s", "9s", "E", "S", "W", "N", "P", "F", "C"])
    assert is_thirteen_orphans(hand, 0) is True
    assert is_thirteen_orphans(hand, 1) is False


def test_tile_to_index_rejects_invalid_tile_code():
    with pytest.raises(ValueError):
        tile_to_index("10m")


def test_index_to_tile_rejects_out_of_range_index():
    with pytest.raises(ValueError):
        index_to_tile(34)


def test_validate_counts_rejects_wrong_length():
    with pytest.raises(ValueError):
        validate_counts((0,) * 33)


def test_validate_counts_rejects_out_of_range_value():
    with pytest.raises(ValueError):
        validate_counts((5,) + (0,) * 33)
