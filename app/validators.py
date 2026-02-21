import re
from functools import lru_cache

from fastapi import HTTPException

from app.schemas import ScoreRequest

TILE_RE = re.compile(r"^(?:[1-9][mps]|5[smpr]r|[ESWNPFC])$")
TERMINAL_HONOR_INDICES = {
    0,
    8,
    9,
    17,
    18,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
    33,
}


def validate_tile(tile: str) -> None:
    if not TILE_RE.fullmatch(tile):
        raise HTTPException(status_code=422, detail=f"Invalid tile code: {tile}")


def _normalize_tile(tile: str) -> str:
    if tile in {"5mr", "5pr", "5sr"}:
        return tile[:2]
    return tile


def _tile_to_index(tile: str) -> int:
    t = _normalize_tile(tile)
    if len(t) == 2 and t[0].isdigit():
        num = int(t[0])
        suit = t[1]
        base = {"m": 0, "p": 9, "s": 18}[suit]
        return base + (num - 1)
    honor_map = {"E": 27, "S": 28, "W": 29, "N": 30, "P": 31, "F": 32, "C": 33}
    return honor_map[t]


def _is_chiitoi(counts: list[int]) -> bool:
    return sum(1 for c in counts if c == 2) == 7 and all(c in {0, 2} for c in counts)


def _is_kokushi(counts: list[int]) -> bool:
    if any(counts[i] > 0 and i not in TERMINAL_HONOR_INDICES for i in range(34)):
        return False
    pair_found = False
    for idx in TERMINAL_HONOR_INDICES:
        if counts[idx] == 0:
            return False
        if counts[idx] >= 2:
            pair_found = True
    return pair_found


@lru_cache(maxsize=20000)
def _can_form_melds(counts_tuple: tuple[int, ...], needed_melds: int) -> bool:
    if needed_melds == 0:
        return all(c == 0 for c in counts_tuple)

    counts = list(counts_tuple)
    first = next((i for i, c in enumerate(counts) if c > 0), -1)
    if first == -1:
        return False

    if counts[first] >= 3:
        counts[first] -= 3
        if _can_form_melds(tuple(counts), needed_melds - 1):
            return True
        counts[first] += 3

    if first < 27 and first % 9 <= 6 and counts[first + 1] > 0 and counts[first + 2] > 0:
        counts[first] -= 1
        counts[first + 1] -= 1
        counts[first + 2] -= 1
        if _can_form_melds(tuple(counts), needed_melds - 1):
            return True
    return False


def _is_standard_win(counts: list[int], open_melds: int) -> bool:
    needed_melds = 4 - open_melds
    expected_tiles = needed_melds * 3 + 2
    if sum(counts) != expected_tiles:
        return False
    for i, c in enumerate(counts):
        if c >= 2:
            tmp = counts[:]
            tmp[i] -= 2
            if _can_form_melds(tuple(tmp), needed_melds):
                return True
    return False


def _is_valid_winning_shape(req: ScoreRequest) -> bool:
    closed_counts = [0] * 34
    for tile in req.hand.closed_tiles:
        closed_counts[_tile_to_index(tile)] += 1

    open_melds = len(req.hand.melds)
    if open_melds == 0:
        if _is_chiitoi(closed_counts) or _is_kokushi(closed_counts):
            return True
    return _is_standard_win(closed_counts, open_melds)


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
    if not (req.context.riichi or req.context.double_riichi) and req.context.ippatsu:
        raise HTTPException(status_code=422, detail="ippatsu cannot be true when riichi/double_riichi is false")
    if req.context.win_type == "ron" and req.context.haitei:
        raise HTTPException(status_code=422, detail="haitei cannot be true on ron")
    if req.context.win_type == "tsumo" and req.context.houtei:
        raise HTTPException(status_code=422, detail="houtei cannot be true on tsumo")
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
