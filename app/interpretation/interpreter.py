from __future__ import annotations

from statistics import median

from app.domain.tiles import is_tile_code, normalize_tile
from app.interpretation.models import (
    FactStatus,
    InterpretationRequest,
    InterpretationResponse,
    RecognitionInterpretationRequest,
    MeldInterpretation,
    TileObservation,
    WinningTileInterpretation,
)
from app.interpretation.policy import (
    MAX_UNCONFIRMED_CONFIDENCE,
    MAX_VISUAL_CONFIDENCE,
    MELD_MIN_TILE_CONFIDENCE,
    SIDEWAYS_MAX_DEGREES,
    SIDEWAYS_MIN_DEGREES,
    WINNING_TILE_MIN_CONFIDENCE,
    WINNING_TILE_MIN_GAP_RATIO,
)


def request_from_hand_estimate(
    hand_estimate: dict, confirmation: RecognitionInterpretationRequest
) -> InterpretationRequest:
    observations = []
    for position, slot in enumerate(hand_estimate.get("slots", [])):
        candidates = slot.get("candidates") or [
            {"tile": slot.get("top"), "confidence": slot.get("top_confidence", 0.0)}
        ]
        observations.append(
            TileObservation.model_validate(
                {
                    "observation_id": slot.get("observation_id") or f"tile-{position}",
                    "index": slot.get("index", position),
                    "candidates": candidates,
                    "bbox": slot.get("bbox"),
                    "rotation_degrees": slot.get("rotation_degrees"),
                    "visual_group_id": slot.get("visual_group_id"),
                }
            )
        )
    return InterpretationRequest(
        observations=observations,
        confirmed_winning_tile_id=confirmation.confirmed_winning_tile_id,
        confirmed_melds=confirmation.confirmed_melds,
    )


def interpret_observations(request: InterpretationRequest) -> InterpretationResponse:
    """Infer candidates without turning uncertain visual evidence into facts."""
    by_id = {observation.observation_id: observation for observation in request.observations}
    if len(by_id) != len(request.observations):
        raise ValueError("observation_id must be unique")
    if any(not observation.candidates for observation in request.observations):
        raise ValueError("every observation must have at least one tile candidate")
    for observation in request.observations:
        for candidate in observation.candidates:
            if not is_tile_code(candidate.tile):
                raise ValueError(f"invalid tile candidate: {candidate.tile}")
        if observation.bbox and (
            observation.bbox.right <= observation.bbox.left
            or observation.bbox.bottom <= observation.bbox.top
        ):
            raise ValueError(f"invalid bounding box: {observation.observation_id}")

    melds = _confirmed_melds(request, by_id)
    confirmed_ids = {item for meld in melds for item in meld.observation_ids}
    melds.extend(_infer_visual_groups(request.observations, confirmed_ids))
    excluded_from_winning = {
        item
        for meld in melds
        if meld.status in {FactStatus.confirmed, FactStatus.inferred}
        for item in meld.observation_ids
    }
    winning_tile = _interpret_winning_tile(request, by_id, excluded_from_winning)
    needs_confirmation = winning_tile.status != FactStatus.confirmed or any(
        meld.status != FactStatus.confirmed for meld in melds
    )
    return InterpretationResponse(
        melds=melds,
        winning_tile=winning_tile,
        requires_user_confirmation=needs_confirmation,
    )


def _top_tile(observation: TileObservation) -> str:
    return observation.candidates[0].tile


def _top_confidence(observation: TileObservation) -> float:
    return observation.candidates[0].confidence


def _confirmed_melds(request: InterpretationRequest, by_id: dict[str, TileObservation]) -> list[MeldInterpretation]:
    results = []
    used: set[str] = set()
    for meld in request.confirmed_melds:
        if len(set(meld.observation_ids)) != len(meld.observation_ids):
            raise ValueError("a confirmed meld cannot contain the same observation twice")
        missing = [item for item in meld.observation_ids if item not in by_id]
        if missing:
            raise ValueError(f"confirmed meld references unknown observations: {missing}")
        overlap = used.intersection(meld.observation_ids)
        if overlap:
            raise ValueError(f"observations belong to multiple confirmed melds: {sorted(overlap)}")
        tiles = [_top_tile(by_id[item]) for item in meld.observation_ids]
        if not _valid_meld(meld.type.value, tiles):
            raise ValueError(f"confirmed meld tiles do not form {meld.type.value}: {tiles}")
        used.update(meld.observation_ids)
        results.append(
            MeldInterpretation(
                observation_ids=meld.observation_ids,
                type=meld.type,
                tiles=tiles,
                open=meld.open,
                status=FactStatus.confirmed,
                confidence=1.0,
                evidence=["user_confirmed"],
            )
        )
    return results


