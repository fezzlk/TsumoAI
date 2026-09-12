from datetime import datetime, timezone
from types import SimpleNamespace

from fastapi.testclient import TestClient

from app.auth import get_current_user, require_admin
from app.main import app


client = TestClient(app)


def teardown_function():
    app.dependency_overrides.clear()


def test_feedback_requires_login():
    response = client.post("/api/v1/score/feedback", json={"comment": "test"})
    assert response.status_code == 401


def test_training_data_list_requires_admin():
    app.dependency_overrides[get_current_user] = lambda: {"uid": "member"}
    response = client.get("/api/v1/training-data/list")
    assert response.status_code == 403


def test_admin_dependency_allows_management_route(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    from app import main
    monkeypatch.setattr(main.training_data_store, "list_entries", lambda **_: [])
    monkeypatch.setattr(main.training_data_store, "get_stats", lambda: {})
    response = client.get("/api/v1/training-data/list")
    assert response.status_code == 200


def test_admin_can_update_training_data_label(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    from app import main
    monkeypatch.setattr(main.training_data_store, "update_tile_code", lambda entry_id, tile: True)
    response = client.patch("/api/v1/training-data/example?tile_code=9s")
    assert response.status_code == 200
    assert response.json() == {"status": "updated", "id": "example", "tile_code": "9s"}


def test_training_data_label_rejects_invalid_tile():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    response = client.patch("/api/v1/training-data/example?tile_code=10m")
    assert response.status_code == 422


def test_retraining_history_requires_admin():
    response = client.get("/api/v1/model/retraining-history")
    assert response.status_code == 401


def test_admin_can_list_regional_retraining_history(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    from app import main
    from google.cloud.devtools import cloudbuild_v1

    started = datetime(2026, 8, 27, 12, 7, 11, tzinfo=timezone.utc)
    finished = datetime(2026, 8, 27, 12, 31, 42, tzinfo=timezone.utc)
    build = SimpleNamespace(
        id="aa7f32cd-e5c8-44e4-8f04-48c478c193da",
        status=SimpleNamespace(name="SUCCESS"),
        tags=["tsumoai-model-training"],
        create_time=started,
        start_time=started,
        finish_time=finished,
        log_url="https://console.cloud.google.com/cloud-build/builds/example",
        failure_info=SimpleNamespace(detail=""),
    )
    captured = {}

    class FakeClient:
        def list_builds(self, request):
            captured.update(request)
            return [build]

    monkeypatch.setattr(main, "resolve_gcp_project", lambda: "tsumoai")
    monkeypatch.setattr(main.settings, "gcp_region", "asia-northeast1")
    monkeypatch.setattr(cloudbuild_v1, "CloudBuildClient", FakeClient)

    response = client.get("/api/v1/model/retraining-history")

    assert response.status_code == 200
    assert captured["parent"] == "projects/tsumoai/locations/asia-northeast1"
    assert response.json()["builds"][0]["status"] == "SUCCESS"
    assert response.json()["builds"][0]["duration_seconds"] == 1471


def test_oversized_recognition_image_is_rejected(monkeypatch):
    from app import main
    monkeypatch.setattr(main.settings, "max_image_bytes", 3)
    response = client.post(
        "/api/v1/recognize",
        files={"image": ("hand.jpg", b"four", "image/jpeg")},
    )
    assert response.status_code == 413
