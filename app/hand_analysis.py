from __future__ import annotations

from app.domain.analysis import analyze_discards, enumerate_improving_tiles
from app.domain.shanten import calculate_shanten
from app.domain.tiles import index_to_tile, tile_to_index, tiles_to_counts
from app.hand_scoring import score_hand_shape
from app.schemas import (
    AnalysisRequestBase,
    DiscardAnalysisRequest,
    DiscardAnalysisResponse,
    DiscardAnalysisResult,
    HandInput,
    TenpaiAnalysisRequest,
    TenpaiAnalysisResponse,
    WaitAnalysis,
)


def _all_visible_counts(request: AnalysisRequestBase) -> tuple[int, ...]:
    tiles = list(request.closed_tiles)
    for meld in request.melds:
        tiles.extend(meld.tiles)
    return tiles_to_counts(tiles)


def _score_wait(request: AnalysisRequestBase, base_tiles: list[str], tile: str):
    if not request.include_score_predictions or request.context is None:
        return None, None
    hand = HandInput(closed_tiles=[*base_tiles, tile], melds=request.melds, win_tile=tile)
    try:
        return score_hand_shape(hand, request.context, request.rules), None
    except ValueError as exc:
        return None, str(exc)


def _wait_results(
    request: AnalysisRequestBase, base_tiles: list[str], waits, *, predict_scores: bool
) -> list[WaitAnalysis]:
    results = []
    for wait in waits:
        score, error = _score_wait(request, base_tiles, wait.tile) if predict_scores else (None, None)
        results.append(WaitAnalysis(tile=wait.tile, remaining=wait.remaining, score=score, score_error=error))
    return results


def _validated_counts(request: AnalysisRequestBase, expected: int, operation: str):
    closed_counts = tiles_to_counts(request.closed_tiles)
    visible_counts = _all_visible_counts(request)
    if len(request.closed_tiles) != expected:
        raise ValueError(f"closed_tiles must contain {expected} tiles for {operation}")
    if any(value > 4 for value in visible_counts):
        index = next(index for index, value in enumerate(visible_counts) if value > 4)
        raise ValueError(f"tile appears more than four times: {index_to_tile(index)}")
    return closed_counts, visible_counts


def analyze_tenpai(request: TenpaiAnalysisRequest) -> TenpaiAnalysisResponse:
    completed_melds = len(request.melds)
    expected = 13 - completed_melds * 3
    closed_counts, visible_counts = _validated_counts(request, expected, "tenpai analysis")
    shanten = calculate_shanten(closed_counts, completed_melds)
    waits = enumerate_improving_tiles(closed_counts, completed_melds, visible_counts)
    return TenpaiAnalysisResponse(
        shanten=shanten,
        improving_tiles=_wait_results(request, request.closed_tiles, waits, predict_scores=shanten == 0),
    )


def analyze_discard_options(request: DiscardAnalysisRequest) -> DiscardAnalysisResponse:
    completed_melds = len(request.melds)
    expected = 14 - completed_melds * 3
    closed_counts, visible_counts = _validated_counts(request, expected, "discard analysis")
    discard_results = []
    for result in analyze_discards(closed_counts, completed_melds, visible_counts):
        reduced = list(request.closed_tiles)
        removed_index = next(
            index for index, tile in enumerate(reduced) if tile_to_index(tile) == tile_to_index(result.discard)
        )
        reduced.pop(removed_index)
        waits = _wait_results(request, reduced, result.waits, predict_scores=result.shanten == 0)
        discard_results.append(
            DiscardAnalysisResult(
                discard=result.discard,
                shanten=result.shanten,
                improving_tiles=waits,
                total_remaining=sum(wait.remaining for wait in waits),
            )
        )
    return DiscardAnalysisResponse(
        shanten=min(result.shanten for result in discard_results),
        discards=discard_results,
    )
