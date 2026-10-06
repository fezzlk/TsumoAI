from __future__ import annotations

from app.call_outlook import assess_call_branch, summarize_call_outlooks
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
    Meld,
    MeldType,
    TenpaiAnalysisRequest,
    TenpaiAnalysisResponse,
    TenpaiWaitAnalysis,
    WaitAnalysis,
)


_BONUS_YAKU_NAMES = {"ドラ", "赤ドラ", "裏ドラ"}


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


def _remove_tile_indices(tiles: list[str], indices: list[int]) -> list[str]:
    """Remove one physical tile for each normalized tile index.

    Red fives and ordinary fives share a normalized index. Keeping the
    original string for every tile that remains preserves red-tile scoring.
    """
    remaining = list(tiles)
    for tile_index in indices:
        position = next(
            index
            for index, tile in enumerate(remaining)
            if tile_to_index(tile) == tile_index
        )
        remaining.pop(position)
    return remaining


def _request_with_hypothetical_meld(
    request: CallAnalysisRequest,
    *,
    call_type: str,
    call_tile_index: int,
    consumed_indices: list[int],
) -> CallAnalysisRequest:
    meld_type = {
        "chi": MeldType.chi,
        "pon": MeldType.pon,
        "kan": MeldType.kan,
    }[call_type]
    remaining = list(request.closed_tiles)
    consumed_tiles = []
    for tile_index in consumed_indices:
        position = next(i for i, tile in enumerate(remaining) if tile_to_index(tile) == tile_index)
        consumed_tiles.append(remaining.pop(position))
    meld = Meld(
        type=meld_type,
        tiles=[
            *consumed_tiles,
            index_to_tile(call_tile_index),
        ],
        open=True,
    )
    context = request.context
    if context is not None:
        # Compare ordinary future ron outcomes; incidental win flags must not
        # make an otherwise yakuless call appear safe. Preserve winds/dora.
        encoded_red = sum(tile.endswith("r") for tile in request.closed_tiles)
        encoded_red += sum(tile.endswith("r") for meld in request.melds for tile in meld.tiles)
        context = context.model_copy(
            update={"win_type": "ron", "riichi": False, "double_riichi": False, "ippatsu": False,
                    "haitei": False, "houtei": False, "rinshan": False, "chankan": False,
                    "tenhou": False, "chiihou": False, "honba": 0, "kyotaku": 0,
                    "aka_dora_count": max(context.aka_dora_count, encoded_red)}
        )
    return request.model_copy(
        update={"closed_tiles": remaining, "melds": [*request.melds, meld], "context": context}
    )


def _call_wait_results(request: CallAnalysisRequest, tiles: list[str], waits, shanten: int):
    context = request.context
    if context is not None:
        removed_red = sum(tile.endswith("r") for tile in request.closed_tiles) - sum(tile.endswith("r") for tile in tiles)
        context = context.model_copy(update={"aka_dora_count": max(0, context.aka_dora_count - removed_red)})
    # Checking yaku is essential even when score details were opted out.
    scoring_request = request.model_copy(update={"include_score_predictions": True, "context": context})
    ron = _wait_results(scoring_request, tiles, waits, predict_scores=shanten == 0)
    tsumo_context = context.model_copy(update={"win_type": "tsumo"}) if context is not None else None
    tsumo_request = scoring_request.model_copy(update={"context": tsumo_context})
    tsumo = _wait_results(tsumo_request, tiles, waits, predict_scores=shanten == 0)
    return ron, tsumo


def _possible_yaku(*wait_groups: list[WaitAnalysis]) -> list[str]:
    names: set[str] = set()
    for waits in wait_groups:
        for wait in waits:
            if wait.score is None:
                continue
            names.update(
                item.name
                for item in wait.score.yaku
                if item.name not in _BONUS_YAKU_NAMES
            )
            names.update(wait.score.yakuman)
    return sorted(names)


