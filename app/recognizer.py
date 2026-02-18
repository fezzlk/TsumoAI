from __future__ import annotations

from app.hand_extraction import extract_hand_from_image


def recognize_tiles(image_bytes: bytes) -> dict:
    """Backward-compatible wrapper. Use app.hand_extraction instead."""
    return extract_hand_from_image(image_bytes)
