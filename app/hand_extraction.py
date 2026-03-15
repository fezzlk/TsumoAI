from __future__ import annotations

import base64
import json
from io import BytesIO
from typing import Any, Callable

from openai import OpenAI
from PIL import Image, ImageEnhance, ImageOps

from app.config import settings
from app.recognition_postprocess import DEFAULT_POLICY, merge_slot_estimates, pick_winning_tiles, slot_options
from app.schemas import HandInput
from app.validators import validate_tile


SYSTEM_PROMPT = """You are a mahjong tile recognizer.
Return JSON only.
Detect exactly 14 winning-hand tiles from a single image.
Use tile codes: 1m-9m,1p-9p,1s-9s,E,S,W,N,P,F,C,5mr,5pr,5sr.
For each slot, return top and up to 3 candidates with confidence [0,1]."""


class RecognitionCancelledError(Exception):
    pass


def _is_valid_tile_code(tile: str) -> bool:
    try:
        validate_tile(tile)
        return True
    except Exception:
        return False


def _parse_payload(output_text: str) -> dict[str, Any]:
    text = output_text.strip()
    if text.startswith("```"):
        lines = text.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].startswith("```"):
            lines = lines[:-1]
        text = "\n".join(lines).strip()
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        start = text.find("{")
        end = text.rfind("}")
        if start == -1 or end == -1 or end <= start:
            raise
        payload = json.loads(text[start : end + 1])
    if not isinstance(payload, dict):
        raise ValueError("recognizer payload must be a JSON object")
    return payload


def _jpeg_bytes(image: Image.Image) -> bytes:
    buf = BytesIO()
    image.convert("RGB").save(buf, format="JPEG", quality=95)
    return buf.getvalue()


def _fallback_result(extra_warnings: list[str] | None = None, include_missing_api_key_warning: bool = True) -> dict[str, Any]:
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
    warnings: list[str] = []
    if include_missing_api_key_warning:
        warnings.append("OPENAI_API_KEY is not set; fallback result is used.")
    if extra_warnings:
        warnings.extend(extra_warnings)
    return {"tiles_count": 14, "slots": slots, "warnings": warnings}


def _coerce_slots(raw_slots: Any) -> list[Any]:
    if isinstance(raw_slots, str):
        raw_slots = json.loads(raw_slots)
    if isinstance(raw_slots, dict):
        return list(raw_slots.values())
    if isinstance(raw_slots, list):
        return raw_slots
    raise ValueError("payload.slots must be list/dict/json-string")


def _normalize_candidates(raw_slots: Any) -> list[dict[str, Any]]:
    slots_list = _coerce_slots(raw_slots)
    normalized: list[dict[str, Any]] = []
    for idx, slot in enumerate(slots_list):
        if isinstance(slot, str):
            parsed = slot.strip()
            if parsed.startswith("{"):
                slot = json.loads(parsed)
            else:
                slot = {"index": idx, "top": parsed, "candidates": [], "ambiguous": True}
        if not isinstance(slot, dict):
            raise ValueError("each slot must be object/string")
        index = int(slot.get("index", idx))
        raw_top = str(slot.get("top", "")).strip()
        candidates = []
        raw_candidates = slot.get("candidates", [])
        if isinstance(raw_candidates, dict):
            raw_candidates = [raw_candidates]
        if isinstance(raw_candidates, str):
            raw_candidates = [raw_candidates]
        for cand in list(raw_candidates)[:3]:
            if isinstance(cand, str):
                cand = {"tile": cand, "confidence": 0.0}
            if not isinstance(cand, dict):
                continue
            tile = str(cand.get("tile", "")).strip()
            if not _is_valid_tile_code(tile):
                continue
            confidence = float(cand.get("confidence", 0.0))
            confidence = min(max(confidence, 0.0), 1.0)
            candidates.append({"tile": tile, "confidence": confidence})
        top = raw_top if _is_valid_tile_code(raw_top) else (candidates[0]["tile"] if candidates else "")
        if not top:
            continue
        top_confidence = float(slot.get("top_confidence", 0.0) or 0.0)
        top_confidence = min(max(top_confidence, 0.0), 1.0)
        normalized.append(
            {
                "index": index,
                "top": top,
                "candidates": candidates,
                "ambiguous": bool(slot.get("ambiguous", False)),
                "top_confidence": top_confidence,
            }
        )
    return sorted(normalized, key=lambda x: x["index"])


