#!/usr/bin/env python3
"""Verify whether the OpenAI Vision recognizer can also return usable per-tile bboxes.

FEZ-95: app/hand_extraction.py's Vision path only returns tile codes + confidence today.
This script calls the model with a bbox-extended prompt (SYSTEM_PROMPT_WITH_BBOX) against
the existing evaluation image sets and reports:
  - format validity: fraction of slots with a well-formed, non-degenerate normalized bbox
  - tile accuracy: whether asking for bbox alongside the tile code hurts recognition
    accuracy on the labeled cropped set (compared against the known ground truth)
  - annotated overlay images for manual visual review of bbox usefulness

This is exploratory only; it does not change extract_hand_from_image or any production
code path. See app/hand_extraction.py::SYSTEM_PROMPT_WITH_BBOX / _call_model_for_slots.
"""

from __future__ import annotations

import argparse
import json
from io import BytesIO
from pathlib import Path
from typing import Any

from openai import OpenAI
from PIL import Image, ImageDraw

from app.config import settings
from app.hand_extraction import (
    SYSTEM_PROMPT_WITH_BBOX,
    _call_model_for_slots,
    _coerce_slots,
    _is_valid_tile_code,
)

PRICE_PER_CALL_JPY = 2.5  # rough estimate per issue text (gpt-4o-mini, single image)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Verify VLM bbox estimation quality (FEZ-95).")
    p.add_argument(
        "--labeled-set",
        default="data/recognition_eval_set_cropped.jsonl",
        help="JSONL with ground-truth tiles, used for the accuracy comparison",
    )
    p.add_argument(
        "--tilted-dir",
        default="data/eval_images_tilted",
        help="Directory of unlabeled tilted/curved photos, used for format/visual check only",
    )
    p.add_argument(
        "--out-dir",
        required=True,
        help="Directory to write annotated overlay images and the raw results JSON",
    )
    p.add_argument("--limit", type=int, default=None, help="Cap number of images processed (cost control)")
    return p.parse_args()


def _load_labeled_rows(path: Path) -> list[dict]:
    rows: list[dict] = []
    if not path.exists():
        return rows
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def _jpeg_bytes(image_path: Path) -> bytes:
    with Image.open(image_path) as img:
        rgb = img.convert("RGB")
        out = BytesIO()
        rgb.save(out, format="JPEG", quality=95)
        return out.getvalue()


def _extract_bbox(slot: dict[str, Any]) -> tuple[float, float, float, float] | None:
    raw = slot.get("bbox")
    if isinstance(raw, dict):
        try:
            raw = [raw["x_min"], raw["y_min"], raw["x_max"], raw["y_max"]]
        except KeyError:
            return None
    if not isinstance(raw, (list, tuple)) or len(raw) != 4:
        return None
    try:
        x_min, y_min, x_max, y_max = (float(v) for v in raw)
    except (TypeError, ValueError):
        return None
    return x_min, y_min, x_max, y_max


def _bbox_is_well_formed(bbox: tuple[float, float, float, float]) -> bool:
    x_min, y_min, x_max, y_max = bbox
    tolerance = 0.05
    if not all(-tolerance <= v <= 1 + tolerance for v in bbox):
        return False
    width = x_max - x_min
    height = y_max - y_min
    min_side = 0.01  # a 14-tile hand can't have a tile narrower than ~1% of the frame
    return width >= min_side and height >= min_side


def _parse_slots_with_bbox(payload: dict[str, Any]) -> list[dict[str, Any]]:
    slots_list = _coerce_slots(payload.get("slots", []))
    parsed = []
    for idx, slot in enumerate(slots_list):
        if isinstance(slot, str) and slot.strip().startswith("{"):
            slot = json.loads(slot)
        if not isinstance(slot, dict):
            continue
        top = str(slot.get("top", "")).strip()
        if not _is_valid_tile_code(top):
            candidates = slot.get("candidates", [])
            if isinstance(candidates, list) and candidates and isinstance(candidates[0], dict):
                top = str(candidates[0].get("tile", "")).strip()
        bbox = _extract_bbox(slot)
        parsed.append(
            {
                "index": int(slot.get("index", idx)),
                "top": top,
                "top_valid": _is_valid_tile_code(top),
                "bbox": bbox,
                "bbox_well_formed": bbox is not None and _bbox_is_well_formed(bbox),
            }
        )
    return sorted(parsed, key=lambda s: s["index"])


