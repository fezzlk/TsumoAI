from __future__ import annotations

from app.domain.analysis import analyze_discards, enumerate_improving_tiles
from app.domain.shanten import calculate_shanten
from app.domain.tiles import index_to_tile, tile_to_index, tiles_to_counts
from app.hand_scoring import score_hand_shape
from app.hand_validation import validate_hand_context, validate_hand_tiles_and_melds, validate_winning_hand
from app.schemas import (
    AnalysisRequestBase,
    CallAnalysisRequest,
    CallAnalysisResponse,
    CallAnalysisResult,
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
        validate_winning_hand(hand, request.context)
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
    validate_hand_tiles_and_melds(request.closed_tiles, request.melds)
    if request.context is not None:
        validate_hand_context(request.melds, request.context)
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


def analyze_call_options(request: CallAnalysisRequest) -> CallAnalysisResponse:
    completed_melds = len(request.melds)
    expected = 13 - completed_melds * 3
    closed_counts, visible_counts = _validated_counts(request, expected, "call analysis")
    current_shanten = calculate_shanten(closed_counts, completed_melds)
    calls: list[CallAnalysisResult] = []

    def recommendation(shanten: int) -> str:
        if shanten < current_shanten:
            return "improves"
        if shanten == current_shanten:
            return "keeps"
        return "worsens"

    def add_open_call(call_tile_index: int, call_type: str, consumed_indices: list[int]) -> None:
        reduced = list(closed_counts)
        for index in consumed_indices:
            reduced[index] -= 1
        visible = list(visible_counts)
        visible[call_tile_index] += 1
        discard_options = analyze_discards(tuple(reduced), completed_melds + 1, tuple(visible))
        best_shanten = discard_options[0].shanten
        best_discards = [item for item in discard_options if item.shanten == best_shanten]
        calls.append(
            CallAnalysisResult(
                call_tile=index_to_tile(call_tile_index),
                call_type=call_type,
                consumed_tiles=[index_to_tile(index) for index in consumed_indices],
                shanten_after_call=best_shanten,
                recommendation=recommendation(best_shanten),
                discards=[
                    DiscardAnalysisResult(
                        discard=item.discard,
                        shanten=item.shanten,
                        improving_tiles=_wait_results(
                            request,
                            [],
                            item.waits,
                            predict_scores=False,
                        ),
                        total_remaining=sum(wait.remaining for wait in item.waits),
                    )
                    for item in best_discards
                ],
            )
        )

    for call_index in range(34):
        if visible_counts[call_index] >= 4:
            continue
        if closed_counts[call_index] >= 2:
            add_open_call(call_index, "pon", [call_index, call_index])

        if closed_counts[call_index] >= 3:
            reduced = list(closed_counts)
            reduced[call_index] -= 3
            visible = list(visible_counts)
            visible[call_index] += 1
            replacement_tiles = enumerate_improving_tiles(
                tuple(reduced), completed_melds + 1, tuple(visible)
            )
            replacement_shanten = calculate_shanten(tuple(reduced), completed_melds + 1)
            calls.append(
                CallAnalysisResult(
                    call_tile=index_to_tile(call_index),
                    call_type="kan",
                    consumed_tiles=[index_to_tile(call_index)] * 3,
                    shanten_after_call=replacement_shanten,
                    recommendation=recommendation(replacement_shanten),
                    replacement_tiles=_wait_results(
                        request,
                        [],
                        replacement_tiles,
                        predict_scores=False,
                    ),
                )
            )

        if call_index >= 27:
            continue
        rank = call_index % 9
        suit_start = call_index - rank
        for sequence_start in range(max(0, rank - 2), min(rank, 6) + 1):
            sequence = [suit_start + sequence_start + offset for offset in range(3)]
            consumed = [index for index in sequence if index != call_index]
            if all(closed_counts[index] > 0 for index in consumed):
                add_open_call(call_index, "chi", consumed)

    calls.sort(
        key=lambda item: (
            item.shanten_after_call,
            {"pon": 0, "chi": 1, "kan": 2}[item.call_type],
            item.call_tile,
            item.consumed_tiles,
        )
    )
    return CallAnalysisResponse(current_shanten=current_shanten, calls=calls)
