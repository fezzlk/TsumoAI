from fastapi import HTTPException

from app.domain.decomposition import is_winning_hand
from app.domain.tiles import is_tile_code, normalize_tile, tiles_to_counts
from app.schemas import HandInput, ScoreRequest


def validate_tile(tile: str) -> None:
    if not is_tile_code(tile):
        raise HTTPException(status_code=422, detail=f"Invalid tile code: {tile}")


def _normalize_tile(tile: str) -> str:
    return normalize_tile(tile)


def _is_valid_winning_shape(req: ScoreRequest) -> bool:
    return is_winning_hand(tiles_to_counts(req.hand.closed_tiles), len(req.hand.melds))


def is_valid_winning_shape_hand(hand: HandInput) -> bool:
    return is_winning_hand(tiles_to_counts(hand.closed_tiles), len(hand.melds))


def validate_score_request(req: ScoreRequest) -> None:
    req.context.is_dealer = req.context.seat_wind == "E"

    all_tiles = list(req.hand.closed_tiles)
    for meld in req.hand.melds:
        all_tiles.extend(meld.tiles)
    for tile in all_tiles:
        validate_tile(tile)
    validate_tile(req.hand.win_tile)
    for tile in req.context.dora_indicators:
        validate_tile(tile)
    for tile in req.context.ura_dora_indicators:
        validate_tile(tile)

    tile_counts: dict[str, int] = {}
    for tile in all_tiles:
        normalized = _normalize_tile(tile)
        tile_counts[normalized] = tile_counts.get(normalized, 0) + 1
        if tile_counts[normalized] >= 5:
            raise HTTPException(status_code=422, detail=f"Tile appears 5+ times in hand: {normalized}")

    for meld in req.hand.melds:
        if meld.type in {"chi", "pon"} and len(meld.tiles) != 3:
            raise HTTPException(status_code=422, detail=f"{meld.type} must contain exactly 3 tiles")
        if meld.type in {"kan", "ankan", "kakan"} and len(meld.tiles) != 4:
            raise HTTPException(status_code=422, detail=f"{meld.type} must contain exactly 4 tiles")
        if meld.type in {"pon", "kan", "ankan", "kakan"}:
            normalized = {_normalize_tile(t) for t in meld.tiles}
            if len(normalized) != 1:
                raise HTTPException(status_code=422, detail=f"{meld.type} tiles must all be the same tile")

    kan_melds = sum(1 for m in req.hand.melds if m.type in {"kan", "ankan", "kakan"})
    total_tiles = len(req.hand.closed_tiles) + sum(len(m.tiles) for m in req.hand.melds)
    expected_total_tiles = 14 + kan_melds
    if total_tiles != expected_total_tiles:
        raise HTTPException(
            status_code=422,
            detail=f"Total tiles must be {expected_total_tiles} at win state (14 + number of kans)",
        )

    if req.context.riichi and req.context.double_riichi:
        raise HTTPException(status_code=422, detail="riichi and double_riichi cannot both be true")
    if (req.context.riichi or req.context.double_riichi) and any(meld.open for meld in req.hand.melds):
        raise HTTPException(status_code=422, detail="riichi/double_riichi require a closed hand (no open melds)")
    if not (req.context.riichi or req.context.double_riichi) and req.context.ippatsu:
        raise HTTPException(status_code=422, detail="ippatsu cannot be true when riichi/double_riichi is false")
    if req.context.win_type == "ron" and req.context.haitei:
        raise HTTPException(status_code=422, detail="haitei cannot be true on ron")
    if req.context.win_type == "ron" and req.context.rinshan:
        raise HTTPException(status_code=422, detail="rinshan cannot be true on ron")
    if req.context.win_type == "tsumo" and req.context.houtei:
        raise HTTPException(status_code=422, detail="houtei cannot be true on tsumo")
    if req.context.win_type == "tsumo" and req.context.chankan:
        raise HTTPException(status_code=422, detail="chankan cannot be true on tsumo")
    if req.context.chiihou and req.context.tenhou:
        raise HTTPException(status_code=422, detail="chiihou and tenhou cannot both be true")
    if (req.context.chiihou or req.context.tenhou) and req.context.win_type != "tsumo":
        raise HTTPException(status_code=422, detail="chiihou/tenhou require tsumo")
    if req.context.tenhou and not req.context.is_dealer:
        raise HTTPException(status_code=422, detail="tenhou requires dealer")
    if req.context.chiihou and req.context.is_dealer:
        raise HTTPException(status_code=422, detail="chiihou requires non-dealer")
    if not _is_valid_winning_shape(req):
        raise HTTPException(status_code=422, detail="Hand is not a valid winning shape")
