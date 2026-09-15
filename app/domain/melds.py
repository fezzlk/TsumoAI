"""Structural rules for declared melds, independent of transport or schemas."""

from collections.abc import Sequence

from app.domain.tiles import is_tile_code, normalize_tile


def validate_meld(kind: str, tiles: Sequence[str], is_open: bool) -> None:
    if kind not in {"chi", "pon", "kan", "ankan", "kakan"}:
        raise ValueError(f"Invalid meld type: {kind}")
    expected = 3 if kind in {"chi", "pon"} else 4
    if len(tiles) != expected:
        raise ValueError(f"{kind} must contain exactly {expected} tiles")
    for tile in tiles:
        if not is_tile_code(tile):
            raise ValueError(f"Invalid tile code: {tile}")

    normalized = [normalize_tile(tile) for tile in tiles]
    if kind == "chi":
        if not is_open:
            raise ValueError("chi must be open")
        if any(len(tile) != 2 or tile[1] not in "mps" for tile in normalized):
            raise ValueError("chi must contain suited tiles")
        suits = {tile[1] for tile in normalized}
        numbers = sorted(int(tile[0]) for tile in normalized)
        if len(suits) != 1 or numbers != list(range(numbers[0], numbers[0] + 3)):
            raise ValueError(f"tiles do not form chi: {list(tiles)}")
    else:
        if len(set(normalized)) != 1:
            raise ValueError(f"{kind} tiles must all be the same tile")
        required_open = kind != "ankan"
        if is_open != required_open:
            raise ValueError(f"{kind} open must be {str(required_open).lower()}")