def _without_score_details(waits: list[WaitAnalysis]) -> list[WaitAnalysis]:
    """Keep call-advice responses compact after extracting possible yaku."""
    return [
        wait.model_copy(update={"score": None, "score_error": None})
        for wait in waits
    ]


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
    scoring_requests = {}
    for win_type in ("ron", "tsumo"):
        context = request.context
        if context is not None:
            encoded_red = sum(tile.endswith("r") for tile in request.closed_tiles)
            encoded_red += sum(tile.endswith("r") for meld in request.melds for tile in meld.tiles)
            # Keep the current riichi/dora/round settings. Only remove flags
            # incompatible with the alternative way of winning.
            clear_flags = ("haitei", "rinshan", "chiihou", "tenhou") if win_type == "ron" else ("houtei", "chankan")
            context = context.model_copy(update={
                "win_type": win_type,
                "aka_dora_count": max(context.aka_dora_count, encoded_red),
                **{flag: False for flag in clear_flags},
            })
        scoring_requests[win_type] = request.model_copy(update={"context": context})
    predictions = []
    for wait in waits:
        ron, ron_error = _score_wait(scoring_requests["ron"], request.closed_tiles, wait.tile) if shanten == 0 else (None, None)
        tsumo, tsumo_error = _score_wait(scoring_requests["tsumo"], request.closed_tiles, wait.tile) if shanten == 0 else (None, None)
        selected_tsumo = request.context is not None and request.context.win_type == "tsumo"
        predictions.append(TenpaiWaitAnalysis(
            tile=wait.tile, remaining=wait.remaining,
            score=tsumo if selected_tsumo else ron,
            score_error=tsumo_error if selected_tsumo else ron_error,
            ron_score=ron, ron_score_error=ron_error,
            tsumo_score=tsumo, tsumo_score_error=tsumo_error,
        ))
    conditions = []
    if request.context is not None and request.include_score_predictions and shanten == 0:
        context = request.context
        wind_names = {"E": "東", "S": "南", "W": "西", "N": "北"}
        conditions = [
            f"場風 {wind_names[context.round_wind]}・自風 {wind_names[context.seat_wind]}（{'親' if context.seat_wind == 'E' else '子'}）",
            "ダブルリーチあり" if context.double_riichi else "リーチあり" if context.riichi else "リーチなし",
            "喰いタンあり" if request.rules.kuitan_ari else "喰いタンなし",
        ]
    return TenpaiAnalysisResponse(
        shanten=shanten,
        improving_tiles=predictions,
        score_conditions=conditions,
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
        reduced_tiles = _remove_tile_indices(request.closed_tiles, consumed_indices)
        hypothetical_request = _request_with_hypothetical_meld(
            request,
            call_type=call_type,
            call_tile_index=call_tile_index,
            consumed_indices=consumed_indices,
        )
        visible = list(visible_counts)
        visible[call_tile_index] += 1
        discard_options = analyze_discards(tuple(reduced), completed_melds + 1, tuple(visible))
        best_shanten = discard_options[0].shanten
        best_discards = [item for item in discard_options if item.shanten == best_shanten]
        discard_results: list[DiscardAnalysisResult] = []
        wait_groups: list[list[WaitAnalysis]] = []
        for item in best_discards:
            after_discard = _remove_tile_indices(
                reduced_tiles, [tile_to_index(item.discard)]
            )
            waits, tsumo_waits = _call_wait_results(
                hypothetical_request,
                after_discard,
                item.waits,
                item.shanten,
            )
            wait_groups.append(waits)
            wait_groups.append(tsumo_waits)
            discard_results.append(
                DiscardAnalysisResult(
                    discard=item.discard,
                    shanten=item.shanten,
                    improving_tiles=_without_score_details(waits),
                    total_remaining=sum(wait.remaining for wait in waits),
                    call_outlook=assess_call_branch(hypothetical_request, after_discard, item.shanten, waits, tsumo_waits),
                )
            )
        calls.append(
            CallAnalysisResult(
                call_tile=index_to_tile(call_tile_index),
                call_type=call_type,
                consumed_tiles=[index_to_tile(index) for index in consumed_indices],
                shanten_after_call=best_shanten,
                recommendation=recommendation(best_shanten),
                possible_yaku=_possible_yaku(*wait_groups),
                outlook=summarize_call_outlooks([item.call_outlook for item in discard_results]),
                discards=discard_results,
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
            reduced_tiles = _remove_tile_indices(
                request.closed_tiles, [call_index, call_index, call_index]
            )
            hypothetical_request = _request_with_hypothetical_meld(
                request,
                call_type="kan",
                call_tile_index=call_index,
                consumed_indices=[call_index, call_index, call_index],
            )
            visible = list(visible_counts)
            visible[call_index] += 1
            replacement_tiles = enumerate_improving_tiles(
                tuple(reduced), completed_melds + 1, tuple(visible)
            )
            replacement_shanten = calculate_shanten(tuple(reduced), completed_melds + 1)
            replacement_results, tsumo_results = _call_wait_results(
                hypothetical_request,
                reduced_tiles,
                replacement_tiles,
                replacement_shanten,
            )
            outlook = assess_call_branch(hypothetical_request, reduced_tiles, replacement_shanten, replacement_results, tsumo_results)
            outlook.warnings.append("カン後は補充牌と打牌で形が変わります。嶺上開花・新しい槓ドラは打点に含めていません。")
            calls.append(
                CallAnalysisResult(
                    call_tile=index_to_tile(call_index),
                    call_type="kan",
                    consumed_tiles=[index_to_tile(call_index)] * 3,
                    shanten_after_call=replacement_shanten,
                    recommendation=recommendation(replacement_shanten),
                    possible_yaku=_possible_yaku(replacement_results, tsumo_results),
                    outlook=outlook,
                    replacement_tiles=_without_score_details(replacement_results),
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
