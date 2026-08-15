#!/usr/bin/env python3
"""Compare tile-localization approaches on real phone photos.

Phase A of the recognition-engine rebuild (FEZ-87): before designing a new
pipeline, find out which of the two already-trained/implemented detectors
actually finds ~14 tiles on real photos:

  1. The classic-CV connected-components segmenter currently live in
     app/tile_recognizer_local.py (`_segment_tiles`).
  2. The trained-but-never-wired YOLOv8n detector in ml/yolo/.

Both are EXIF-corrected before detection so the comparison isn't polluted by
the orientation bug found elsewhere in the codebase.

This script does not modify app/ or mobile/, and does not train anything.
"""

from __future__ import annotations

import json
import statistics
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

import pillow_heif

pillow_heif.register_heif_opener()

BASE_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE_DIR))

from app.tile_recognizer_local import _segment_tiles  # noqa: E402

EVAL_SET_PATH = (
    (BASE_DIR / sys.argv[1]).resolve()
    if len(sys.argv) > 1
    else BASE_DIR / "data" / "recognition_eval_set.jsonl"
)
YOLO_WEIGHTS = BASE_DIR / "ml" / "yolo" / "runs" / "tile_detector" / "weights" / "best.pt"
REPORT_DIR = Path.home() / "ai-output" / "tsumoai" / "report"
TARGET_TILE_COUNT = 14


@dataclass
class CaseResult:
    case_id: str
    image_path: str
    cv_count: int
    yolo_count: int


def load_eval_cases() -> list[dict]:
    cases = []
    with EVAL_SET_PATH.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            cases.append(json.loads(line))
    return cases


def load_exif_safe_rgb(image_path: Path) -> np.ndarray:
    with Image.open(image_path) as img:
        img = ImageOps.exif_transpose(img)
        return np.array(img.convert("RGB"))


def run_cv_segmenter(rgb: np.ndarray) -> int:
    tiles = _segment_tiles(rgb)
    return len(tiles)


def run_yolo_detector(model, image_path: Path) -> int:
    results = model.predict(source=str(image_path), imgsz=640, conf=0.25, verbose=False)
    if not results:
        return 0
    return len(results[0].boxes)


def summarize(counts: list[int], label: str) -> str:
    exact = sum(1 for c in counts if c == TARGET_TILE_COUNT)
    mean = statistics.mean(counts) if counts else 0.0
    lines = [
        f"  {label}:",
        f"    14枚ちょうど検出: {exact}/{len(counts)}",
        f"    平均検出枚数: {mean:.1f}",
        f"    分布: {sorted(counts)}",
    ]
    return "\n".join(lines)


def main() -> None:
    cases = load_eval_cases()
    labeled_cases = [c for c in cases if len(c.get("corrected_tiles", [])) >= 14]

    print(f"評価対象: {len(labeled_cases)}件（ラベル付き実写真）")

    yolo_available = YOLO_WEIGHTS.exists()
    model = None
    if yolo_available:
        from ultralytics import YOLO

        model = YOLO(str(YOLO_WEIGHTS))
    else:
        print(f"警告: YOLO重みが見つかりません: {YOLO_WEIGHTS}")

    results: list[CaseResult] = []
    for case in labeled_cases:
        image_path = BASE_DIR / case["image_path"]
        rgb = load_exif_safe_rgb(image_path)

        cv_count = run_cv_segmenter(rgb)
        yolo_count = run_yolo_detector(model, image_path) if model is not None else -1

        results.append(
            CaseResult(
                case_id=case["case_id"],
                image_path=case["image_path"],
                cv_count=cv_count,
                yolo_count=yolo_count,
            )
        )
        print(
            f"  {case['case_id']}: CVセグメンター={cv_count}枚, "
            f"YOLO検出器={yolo_count if yolo_count >= 0 else 'N/A'}枚 "
            f"(正解=14枚, note={case.get('note', '')})"
        )

    cv_counts = [r.cv_count for r in results]
    yolo_counts = [r.yolo_count for r in results if r.yolo_count >= 0]

    report_lines = [
        "# TsumoAI 検出方式比較レポート（Phase A）",
        "",
        f"実行日時: {datetime.now().isoformat(timespec='seconds')}",
        f"評価対象: {len(labeled_cases)}件（`{EVAL_SET_PATH.relative_to(BASE_DIR)}`のラベル付きケース）",
        "全ケースでEXIF回転補正（PIL.ImageOps.exif_transpose）を適用済み。",
        "",
        "## ケース別結果",
        "",
    ]
    for r in results:
        report_lines.append(
            f"- {r.case_id} (`{r.image_path}`): "
            f"CVセグメンター={r.cv_count}枚, "
            f"YOLO検出器={r.yolo_count if r.yolo_count >= 0 else 'N/A'}枚 "
            f"(正解=14枚)"
        )

    report_lines += [
        "",
        "## 集計",
        "",
        summarize(cv_counts, "CVセグメンター（app/tile_recognizer_local.py、現行ライブ実装）"),
        "",
    ]
    if yolo_counts:
        report_lines.append(summarize(yolo_counts, "YOLO検出器（ml/yolo/、未配線の学習済みモデル）"))
    else:
        report_lines.append("  YOLO検出器: 重みファイルが見つからず未実施")

    report_text = "\n".join(report_lines) + "\n"

    print("\n" + report_text)

    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    report_path = REPORT_DIR / f"{datetime.now().strftime('%Y%m%d%H%M%S')}_tile-detector-comparison.md"
    report_path.write_text(report_text)
    print(f"レポート保存先: {report_path}")


if __name__ == "__main__":
    main()
