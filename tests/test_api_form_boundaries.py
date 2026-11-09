"""Pin how multipart form/file boundary values reach the handlers.

FastAPI changes how empty form values, omitted fields and empty file parts
are treated across versions (FEZ-257). These tests fix the current behavior
so that a FastAPI upgrade which changes it fails loudly instead of silently
altering what the mobile/web clients' requests mean.

Up to FastAPI 0.115.8 an empty optional form value ("") reached the handler
as "". Since the upgrade to 0.136 it is treated as "not sent" and the
declared default (None) is used. The current clients never send empty values
for these fields: the web UI only appends game_id when it is set, and the
mobile client omits null fields and always sends non-empty versions.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import main as main_module
from app.auth import get_current_user
from app.main import app

client = TestClient(app)


def sample_image_bytes() -> bytes:
    return (Path(__file__).resolve().parents[1] / "app" / "static" / "tiles" / "Mpu1m.png").read_bytes()


def teardown_function():
    app.dependency_overrides.clear()
    main_module._recognition_rate_windows.clear()


@pytest.fixture
def captured_game_ids(monkeypatch):
    main_module._recognition_rate_windows.clear()
    monkeypatch.setattr(
        main_module,
        "extract_hand_from_image",
        lambda image_bytes, should_cancel=None: {"tiles_count": 0, "slots": [], "warnings": []},
    )
    seen: list = []
    original = main_module._build_recognize_response

    def spy(width, height, game_id, payload):
        seen.append(game_id)
        return original(width=width, height=height, game_id=game_id, payload=payload)

    monkeypatch.setattr(main_module, "_build_recognize_response", spy)
    return seen


@pytest.fixture
def captured_uploads(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"uid": "u-1"}
    calls: list[dict] = []

    def fake_upload(image_bytes, tile_code, source, **kwargs):
        calls.append({"tile_code": tile_code, "source": source, **kwargs})
        return {"id": "td-1", "image_path": "p"}

    monkeypatch.setattr(main_module.training_data_store, "upload", fake_upload)
    return calls


# ── /api/v1/recognize: game_id (optional Form) and image (required File) ──


def test_recognize_omitted_game_id_is_none(captured_game_ids):
    response = client.post("/api/v1/recognize", files={"image": ("hand.png", sample_image_bytes(), "image/png")})
    assert response.status_code == 200
    assert captured_game_ids == [None]


def test_recognize_game_id_value_is_passed_through(captured_game_ids):
    response = client.post(
        "/api/v1/recognize",
        files={"image": ("hand.png", sample_image_bytes(), "image/png")},
        data={"game_id": "g-1"},
    )
    assert response.status_code == 200
    assert captured_game_ids == ["g-1"]


def test_recognize_empty_game_id_is_treated_as_omitted(captured_game_ids):
    response = client.post(
        "/api/v1/recognize",
        files={"image": ("hand.png", sample_image_bytes(), "image/png")},
        data={"game_id": ""},
    )
    assert response.status_code == 200
    assert captured_game_ids == [None]


def test_recognize_without_image_part_is_422(captured_game_ids):
    response = client.post("/api/v1/recognize", data={"game_id": "g-1"})
    assert response.status_code == 422
    assert captured_game_ids == []


def test_recognize_empty_content_with_filename_reaches_handler_and_is_400(captured_game_ids):
    response = client.post("/api/v1/recognize", files={"image": ("hand.png", b"", "image/png")})
    assert response.status_code == 400
    assert "image is required" in response.json()["detail"]
    assert captured_game_ids == []


def test_recognize_file_part_without_filename_or_content_is_422(captured_game_ids):
    # Rejected by FastAPI request validation before the handler runs.
    response = client.post("/api/v1/recognize", files={"image": ("", b"", "application/octet-stream")})
    assert response.status_code == 422
    assert captured_game_ids == []


# ── /api/v1/training-data/upload: required/optional str and float Form fields ──


def _upload(data: dict):
    return client.post(
        "/api/v1/training-data/upload",
        files={"image": ("tile.png", sample_image_bytes(), "image/png")},
        data=data,
    )


def test_training_upload_omitted_optional_fields_use_defaults(captured_uploads):
    response = _upload({"tile_code": "1m"})
    assert response.status_code == 200
    call = captured_uploads[0]
    assert call["source"] == "user"
    assert call["predicted_tile_code"] is None
    assert call["predicted_confidence"] is None
    assert call["recognition_model_version"] is None


def test_training_upload_empty_optional_fields_are_treated_as_omitted(captured_uploads):
    response = _upload(
        {
            "tile_code": "1m",
            "predicted_tile_code": "",
            "predicted_confidence": "",
            "recognition_model_version": "",
            "recognition_model_source": "",
            "preprocessing_version": "",
        }
    )
    assert response.status_code == 200
    call = captured_uploads[0]
    assert call["predicted_tile_code"] is None
    assert call["predicted_confidence"] is None
    assert call["recognition_model_version"] is None
    assert call["recognition_model_source"] is None
    assert call["preprocessing_version"] is None


def test_training_upload_empty_source_falls_back_to_default(captured_uploads):
    response = _upload({"tile_code": "1m", "source": ""})
    assert response.status_code == 200
    assert captured_uploads[0]["source"] == "user"


def test_training_upload_missing_required_tile_code_is_422(captured_uploads):
    response = _upload({})
    assert response.status_code == 422
    assert captured_uploads == []


def test_training_upload_empty_required_tile_code_is_422(captured_uploads):
    response = _upload({"tile_code": ""})
    assert response.status_code == 422
    assert captured_uploads == []


def test_training_upload_non_numeric_confidence_is_422(captured_uploads):
    response = _upload({"tile_code": "1m", "predicted_confidence": "abc"})
    assert response.status_code == 422
    assert captured_uploads == []
