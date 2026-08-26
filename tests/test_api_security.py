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


def test_oversized_recognition_image_is_rejected(monkeypatch):
    from app import main
    monkeypatch.setattr(main.settings, "max_image_bytes", 3)
    response = client.post(
        "/api/v1/recognize",
        files={"image": ("hand.jpg", b"four", "image/jpeg")},
    )
    assert response.status_code == 413


def test_terms_page_is_public():
    response = client.get("/terms")
    assert response.status_code == 200
    assert "利用規約" in response.text
    assert "免責事項" in response.text


def test_privacy_page_is_public():
    response = client.get("/privacy")
    assert response.status_code == 200
    assert "プライバシーポリシー" in response.text
    assert "DELETE /api/v1/me/data" in response.text


def test_delete_my_data_requires_login():
    response = client.delete("/api/v1/me/data")
    assert response.status_code == 401


def test_delete_my_data_deletes_across_all_stores(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"uid": "member-1"}
    from app import main
    monkeypatch.setattr(main.training_data_store, "delete_by_uid", lambda uid: 2 if uid == "member-1" else 0)
    monkeypatch.setattr(main.gcs_feedback_store, "delete_by_uid", lambda uid: 1 if uid == "member-1" else 0)
    monkeypatch.setattr(main.recognition_feedback_store, "delete_by_uid", lambda uid: 3 if uid == "member-1" else 0)
    monkeypatch.setattr(main.gcs_dataset_store, "delete_by_uid", lambda uid: 0)
    response = client.delete("/api/v1/me/data")
    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "deleted_training_data": 2,
        "deleted_score_feedback": 1,
        "deleted_recognition_feedback": 3,
        "deleted_dataset_uploads": 0,
    }
