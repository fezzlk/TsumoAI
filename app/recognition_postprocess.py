from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any

from app.schemas import HandInput
from app.tile_weighting import tile_reliability_weight, tile_similarity
from app.validators import is_valid_winning_shape_hand


@dataclass(frozen=True)
class RecognitionPolicy:
    """Centralized policy for recognition post-processing.

    Keep all tunable knobs here to avoid one-off fixes scattered in code.
    """

    top_conf_floor: float = 0.55
    merge_top_weight: float = 1.0
    merge_candidate_weight: float = 1.0
    adjacency_same_suit_bonus: float = 0.12
    adjacency_far_penalty: float = 0.05
    beam_width: int = 512


DEFAULT_POLICY = RecognitionPolicy()


def _normalize_tile(tile: str) -> str:
    if tile in {"5mr", "5pr", "5sr"}:
        return tile[:2]
    return tile


def _tile_number_suit(tile: str) -> tuple[int, str] | None:
    t = _normalize_tile(tile)
    if len(t) == 2 and t[0].isdigit() and t[1] in {"m", "p", "s"}:
        return int(t[0]), t[1]
    return None


def slot_options(slot: dict[str, Any], policy: RecognitionPolicy = DEFAULT_POLICY) -> list[dict[str, Any]]:
    dedup: dict[str, float] = {}
    top = slot["top"]
    top_conf = float(slot.get("top_confidence", 0.0) or 0.0)
    best_top_candidate_conf = 0.0
    for cand in slot.get("candidates", []):
        if cand["tile"] == top:
            best_top_candidate_conf = max(best_top_candidate_conf, float(cand.get("confidence", 0.0)))
    dedup[top] = max(top_conf, best_top_candidate_conf, policy.top_conf_floor)
    for cand in slot.get("candidates", []):
        tile = cand["tile"]
        dedup[tile] = max(dedup.get(tile, 0.0), float(cand.get("confidence", 0.0)))
    weighted = []
    for tile, conf in dedup.items():
        weighted_conf = conf * tile_reliability_weight(tile)
        weighted.append({"tile": tile, "confidence": min(max(weighted_conf, 0.0), 1.0)})
    return weighted


def merge_slot_estimates(
    estimates: list[tuple[list[dict[str, Any]], float]],
    policy: RecognitionPolicy = DEFAULT_POLICY,
) -> list[dict[str, Any]]:
    max_len = max(len(slots) for slots, _ in estimates)
    merged: list[dict[str, Any]] = []

    for idx in range(max_len):
        score_map: dict[str, float] = {}
        ambiguous = False
        for slots, weight in estimates:
            if idx >= len(slots):
                continue
            slot = slots[idx]
            ambiguous = ambiguous or bool(slot.get("ambiguous", False))
            top_tile = slot["top"]
            top_conf = float(slot.get("top_confidence", 0.0) or 0.0)
            top_candidate_conf = 0.0
            for cand in slot.get("candidates", []):
                if cand["tile"] == top_tile:
                    top_candidate_conf = max(top_candidate_conf, float(cand.get("confidence", 0.0)))
            score_map[top_tile] = score_map.get(top_tile, 0.0) + (
                max(top_conf, top_candidate_conf, policy.top_conf_floor) * weight * policy.merge_top_weight
            )
            for cand in slot.get("candidates", []):
                tile = cand["tile"]
                conf = float(cand.get("confidence", 0.0))
                score_map[tile] = score_map.get(tile, 0.0) + (conf * weight * policy.merge_candidate_weight)

        ranked = sorted(score_map.items(), key=lambda x: x[1], reverse=True)
        if not ranked:
            continue
        total = sum(score for _, score in ranked) or 1.0
        merged.append(
            {
                "index": idx,
                "top": ranked[0][0],
                "candidates": [
                    {"tile": tile, "confidence": min(max(score / total, 0.0), 1.0)}
                    for tile, score in ranked[:3]
                ],
                "ambiguous": ambiguous,
            }
        )
    return merged


def _transition_prior(prev_tile: str | None, current_tile: str, policy: RecognitionPolicy) -> float:
    if not prev_tile:
        return 0.0
    a = _tile_number_suit(prev_tile)
    b = _tile_number_suit(current_tile)
    if not a or not b:
        return 0.0
    a_num, a_suit = a
    b_num, b_suit = b
    if a_suit == b_suit and abs(a_num - b_num) <= 2:
        return policy.adjacency_same_suit_bonus
    if a_suit != b_suit and abs(a_num - b_num) >= 4:
        return -policy.adjacency_far_penalty
    # Small prior based on template similarity after orange-header removal.
    sim = tile_similarity(prev_tile, current_tile)
    if sim >= 0.9:
        return 0.02
    return 0.0


def pick_winning_tiles(
    slots: list[dict[str, Any]],
    policy: RecognitionPolicy = DEFAULT_POLICY,
) -> list[str] | None:
    states: list[dict[str, Any]] = [{"tiles": [], "counts": {}, "score": 0.0}]

    for slot in slots:
        options = slot_options(slot, policy=policy)
        next_states: list[dict[str, Any]] = []
        for state in states:
            prev_tile = state["tiles"][-1] if state["tiles"] else None
            for option in options:
                tile = option["tile"]
                normalized = _normalize_tile(tile)
                tile_count = state["counts"].get(normalized, 0)
                if tile_count >= 4:
                    continue
                next_counts = dict(state["counts"])
                next_counts[normalized] = tile_count + 1
                prior = _transition_prior(prev_tile, tile, policy)
                next_states.append(
                    {
                        "tiles": state["tiles"] + [tile],
                        "counts": next_counts,
                        "score": state["score"] + math.log(max(option["confidence"], 1e-6)) + prior,
                    }
                )
        if not next_states:
            return None
        next_states.sort(key=lambda item: item["score"], reverse=True)
        states = next_states[: policy.beam_width]

    for state in states:
        tiles = state["tiles"]
        hand = HandInput(closed_tiles=tiles, melds=[], win_tile=tiles[-1])
        if is_valid_winning_shape_hand(hand):
            return tiles
    return None
