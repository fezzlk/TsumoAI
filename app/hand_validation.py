"""Shared score and analysis input checks; callers choose their error transport."""

from collections import Counter

from app.domain.decomposition import is_winning_hand
from app.domain.melds import validate_meld
from app.domain.tiles import is_tile_code, normalize_tile, tiles_to_counts
from app.schemas import ContextInput, HandInput, Meld


def validate_tile_code(tile: str) -> None:
    if not is_tile_code(tile):
        raise ValueError(f"Invalid tile code: {tile}")


def validate_hand_tiles_and_melds(closed_tiles: list[str], melds: list[Meld]) -> None:
    if len(melds) > 4:
        raise ValueError("A hand cannot contain more than four declared melds")
    for tile in closed_tiles:
        validate_tile_code(tile)
    for meld in melds:
        validate_meld(meld.type, meld.tiles, meld.open)


def validate_hand_context(melds: list[Meld], context: ContextInput) -> None:
    for tile in [*context.dora_indicators, *context.ura_dora_indicators]:
        validate_tile_code(tile)
    if context.riichi and context.double_riichi:
        raise ValueError("riichi and double_riichi cannot both be true")
    if (context.riichi or context.double_riichi) and any(meld.open for meld in melds):
        raise ValueError("riichi/double_riichi require a closed hand (no open melds)")
    if not (context.riichi or context.double_riichi) and context.ippatsu:
        raise ValueError("ippatsu cannot be true when riichi/double_riichi is false")
    if context.win_type == "ron" and context.haitei:
        raise ValueError("haitei cannot be true on ron")
    if context.win_type == "ron" and context.rinshan:
        raise ValueError("rinshan cannot be true on ron")
    if context.win_type == "tsumo" and context.houtei:
        raise ValueError("houtei cannot be true on tsumo")
    if context.win_type == "tsumo" and context.chankan:
        raise ValueError("chankan cannot be true on tsumo")
    if context.chiihou and context.tenhou:
        raise ValueError("chiihou and tenhou cannot both be true")
    if (context.chiihou or context.tenhou) and context.win_type != "tsumo":
        raise ValueError("chiihou/tenhou require tsumo")
    if context.tenhou and context.seat_wind != "E":
        raise ValueError("tenhou requires dealer")
    if context.chiihou and context.seat_wind == "E":
        raise ValueError("chiihou requires non-dealer")


def validate_winning_hand(hand: HandInput, context: ContextInput) -> None:
    validate_hand_tiles_and_melds(hand.closed_tiles, hand.melds)
    validate_tile_code(hand.win_tile)
    all_tiles = [*hand.closed_tiles, *(tile for meld in hand.melds for tile in meld.tiles)]
    counts = Counter(normalize_tile(tile) for tile in all_tiles)
    for tile, count in counts.items():
        if count > 4:
            raise ValueError(f"Tile appears 5+ times in hand: {tile}")

    kans = sum(meld.type in {"kan", "ankan", "kakan"} for meld in hand.melds)
    expected = 14 + kans
    if len(all_tiles) != expected:
        raise ValueError(f"Total tiles must be {expected} at win state (14 + number of kans)")
    if normalize_tile(hand.win_tile) not in {normalize_tile(tile) for tile in hand.closed_tiles}:
        raise ValueError("win_tile must be present in closed_tiles")
    validate_hand_context(hand.melds, context)
    if not is_winning_hand(tiles_to_counts(hand.closed_tiles), len(hand.melds)):
        raise ValueError("Hand is not a valid winning shape")