def _slot_options(slot: dict[str, Any]) -> list[dict[str, Any]]:
    return slot_options(slot, policy=DEFAULT_POLICY)


def _pick_winning_tiles(slots: list[dict[str, Any]], beam_width: int = 512) -> list[str] | None:
    _ = beam_width  # compatibility with existing tests/calls
    return pick_winning_tiles(slots, policy=DEFAULT_POLICY)


def _image_variants(image_bytes: bytes) -> list[tuple[str, bytes, float]]:
    with Image.open(BytesIO(image_bytes)) as img:
        rgb = img.convert("RGB")
        variants = [
            ("orig", _jpeg_bytes(rgb), 1.0),
            ("autocontrast", _jpeg_bytes(ImageOps.autocontrast(rgb, cutoff=1)), 0.95),
            (
                "contrast_sharp",
                _jpeg_bytes(
                    ImageEnhance.Sharpness(ImageEnhance.Contrast(rgb).enhance(1.15)).enhance(1.2)
                ),
                0.9,
            ),
        ]
    return variants


def _call_model_for_slots(client: OpenAI, image_bytes: bytes) -> dict[str, Any]:
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
    return _parse_payload(output_text)


def _merge_slot_estimates(estimates: list[tuple[list[dict[str, Any]], float]]) -> list[dict[str, Any]]:
    merged = merge_slot_estimates(estimates, policy=DEFAULT_POLICY)
    for slot in merged:
        validate_tile(slot["top"])
    return merged


def extract_hand_from_image(image_bytes: bytes, should_cancel: Callable[[], bool] | None = None) -> dict[str, Any]:
    """Image -> hand-shape candidates. This module must not score."""
    if should_cancel and should_cancel():
        raise RecognitionCancelledError("recognition canceled")

    # Try local TFLite recognition first
    try:
        from app.tile_recognizer_local import recognize_tiles_local

        local_result = recognize_tiles_local(image_bytes)
        if local_result is not None:
            return local_result
    except Exception:
        pass  # Fall through to OpenAI API

    if not settings.openai_api_key:
        return _fallback_result()

    client = OpenAI(api_key=settings.openai_api_key)
    variants = _image_variants(image_bytes)
    passes = max(1, min(settings.recognize_ensemble_passes, len(variants)))
    collected: list[tuple[list[dict[str, Any]], float]] = []
    warnings: list[str] = []
    tiles_count_votes: list[int] = []

    for name, variant_bytes, weight in variants[:passes]:
        if should_cancel and should_cancel():
            raise RecognitionCancelledError("recognition canceled")
        try:
            payload = _call_model_for_slots(client, variant_bytes)
            slots = _normalize_candidates(payload.get("slots", []))
            if not slots:
                raise ValueError("slots is empty")
            collected.append((slots, weight))
            tiles_count_votes.append(int(payload.get("tiles_count", len(slots))))
            for warning in list(payload.get("warnings", [])):
                warnings.append(f"{name}:{warning}")
        except Exception as exc:
            warnings.append(f"{name}:recognition failed ({exc})")

    if not collected:
        fallback = _fallback_result(
            extra_warnings=warnings + ["All recognition passes failed; fallback was used."],
            include_missing_api_key_warning=False,
        )
        return fallback

    if len(collected) == 1:
        merged_slots = collected[0][0]
    else:
        merged_slots = _merge_slot_estimates(collected)
        warnings.append(f"Ensemble merge applied across {len(collected)} passes.")

    tiles_count = max(set(tiles_count_votes), key=tiles_count_votes.count) if tiles_count_votes else len(merged_slots)
    return {
        "tiles_count": int(tiles_count),
        "slots": merged_slots,
        "warnings": warnings,
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
