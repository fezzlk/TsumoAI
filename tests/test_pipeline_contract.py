from __future__ import annotations

import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.hand_analysis import analyze_discard_options, analyze_tenpai
from app.interpretation.interpreter import interpret_observations
from app.interpretation.models import InterpretationRequest
from app.main import app
from app.schemas import DiscardAnalysisRequest, TenpaiAnalysisRequest
from scripts.evaluate_domain_analysis_set import evaluate_rows as evaluate_domain_rows
from scripts.evaluate_domain_analysis_set import load_rows as load_domain_rows
from scripts.evaluate_interpretation_set import evaluate_rows as evaluate_interpretation_rows
from scripts.evaluate_interpretation_set import load_rows as load_interpretation_rows

ROOT = Path(__file__).resolve().parent.parent
INTERPRETATION_CASES = load_interpretation_rows(ROOT / "data/interpretation_eval_set.jsonl")
DOMAIN_CASES = load_domain_rows(ROOT / "data/domain_analysis_eval_set.jsonl")
CONTRACT_FIXTURES = ROOT / "tests/fixtures/contracts"
client = TestClient(app)


def test_versioned_contract_fixtures_are_valid_json():
    for name in ("observation-v1.json", "confirmation-v1.json", "confirmed-hand-state-v1.json"):
        payload = json.loads((CONTRACT_FIXTURES / name).read_text(encoding="utf-8"))
        assert payload["schema_version"] == "1"


def test_evaluation_rows_have_required_versioned_fields():
    for row in [*INTERPRETATION_CASES, *DOMAIN_CASES]:
        assert row["case_id"]
        assert row["schema_version"] == "1"
        assert isinstance(row["expected"], dict)


def test_interpretation_offline_metrics_are_safe():
    metrics = evaluate_interpretation_rows(INTERPRETATION_CASES)
    assert metrics["failures"] == []
    assert metrics["false_auto_confirm"] == 0


@pytest.mark.parametrize("case", INTERPRETATION_CASES, ids=lambda case: case["case_id"])
def test_interpretation_function_and_api_contract(case):
    expected = case["expected"]
    if "error_contains" in expected:
        request = InterpretationRequest.model_validate(case["request"])
        with pytest.raises(ValueError, match=expected["error_contains"]):
            interpret_observations(request)
        response = client.post("/api/v1/interpretations", json=case["request"])
        assert response.status_code == 422
        assert expected["error_contains"] in response.json()["detail"]
        return

    direct = interpret_observations(InterpretationRequest.model_validate(case["request"]))
    response = client.post("/api/v1/interpretations", json=case["request"])
    assert response.status_code == 200
    assert response.json() == direct.model_dump(mode="json")


def test_domain_offline_metrics_pass():
    metrics = evaluate_domain_rows(DOMAIN_CASES)
    assert metrics["failures"] == []


@pytest.mark.parametrize("case", DOMAIN_CASES, ids=lambda case: case["case_id"])
def test_domain_function_and_api_contract(case):
    expected = case["expected"]
    if case["operation"] == "tenpai":
        request = TenpaiAnalysisRequest.model_validate(case["request"])
        call = lambda: analyze_tenpai(request)
        endpoint = "/api/v1/tenpai/analyze"
    else:
        request = DiscardAnalysisRequest.model_validate(case["request"])
        call = lambda: analyze_discard_options(request)
        endpoint = "/api/v1/discards/analyze"

    if expected["status"] == "error":
        with pytest.raises(ValueError, match=expected["error_contains"]):
            call()
        response = client.post(endpoint, json=case["request"])
        assert response.status_code == 422
        assert expected["error_contains"] in response.json()["detail"]
        return

    direct = call()
    response = client.post(endpoint, json=case["request"])
    assert response.status_code == 200
    assert response.json() == direct.model_dump(mode="json")