def _draw_overlay(image_path: Path, slots: list[dict[str, Any]], out_path: Path) -> None:
    with Image.open(image_path) as img:
        rgb = img.convert("RGB")
        width, height = rgb.size
        draw = ImageDraw.Draw(rgb)
        for slot in slots:
            if slot["bbox"] is None:
                continue
            x_min, y_min, x_max, y_max = slot["bbox"]
            box = (x_min * width, y_min * height, x_max * width, y_max * height)
            color = "lime" if slot["bbox_well_formed"] else "red"
            draw.rectangle(box, outline=color, width=3)
            draw.text((box[0] + 2, box[1] + 2), f"{slot['index']}:{slot['top']}", fill=color)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        rgb.save(out_path, format="JPEG", quality=90)


def _evaluate_image(client: OpenAI, image_path: Path, out_dir: Path) -> dict[str, Any]:
    payload = _call_model_for_slots(client, _jpeg_bytes(image_path), system_prompt=SYSTEM_PROMPT_WITH_BBOX)
    slots = _parse_slots_with_bbox(payload)
    _draw_overlay(image_path, slots, out_dir / f"{image_path.stem}_bbox.jpg")
    return {"image": str(image_path), "slots_count": len(slots), "slots": slots}


def main() -> int:
    args = parse_args()
    if not settings.openai_api_key:
        print("OPENAI_API_KEY is not set; cannot run live evaluation.")
        return 1

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    client = OpenAI(api_key=settings.openai_api_key)

    labeled_rows = _load_labeled_rows(Path(args.labeled_set))
    tilted_images = sorted(Path(args.tilted_dir).glob("*.jpg")) if Path(args.tilted_dir).exists() else []

    tasks: list[tuple[Path, list[str] | None]] = [
        (Path(row["image_path"]), row.get("corrected_tiles")) for row in labeled_rows if Path(row["image_path"]).exists()
    ] + [(p, None) for p in tilted_images]

    if args.limit is not None:
        tasks = tasks[: args.limit]

    print(f"Evaluating {len(tasks)} image(s); estimated cost ~{len(tasks) * PRICE_PER_CALL_JPY:.1f} JPY")

    results = []
    bbox_well_formed_total = 0
    bbox_total = 0
    tile_correct = 0
    tile_total = 0

    for image_path, ground_truth in tasks:
        try:
            result = _evaluate_image(client, image_path, out_dir)
        except Exception as exc:  # keep going; report the failure per-image
            results.append({"image": str(image_path), "error": str(exc)})
            print(f"FAILED {image_path}: {exc}")
            continue

        result["ground_truth"] = ground_truth
        results.append(result)

        for slot in result["slots"]:
            bbox_total += 1
            if slot["bbox_well_formed"]:
                bbox_well_formed_total += 1

        if ground_truth and len(result["slots"]) == len(ground_truth):
            pred = [slot["top"] for slot in result["slots"]]
            for p, g in zip(pred, ground_truth):
                tile_total += 1
                if p == g:
                    tile_correct += 1

        print(f"{image_path}: slots={result['slots_count']} bbox_ok={sum(s['bbox_well_formed'] for s in result['slots'])}/{result['slots_count']}")

    results_path = out_dir / "results.json"
    results_path.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")

    print()
    print(f"cases_total={len(tasks)} cases_failed={sum(1 for r in results if 'error' in r)}")
    if bbox_total:
        print(f"bbox_format_valid_rate={(bbox_well_formed_total / bbox_total) * 100:.1f}% ({bbox_well_formed_total}/{bbox_total})")
    if tile_total:
        print(f"tile_accuracy_with_bbox_prompt={(tile_correct / tile_total) * 100:.1f}% ({tile_correct}/{tile_total})")
    print(f"annotated overlays + raw results written to {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
