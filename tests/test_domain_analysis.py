from __future__ import annotations

from app.domain.analysis import analyze_discards, enumerate_improving_tiles
from app.domain.decomposition import is_winning_hand, standard_decompositions
from app.domain.shanten import calculate_shanten
from app.domain.tiles import index_to_tile, tile_to_index, tiles_to_counts


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
