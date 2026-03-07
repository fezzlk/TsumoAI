#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Build confusion summary from recognition feedback JSONL")
    p.add_argument("--input", default="data/recognition_feedback.jsonl")
    p.add_argument("--top", type=int, default=30)
    return p.parse_args()


def load_rows(path: Path) -> list[dict]:
    rows = []
    if not path.exists():
        return rows
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def main() -> int:
    args = parse_args()
    rows = load_rows(Path(args.input))
    confusion = Counter()
    total = 0
    correct = 0

    for row in rows:
        payload = row.get("payload", {})
        resp = payload.get("recognition_response", {})
        slots = (((resp or {}).get("hand_estimate") or {}).get("slots") or [])
        pred = [slot.get("top") for slot in slots]
        gt = payload.get("corrected_tiles") or []
        if len(pred) != 14 or len(gt) != 14:
            continue
        for p, g in zip(pred, gt):
            total += 1
            if p == g:
                correct += 1
            else:
                confusion[(g, p)] += 1

    print(f"cases={len(rows)} total_tiles={total} accuracy={(correct / total * 100 if total else 0):.2f}%")
    print("top confusions (ground_truth -> predicted):")
    for (gt, pred), cnt in confusion.most_common(args.top):
        print(f"{gt:>3} -> {pred:<3} : {cnt}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
