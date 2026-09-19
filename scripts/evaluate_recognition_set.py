#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path

from PIL import Image

try:  # pragma: no cover
    from pillow_heif import register_heif_opener

    register_heif_opener()
except Exception:  # pragma: no cover
    pass

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from app import tile_recognizer_local
from app.validators import validate_tile


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Evaluate recognition accuracy on labeled eval set.")
    p.add_argument("--input", default="data/recognition_eval_set.jsonl", help="Eval JSONL path")
    p.add_argument("--top", type=int, default=20, help="Top confusion pairs to print")
    p.add_argument(
        "--mode",
        choices=("local", "pipeline"),
        default="local",
        help="local evaluates only TFLite; pipeline may use the configured OpenAI fallback",
    )
    p.add_argument("--model", type=Path, help="TFLite model to evaluate instead of ml/output")
    p.add_argument("--labels", type=Path, help="labels.txt paired with --model")
    p.add_argument(
        "--allow-paid-fallback",
        action="store_true",
        help="required with --mode pipeline because it may call the paid OpenAI API",
    )
    p.add_argument(
        "--record",
        action="store_true",
        help="Save the resulting metrics to GCS (recognition-accuracy) for the dashboard's accuracy-over-time chart.",
    )
    return p.parse_args()


def _configure_model(model_path: Path | None, labels_path: Path | None) -> tuple[Path, Path]:
    if (model_path is None) != (labels_path is None):
        raise ValueError("--model and --labels must be provided together")
    if model_path is not None and labels_path is not None:
        if not model_path.is_file():
            raise ValueError(f"model not found: {model_path}")
        if not labels_path.is_file():
            raise ValueError(f"labels not found: {labels_path}")
        tile_recognizer_local._TFLITE_PATH = model_path
        tile_recognizer_local._LABELS_PATH = labels_path
        tile_recognizer_local._interpreter = None
        tile_recognizer_local._labels = []
    return tile_recognizer_local._TFLITE_PATH, tile_recognizer_local._LABELS_PATH


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _load_rows(path: Path) -> list[dict]:
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


def _to_jpeg_bytes(image_path: Path) -> bytes:
    with Image.open(image_path) as img:
        rgb = img.convert("RGB")
        out = BytesIO()
        rgb.save(out, format="JPEG", quality=95)
        return out.getvalue()


def _validate_gt(gt: list[str]) -> bool:
    if len(gt) != 14:
        return False
    try:
        for t in gt:
            validate_tile(t)
    except Exception:
        return False
    return True


def main() -> int:
    args = parse_args()
    if args.mode == "pipeline" and not args.allow_paid_fallback:
        print("--mode pipeline requires --allow-paid-fallback because OpenAI API calls may incur cost")
        return 2
    try:
        model_path, labels_path = _configure_model(args.model, args.labels)
    except ValueError as exc:
        print(exc)
        return 2

    model_info = {
        "mode": args.mode,
        "model_path": str(model_path),
        "model_sha256": _sha256(model_path),
        "labels_path": str(labels_path),
        "labels_sha256": _sha256(labels_path),
    }
    print("model=" + json.dumps(model_info, ensure_ascii=False))
    rows = _load_rows(Path(args.input))
    if not rows:
        print(f"no rows found: {args.input}")
        return 1

    valid_rows = [r for r in rows if _validate_gt(r.get("corrected_tiles", []))]
    if not valid_rows:
        print("no labeled rows (corrected_tiles length must be 14)")
        return 1

    tile_total = 0
    tile_correct = 0
    exact_total = 0
    exact_correct = 0
    confusion: dict[tuple[str, str], int] = {}
    failed_cases = 0
    failure_reasons: Counter[str] = Counter()

    for row in valid_rows:
        image_path = Path(row["image_path"])
        if not image_path.exists():
            failed_cases += 1
            failure_reasons["missing_image"] += 1
            continue

        try:
            image_bytes = _to_jpeg_bytes(image_path)
            payload = (
                tile_recognizer_local.recognize_tiles_local(image_bytes)
                if args.mode == "local"
                else _extract_with_pipeline(image_bytes)
            )
            if payload is None:
                failed_cases += 1
                failure_reasons["recognizer_returned_none"] += 1
                continue
            pred = [slot["top"] for slot in payload.get("slots", [])]
        except Exception as exc:
            failed_cases += 1
            failure_reasons[f"exception.{type(exc).__name__}"] += 1
            continue

        gt = row["corrected_tiles"]
        if len(pred) != 14:
            failed_cases += 1
            failure_reasons[f"predicted_tile_count.{len(pred)}"] += 1
            continue

        exact_total += 1
        if pred == gt:
            exact_correct += 1

        for p, g in zip(pred, gt):
            tile_total += 1
            if p == g:
                tile_correct += 1
            else:
                confusion[(g, p)] = confusion.get((g, p), 0) + 1

    if exact_total == 0 or tile_total == 0:
        print(f"failure_reasons={dict(sorted(failure_reasons.items()))}")
        print("evaluation failed: no successful cases")
        return 1

    tile_accuracy = tile_correct / tile_total
    exact_match_rate = exact_correct / exact_total
    recognition_success_rate = exact_total / len(valid_rows)
    full_set_exact_match_rate = exact_correct / len(valid_rows)
    full_set_tile_accuracy = tile_correct / (len(valid_rows) * 14)

    print(f"cases_total={len(valid_rows)} cases_scored={exact_total} cases_failed={failed_cases}")
    print(f"failure_reasons={dict(sorted(failure_reasons.items()))}")
    print(f"recognition_success_rate={recognition_success_rate * 100:.2f}%")
    print(f"tile_accuracy_scored_cases={tile_accuracy * 100:.2f}%")
    print(f"tile_accuracy_all_cases={full_set_tile_accuracy * 100:.2f}%")
    print(f"exact_match_rate_scored_cases={exact_match_rate * 100:.2f}%")
    print(f"exact_match_rate_all_cases={full_set_exact_match_rate * 100:.2f}%")
    print("top confusions (ground_truth -> predicted):")
    for (g, p), c in sorted(confusion.items(), key=lambda x: x[1], reverse=True)[: args.top]:
        print(f"{g:>3} -> {p:<3} : {c}")

    if args.record:
        from app.config import settings
        from app.gcs_feedback_store import GCSFeedbackStore

        store = GCSFeedbackStore(prefix=settings.gcs_accuracy_prefix)
        result = store.save({
            "evaluated_at": datetime.now(timezone.utc).isoformat(),
            "tile_accuracy": tile_accuracy,
            "exact_match_rate": exact_match_rate,
            "n": exact_total,
            "cases_total": len(valid_rows),
            "cases_failed": failed_cases,
            "failure_reasons": dict(failure_reasons),
            "recognition_success_rate": recognition_success_rate,
            "full_set_tile_accuracy": full_set_tile_accuracy,
            "full_set_exact_match_rate": full_set_exact_match_rate,
            **model_info,
        })
        print(f"recorded: {result}")

    return 0


def _extract_with_pipeline(image_bytes: bytes) -> dict | None:
    # Import only after the caller explicitly accepted the possibility of a
    # paid fallback. Local model evaluation must remain independent of the
    # OpenAI client and cloud recording dependencies.
    from app.hand_extraction import extract_hand_from_image

    return extract_hand_from_image(image_bytes)


if __name__ == "__main__":
    raise SystemExit(main())
