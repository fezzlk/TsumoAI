"""HTTP adapters for shared hand validation."""

from fastapi import HTTPException

from app.domain.decomposition import is_winning_hand
from app.domain.tiles import tiles_to_counts
from app.hand_validation import validate_tile_code, validate_winning_hand
from app.schemas import HandInput, ScoreRequest


def validate_tile(tile: str) -> None:
    try:
        validate_tile_code(tile)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


def is_valid_winning_shape_hand(hand: HandInput) -> bool:
    return is_winning_hand(tiles_to_counts(hand.closed_tiles), len(hand.melds))


def validate_score_request(req: ScoreRequest) -> None:
    req.context.is_dealer = req.context.seat_wind == "E"
    try:
        validate_winning_hand(req.hand, req.context)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
