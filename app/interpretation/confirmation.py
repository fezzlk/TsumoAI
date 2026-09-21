"""Build confirmed mahjong state from explicit V1 user confirmations."""

from __future__ import annotations

from collections import Counter

from app.domain.melds import validate_meld
from app.domain.tiles import is_tile_code, normalize_tile
from app.interpretation.models import (
    ConfirmationV1,
    ConfirmedHandMeldV1,
    ConfirmedHandStateV1,
    ConfirmedHandV1,
    ObservationV1,
    Operation,
)


def assemble_confirmed_hand_state(
    observation_document: ObservationV1,
    confirmation: ConfirmationV1,
) -> ConfirmedHandStateV1:
    """Return domain-ready facts only when every physical tile is explicitly confirmed."""
    observations = {item.observation_id: item for item in observation_document.observations}
    confirmed_tiles = {item.observation_id: item.tile for item in confirmation.confirmed_tiles}

    unknown_confirmations = sorted(set(confirmed_tiles) - set(observations))
    if unknown_confirmations:
        raise ValueError(f"confirmed tiles reference unknown observations: {unknown_confirmations}")
    missing_confirmations = sorted(set(observations) - set(confirmed_tiles))
    if missing_confirmations:
        raise ValueError(f"all observations must be explicitly confirmed: {missing_confirmations}")
    for tile in confirmed_tiles.values():
        if not is_tile_code(tile):
            raise ValueError(f"invalid confirmed tile code: {tile}")

    meld_ids: set[str] = set()
    melds: list[ConfirmedHandMeldV1] = []
    for meld in confirmation.confirmed_melds:
        unknown = sorted(set(meld.observation_ids) - set(observations))
        if unknown:
            raise ValueError(f"confirmed meld references unknown observations: {unknown}")
        overlap = meld_ids.intersection(meld.observation_ids)
        if overlap:
            raise ValueError(f"observations belong to multiple confirmed melds: {sorted(overlap)}")
        tiles = [confirmed_tiles[item] for item in meld.observation_ids]
        _validate_meld(meld.type.value, tiles, meld.open)
        meld_ids.update(meld.observation_ids)
        melds.append(
            ConfirmedHandMeldV1(
                type=meld.type,
                tiles=tiles,
                open=meld.open,
                source_observation_ids=meld.observation_ids,
            )
        )

    ordered_closed = sorted(
        (item for item in observation_document.observations if item.observation_id not in meld_ids),
        key=lambda item: item.index,
    )
    closed_ids = [item.observation_id for item in ordered_closed]
    closed_tiles = [confirmed_tiles[item] for item in closed_ids]

    win_id = confirmation.confirmed_winning_tile_id
    if confirmation.operation == Operation.score:
        if win_id is None:
            raise ValueError("score requires an explicitly confirmed winning tile")
        if win_id not in observations:
            raise ValueError("confirmed winning tile references an unknown observation")
        if win_id in meld_ids:
            raise ValueError("winning tile cannot be inside a confirmed meld")
        win_tile = confirmed_tiles[win_id]
    else:
        if win_id is not None:
            raise ValueError("winning tile must be null unless operation is score")
        win_tile = None

    all_tiles = [*closed_tiles, *(tile for meld in melds for tile in meld.tiles)]
    counts = Counter(normalize_tile(tile) for tile in all_tiles)
    duplicates = sorted(tile for tile, count in counts.items() if count > 4)
    if duplicates:
        raise ValueError(f"normalized tile appears more than four times: {duplicates}")

    kans = sum(1 for meld in melds if meld.type.value in {"kan", "ankan", "kakan"})
    expected = (
        13 + kans
        if confirmation.operation in {Operation.tenpai, Operation.call_analysis}
        else 14 + kans
    )
    if len(all_tiles) != expected:
        raise ValueError(
            f"{confirmation.operation.value} requires {expected} physical tiles with {kans} kan(s), "
            f"got {len(all_tiles)}"
        )

    return ConfirmedHandStateV1(
        operation=confirmation.operation,
        hand=ConfirmedHandV1(
            closed_tiles=closed_tiles,
            closed_tile_observation_ids=closed_ids,
            melds=melds,
            win_tile=win_tile,
            win_tile_observation_id=win_id,
        ),
    )


def _validate_meld(kind: str, tiles: list[str], is_open: bool) -> None:
    expected = 3 if kind in {"chi", "pon"} else 4
    if len(tiles) != expected:
        raise ValueError(f"{kind} must contain exactly {expected} observations")

    validate_meld(kind, tiles, is_open)
