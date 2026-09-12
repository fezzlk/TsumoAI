#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from app.hand_analysis import analyze_discard_options, analyze_tenpai  # noqa: E402
from app.schemas import DiscardAnalysisRequest, TenpaiAnalysisRequest  # noqa: E402


def load_rows(path: Path) -> list[dict[str, Any]]:
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    for row in rows:
        missing = {"case_id", "schema_version", "operation", "request", "expected"} - row.keys()
        if missing:
            raise ValueError(f"evaluation row is missing fields {sorted(missing)}: {row.get('case_id')}")
        if row["schema_version"] != "1":
            raise ValueError(f"unsupported schema_version: {row['schema_version']}")
        if row["operation"] not in {"tenpai", "discard_analysis"}:
            raise ValueError(f"unsupported operation: {row['operation']}")
    return rows


def run_case(row: dict[str, Any]) -> dict[str, Any]:
    if row["operation"] == "tenpai":
        request = TenpaiAnalysisRequest.model_validate(row["request"])
        return analyze_tenpai(request).model_dump(mode="json")
    request = DiscardAnalysisRequest.model_validate(row["request"])
    return analyze_discard_options(request).model_dump(mode="json")


def evaluate_rows(rows: list[dict[str, Any]]) -> dict[str, Any]:
    failures: list[str] = []
    passed = 0
    for row in rows:
        case_id = row["case_id"]
        expected = row["expected"]
        try:
            result = run_case(row)
        except (ValueError, TypeError) as exc:
            if expected.get("status") == "error" and expected.get("error_contains", "") in str(exc):
                passed += 1
            else:
                failures.append(f"{case_id}: unexpected error: {exc}")
            continue

        if expected.get("status") == "error":
            failures.append(f"{case_id}: expected error containing {expected.get('error_contains')!r}")
            continue

        failed_fields: list[str] = []
        if "shanten" in expected and result["shanten"] != expected["shanten"]:
            failed_fields.append("shanten")
        waits = {item["tile"] for item in result.get("improving_tiles", [])}
        if not set(expected.get("improving_tiles_include", [])).issubset(waits):
            failed_fields.append("improving_tiles_include")
        discards = {item["discard"] for item in result.get("discards", [])}
        if not set(expected.get("discards_include", [])).issubset(discards):
            failed_fields.append("discards_include")
        if failed_fields:
            failures.append(f"{case_id}: mismatched {', '.join(failed_fields)}")
        else:
            passed += 1
    return {"cases": len(rows), "passed": passed, "failed": len(failures), "failures": failures}


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate deterministic hand-analysis cases.")
    parser.add_argument("--input", type=Path, default=ROOT / "data/domain_analysis_eval_set.jsonl")
    args = parser.parse_args()
    metrics = evaluate_rows(load_rows(args.input))
    print(json.dumps(metrics, ensure_ascii=False, indent=2))
    return 0 if metrics["failed"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
