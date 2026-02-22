from __future__ import annotations

import base64
import json
import math
from typing import Any

from openai import OpenAI

from app.config import settings
from app.schemas import HandInput
from app.validators import is_valid_winning_shape_hand, validate_tile


SYSTEM_PROMPT = """You are a mahjong tile recognizer.
Return JSON only.
Detect exactly 14 winning-hand tiles from a single image.
Use tile codes: 1m-9m,1p-9p,1s-9s,E,S,W,N,P,F,C,5mr,5pr,5sr.
For each slot, return top and up to 3 candidates with confidence [0,1]."""


def _fallback_result() -> dict[str, Any]:
    tiles = ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "2p", "2p"]
    slots = []
    for idx, tile in enumerate(tiles):
        slots.append(
            {
                "index": idx,
                "top": tile,
                "candidates": [
                    {"tile": tile, "confidence": 0.55},
                    {"tile": tile, "confidence": 0.25},
                    {"tile": tile, "confidence": 0.20},
                ],
                "ambiguous": True,
            }
        )
    return {"tiles_count": 14, "slots": slots, "warnings": ["OPENAI_API_KEY is not set; fallback result is used."]}


def _normalize_candidates(raw_slots: list[dict[str, Any]]) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    for slot in raw_slots:
        index = int(slot.get("index"))
        top = str(slot.get("top"))
        validate_tile(top)
        candidates = []
        for cand in slot.get("candidates", [])[:3]:
            tile = str(cand.get("tile"))
            validate_tile(tile)
            confidence = float(cand.get("confidence", 0.0))
            confidence = min(max(confidence, 0.0), 1.0)
            candidates.append({"tile": tile, "confidence": confidence})
        normalized.append(
            {
                "index": index,
                "top": top,
                "candidates": candidates,
                "ambiguous": bool(slot.get("ambiguous", False)),
            }
        )
    return sorted(normalized, key=lambda x: x["index"])


def _normalize_tile(tile: str) -> str:
    if tile in {"5mr", "5pr", "5sr"}:
        return tile[:2]
    return tile


def _slot_options(slot: dict[str, Any]) -> list[dict[str, Any]]:
    dedup: dict[str, float] = {}
    top = slot["top"]
    dedup[top] = 1.0
    for cand in slot.get("candidates", []):
        tile = cand["tile"]
        dedup[tile] = max(dedup.get(tile, 0.0), float(cand.get("confidence", 0.0)))
    return [{"tile": t, "confidence": c} for t, c in dedup.items()]


def _pick_winning_tiles(slots: list[dict[str, Any]], beam_width: int = 512) -> list[str] | None:
    states: list[dict[str, Any]] = [{"tiles": [], "counts": {}, "score": 0.0}]

    for slot in slots:
        options = _slot_options(slot)
        next_states: list[dict[str, Any]] = []
        for state in states:
            for option in options:
                tile = option["tile"]
                normalized = _normalize_tile(tile)
                tile_count = state["counts"].get(normalized, 0)
                if tile_count >= 4:
                    continue
                next_counts = dict(state["counts"])
                next_counts[normalized] = tile_count + 1
                next_states.append(
                    {
                        "tiles": state["tiles"] + [tile],
                        "counts": next_counts,
                        "score": state["score"] + math.log(max(option["confidence"], 1e-6)),
                    }
                )
        if not next_states:
            return None
        next_states.sort(key=lambda item: item["score"], reverse=True)
        states = next_states[:beam_width]

    for state in states:
        tiles = state["tiles"]
        hand = HandInput(closed_tiles=tiles, melds=[], win_tile=tiles[-1])
        if is_valid_winning_shape_hand(hand):
            return tiles
    return None


def extract_hand_from_image(image_bytes: bytes) -> dict[str, Any]:
    """Image -> hand-shape candidates. This module must not score."""
    if not settings.openai_api_key:
        return _fallback_result()

    client = OpenAI(api_key=settings.openai_api_key)
    image_b64 = base64.b64encode(image_bytes).decode("ascii")
    if hasattr(client, "responses"):
        response = client.responses.create(
            model=settings.openai_model,
            input=[
                {
                    "role": "system",
                    "content": [{"type": "input_text", "text": SYSTEM_PROMPT}],
                },
                {
                    "role": "user",
                    "content": [
                        {"type": "input_text", "text": "Return strict JSON with keys: tiles_count, slots, warnings."},
                        {"type": "input_image", "image_url": f"data:image/jpeg;base64,{image_b64}"},
                    ],
                },
            ],
            temperature=0,
        )
        output_text = response.output_text
    else:
        response = client.chat.completions.create(
            model=settings.openai_model,
            temperature=0,
            response_format={"type": "json_object"},
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": "Return strict JSON with keys: tiles_count, slots, warnings."},
                        {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"}},
                    ],
                },
            ],
        )
        output_text = response.choices[0].message.content or "{}"

    payload = json.loads(output_text)
    slots = _normalize_candidates(payload["slots"])
    return {
        "tiles_count": int(payload.get("tiles_count", len(slots))),
        "slots": slots,
        "warnings": list(payload.get("warnings", [])),
    }


def hand_shape_from_estimate(estimate: dict[str, Any]) -> HandInput:
    """Candidates -> concrete hand shape for downstream scoring."""
    tiles, _warnings = hand_shape_from_estimate_with_warnings(estimate)
    return tiles


def hand_shape_from_estimate_with_warnings(estimate: dict[str, Any]) -> tuple[HandInput, list[str]]:
    slots = estimate.get("slots", [])
    if not slots:
        raise ValueError("estimate.slots is empty")

    top_tiles = [slot["top"] for slot in slots]
    warnings: list[str] = []

    winning_tiles = _pick_winning_tiles(slots)
    if winning_tiles is None:
        warnings.append("Could not derive a guaranteed winning hand from candidates; using top-1 tiles.")
        winning_tiles = top_tiles
    elif winning_tiles != top_tiles:
        warnings.append("Hand was adjusted from top-1 predictions to a candidate combination with winning shape.")

    return HandInput(closed_tiles=winning_tiles, melds=[], win_tile=winning_tiles[-1]), warnings
