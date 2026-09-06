#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from app.interpretation.interpreter import interpret_observations  # noqa: E402
from app.interpretation.models import InterpretationRequest  # noqa: E402


def load_rows(path: Path) -> list[dict[str, Any]]:
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    for row in rows:
        missing = {"case_id", "schema_version", "request", "expected"} - row.keys()
        if missing:
            raise ValueError(f"evaluation row is missing fields {sorted(missing)}: {row.get('case_id')}")
        if row["schema_version"] != "1":
            raise ValueError(f"unsupported schema_version: {row['schema_version']}")
    return rows


def evaluate_rows(rows: list[dict[str, Any]]) -> dict[str, Any]:
    failures: list[str] = []
    false_auto_confirm = 0
    passed = 0

    for row in rows:
        case_id = row["case_id"]
        expected = row["expected"]
        try:
            request = InterpretationRequest.model_validate(row["request"])
            result = interpret_observations(request)
        except (ValueError, TypeError) as exc:
            error_contains = expected.get("error_contains")
            if error_contains and error_contains in str(exc):
                passed += 1
            else:
                failures.append(f"{case_id}: unexpected error: {exc}")
            continue

        if "error_contains" in expected:
            failures.append(f"{case_id}: expected error containing {expected['error_contains']!r}")
            continue

        actual_winning_status = result.winning_tile.status.value
        expected_winning_status = expected["winning_status"]
        actual_meld_statuses = [meld.status.value for meld in result.melds]
        expected_meld_statuses = expected.get("meld_statuses", [])

        if expected_winning_status != "confirmed" and actual_winning_status == "confirmed":
            false_auto_confirm += 1
        false_auto_confirm += sum(
            actual == "confirmed"
            and (index >= len(expected_meld_statuses) or expected_meld_statuses[index] != "confirmed")
            for index, actual in enumerate(actual_meld_statuses)
        )

        checks = [
            (actual_winning_status == expected_winning_status, "winning_status"),
            (
                result.winning_tile.observation_id == expected.get("winning_observation_id"),
                "winning_observation_id",
            ),
            (actual_meld_statuses == expected_meld_statuses, "meld_statuses"),
        ]
        if "requires_user_confirmation" in expected:
            checks.append(
                (
                    result.requires_user_confirmation == expected["requires_user_confirmation"],
                    "requires_user_confirmation",
                )
            )
        failed_fields = [name for ok, name in checks if not ok]
        if failed_fields:
            failures.append(f"{case_id}: mismatched {', '.join(failed_fields)}")
        else:
            passed += 1

    return {
        "cases": len(rows),
        "passed": passed,
        "failed": len(failures),
        "false_auto_confirm": false_auto_confirm,
        "failures": failures,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate deterministic interpretation cases.")
    parser.add_argument("--input", type=Path, default=ROOT / "data/interpretation_eval_set.jsonl")
    args = parser.parse_args()
    metrics = evaluate_rows(load_rows(args.input))
    print(json.dumps(metrics, ensure_ascii=False, indent=2))
    return 0 if metrics["failed"] == 0 and metrics["false_auto_confirm"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