def _infer_visual_groups(observations: list[TileObservation], excluded: set[str]) -> list[MeldInterpretation]:
    groups: dict[str, list[TileObservation]] = {}
    for observation in observations:
        if observation.visual_group_id and observation.observation_id not in excluded:
            groups.setdefault(observation.visual_group_id, []).append(observation)

    results = []
    for group_id, group in groups.items():
        group.sort(key=lambda item: item.index)
        tiles = [_top_tile(item) for item in group]
        meld_type = _meld_type(tiles)
        if meld_type is None:
            continue
        rotations = [abs(item.rotation_degrees or 0.0) % 180 for item in group]
        sideways = any(SIDEWAYS_MIN_DEGREES <= rotation <= SIDEWAYS_MAX_DEGREES for rotation in rotations)
        confidence = min(_top_confidence(item) for item in group)
        status = FactStatus.inferred if sideways and confidence >= MELD_MIN_TILE_CONFIDENCE else FactStatus.unknown
        evidence = ["vision_group", "valid_meld_tiles"]
        if sideways:
            evidence.append("sideways_tile")
        else:
            evidence.append("open_state_not_visible")
        results.append(
            MeldInterpretation(
                observation_ids=[item.observation_id for item in group],
                type=meld_type,
                tiles=tiles,
                open=True if sideways else None,
                status=status,
                confidence=(
                    confidence if status == FactStatus.inferred else min(confidence, MAX_UNCONFIRMED_CONFIDENCE)
                ),
                evidence=[f"visual_group:{group_id}", *evidence],
            )
        )
    return results


def _interpret_winning_tile(
    request: InterpretationRequest, by_id: dict[str, TileObservation], meld_ids: set[str]
) -> WinningTileInterpretation:
    if request.confirmed_winning_tile_id is not None:
        observation = by_id.get(request.confirmed_winning_tile_id)
        if observation is None:
            raise ValueError("confirmed winning tile references an unknown observation")
        if observation.observation_id in meld_ids:
            raise ValueError("winning tile cannot be inside a confirmed meld")
        return WinningTileInterpretation(
            observation_id=observation.observation_id,
            tile=_top_tile(observation),
            status=FactStatus.confirmed,
            confidence=1.0,
            evidence=["user_confirmed"],
        )

    concealed = [item for item in request.observations if item.observation_id not in meld_ids]
    with_boxes = [item for item in concealed if item.bbox is not None]
    if len(with_boxes) < 2:
        return WinningTileInterpretation(
            status=FactStatus.unknown,
            confidence=0.0,
            evidence=["insufficient_geometry"],
        )

    horizontal_span = max(item.bbox.right for item in with_boxes) - min(item.bbox.left for item in with_boxes)
    vertical_span = max(item.bbox.bottom for item in with_boxes) - min(item.bbox.top for item in with_boxes)
    horizontal = horizontal_span >= vertical_span
    ordered = sorted(with_boxes, key=lambda item: _axis_center(item, horizontal))
    dimensions = [
        item.bbox.right - item.bbox.left if horizontal else item.bbox.bottom - item.bbox.top for item in ordered
    ]
    typical_size = median(dimensions)
    previous, candidate = ordered[-2], ordered[-1]
    gap = _axis_start(candidate, horizontal) - _axis_end(previous, horizontal)
    gap_ratio = gap / typical_size if typical_size > 0 else 0.0
    visual_confidence = min(MAX_VISUAL_CONFIDENCE, max(0.0, gap_ratio))
    tile_confidence = _top_confidence(candidate)
    if gap_ratio >= WINNING_TILE_MIN_GAP_RATIO and tile_confidence >= WINNING_TILE_MIN_CONFIDENCE:
        return WinningTileInterpretation(
            observation_id=candidate.observation_id,
            tile=_top_tile(candidate),
            status=FactStatus.inferred,
            confidence=min(visual_confidence, tile_confidence),
            evidence=["end_of_concealed_run", f"separation_ratio:{gap_ratio:.2f}"],
        )
    return WinningTileInterpretation(
        observation_id=candidate.observation_id,
        tile=_top_tile(candidate),
        status=FactStatus.unknown,
        confidence=min(MAX_UNCONFIRMED_CONFIDENCE, visual_confidence, tile_confidence),
        evidence=["rightmost_or_bottommost_candidate", f"separation_ratio:{gap_ratio:.2f}"],
    )


def _meld_type(tiles: list[str]) -> str | None:
    if len(tiles) == 3 and _valid_meld("pon", tiles):
        return "pon"
    if len(tiles) == 3 and _valid_meld("chi", tiles):
        return "chi"
    if len(tiles) == 4 and _valid_meld("kan", tiles):
        return "kan"
    return None


def _valid_meld(kind: str, tiles: list[str]) -> bool:
    normalized = [normalize_tile(tile) for tile in tiles]
    if kind in {"pon", "kan", "ankan", "kakan"}:
        expected = 3 if kind == "pon" else 4
        return len(normalized) == expected and len(set(normalized)) == 1
    if kind != "chi" or len(normalized) != 3 or any(len(tile) != 2 for tile in normalized):
        return False
    suits = {tile[1] for tile in normalized}
    numbers = sorted(int(tile[0]) for tile in normalized)
    return len(suits) == 1 and numbers[1] == numbers[0] + 1 and numbers[2] == numbers[1] + 1


def _axis_center(item: TileObservation, horizontal: bool) -> float:
    return (item.bbox.left + item.bbox.right) / 2 if horizontal else (item.bbox.top + item.bbox.bottom) / 2


def _axis_start(item: TileObservation, horizontal: bool) -> float:
    return item.bbox.left if horizontal else item.bbox.top


def _axis_end(item: TileObservation, horizontal: bool) -> float:
    return item.bbox.right if horizontal else item.bbox.bottom
