#!/usr/bin/env python3
from __future__ import annotations

import argparse
import itertools
import json
from pathlib import Path

from app.recognition_postprocess import RecognitionPolicy, pick_winning_tiles


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Grid-search scaffold for RecognitionPolicy")
    p.add_argument("--input", default="data/recognition_feedback.jsonl")
    p.add_argument("--min-cases", type=int, default=10)
    return p.parse_args()


def load_cases(path: Path) -> list[tuple[list[dict], list[str]]]:
    cases = []
    if not path.exists():
        return cases
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            payload = row.get("payload", {})
            resp = payload.get("recognition_response", {})
            slots = (((resp or {}).get("hand_estimate") or {}).get("slots") or [])
            gt = payload.get("corrected_tiles") or []
            if len(slots) == 14 and len(gt) == 14:
                cases.append((slots, gt))
    return cases


def eval_policy(cases: list[tuple[list[dict], list[str]]], policy: RecognitionPolicy) -> tuple[float, float]:
    tile_total = 0
    tile_correct = 0
    exact = 0
    for slots, gt in cases:
        picked = pick_winning_tiles(slots, policy=policy)
        pred = picked if picked else [slot["top"] for slot in slots]
        if pred == gt:
            exact += 1
        for p, g in zip(pred, gt):
            tile_total += 1
            if p == g:
                tile_correct += 1
    tile_acc = tile_correct / tile_total if tile_total else 0.0
    exact_acc = exact / len(cases) if cases else 0.0
    return tile_acc, exact_acc


def main() -> int:
    args = parse_args()
    cases = load_cases(Path(args.input))
    if len(cases) < args.min_cases:
        print(f"not enough cases: {len(cases)} < {args.min_cases}")
        return 1

    grid = {
        "top_conf_floor": [0.45, 0.55, 0.65],
        "adjacency_same_suit_bonus": [0.08, 0.12, 0.16],
        "adjacency_far_penalty": [0.03, 0.05, 0.08],
    }
    best = None
    for tcf, ssb, afp in itertools.product(
        grid["top_conf_floor"], grid["adjacency_same_suit_bonus"], grid["adjacency_far_penalty"]
    ):
        policy = RecognitionPolicy(
            top_conf_floor=tcf,
            adjacency_same_suit_bonus=ssb,
            adjacency_far_penalty=afp,
        )
        tile_acc, exact_acc = eval_policy(cases, policy)
        score = (tile_acc, exact_acc)
        if best is None or score > best[0]:
            best = (score, policy)

    assert best is not None
    (tile_acc, exact_acc), policy = best
    print("best policy:")
    print(policy)
    print(f"tile_accuracy={tile_acc:.4f}")
    print(f"exact_match_rate={exact_acc:.4f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
