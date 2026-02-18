from __future__ import annotations

import base64
import json
from typing import Any

from openai import OpenAI

from app.config import settings
from app.schemas import HandInput
from app.validators import validate_tile


SYSTEM_PROMPT = """You are a mahjong tile recognizer.
Return JSON only.
Detect exactly 14 winning-hand tiles from a single image.
Use tile codes: 1m-9m,1p-9p,1s-9s,E,S,W,N,P,F,C,5mr,5pr,5sr.
For each slot, return top and up to 3 candidates with confidence [0,1]."""


def _fallback_result() -> dict[str, Any]:
    tiles = ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "5mr", "5pr"]
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
    """Candidates -> concrete hand shape (top-1) for downstream scoring."""
    top_tiles = [slot["top"] for slot in estimate["slots"]]
    return HandInput(closed_tiles=top_tiles, melds=[], win_tile=top_tiles[-1])
