#!/usr/bin/env python3
"""Score tile-segmentation results against the evaluation set (FEZ-245).

  python scripts/score_segmentation_eval.py data/segmentation_eval_v1 [label ...]

For each results_<label>.json written by mobile/test/tools/segmentation_eval_test.dart:
- count: the segmenter returned exactly as many boxes as there are tiles
- recall: share of true tiles matched by a box with IoU >= 0.5 (one-to-one)
- iou: mean IoU of the matched pairs
Reported per category and overall; per-case misses are listed with -v.
"""

import json
import sys
from collections import defaultdict
from pathlib import Path


def iou(a, b):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    ix = max(0.0, min(ax + aw, bx + bw) - max(ax, bx))
    iy = max(0.0, min(ay + ah, by + bh) - max(ay, by))
    inter = ix * iy
    union = aw * ah + bw * bh - inter
    return inter / union if union else 0.0


def match(truth, found, threshold=0.5):
    pairs = sorted(
        ((iou(t, f), i, j) for i, t in enumerate(truth) for j, f in enumerate(found)),
        reverse=True,
    )
    used_t, used_f, matched = set(), set(), []
    for score, i, j in pairs:
        if score < threshold:
            break
        if i in used_t or j in used_f:
            continue
        used_t.add(i)
        used_f.add(j)
        matched.append(score)
    return matched


def score(set_dir: Path, label: str, verbose: bool):
    manifest = json.loads((set_dir / "manifest.json").read_text())
    results = {
        r["case_id"]: r
        for r in json.loads((set_dir / f"results_{label}.json").read_text())["results"]
    }
    by_cat = defaultdict(lambda: {"cases": 0, "count_ok": 0, "tiles": 0, "matched": 0, "iou": 0.0})
    misses = []
    for case in manifest["cases"]:
        found = results[case["case_id"]]["boxes"]
        matched = match(case["boxes"], found)
        for key in (case["category"], "ALL"):
            s = by_cat[key]
            s["cases"] += 1
            s["count_ok"] += len(found) == case["tile_count"]
            s["tiles"] += case["tile_count"]
            s["matched"] += len(matched)
            s["iou"] += sum(matched)
        if len(matched) < case["tile_count"]:
            misses.append((case["case_id"], case["tile_count"], len(found), len(matched)))
    print(f"== {label}")
    print(f"{'category':14} {'cases':>5} {'count':>7} {'recall':>7} {'iou':>5}")
    for key in sorted(by_cat, key=lambda k: (k == "ALL", k)):
        s = by_cat[key]
        print(
            f"{key:14} {s['cases']:5d} {s['count_ok'] / s['cases']:7.0%} "
            f"{s['matched'] / s['tiles']:7.0%} {s['iou'] / max(1, s['matched']):5.2f}"
        )
    if verbose:
        for case_id, truth, found, matched in misses:
            print(f"  miss {case_id}: tiles={truth} boxes={found} matched={matched}")


def main():
    args = [a for a in sys.argv[1:] if a != "-v"]
    set_dir = Path(args[0])
    labels = args[1:] or [p.stem.removeprefix("results_") for p in sorted(set_dir.glob("results_*.json"))]
    for label in labels:
        score(set_dir, label, "-v" in sys.argv)


if __name__ == "__main__":
    main()
