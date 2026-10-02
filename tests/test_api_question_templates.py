from fastapi.testclient import TestClient

from app.auth import get_current_user
from app.main import app, question_template_store


client = TestClient(app)


class FakeQuestionTemplateStore:
    def __init__(self):
        self.items = {}

    def list(self, uid):
        assert uid == "user-1"
        return list(self.items.values())

    def upsert(self, uid, item_id, data):
        assert uid == "user-1"
        stored = {
            **data,
            "id": item_id,
            "created_at": data.get("created_at") or "2026-09-29T00:00:00Z",
            "updated_at": "2026-09-29T00:00:01Z",
        }
        self.items[item_id] = stored
        return stored

    def delete(self, uid, item_id):
        assert uid == "user-1"
        self.items.pop(item_id, None)


def test_question_templates_can_be_saved_deduplicated_and_deleted(monkeypatch):
    fake = FakeQuestionTemplateStore()
    monkeypatch.setattr(question_template_store, "list", fake.list)
    monkeypatch.setattr(question_template_store, "upsert", fake.upsert)
    monkeypatch.setattr(question_template_store, "delete", fake.delete)
    app.dependency_overrides[get_current_user] = lambda: {"uid": "user-1"}
    first_id = "f326bb37-6e89-46db-a95b-fb763ac8936a"
    second_id = "b92bd234-1df0-4c25-b2a3-6d7cb6588cad"
    payload = {"name": "親リーチ", "body": "親リーチ中なら何を切る？"}
    try:
        saved = client.put(f"/api/v1/question-templates/{first_id}", json=payload)
        assert saved.status_code == 200

        duplicate = client.put(f"/api/v1/question-templates/{second_id}", json=payload)
        assert duplicate.status_code == 200
        assert duplicate.json()["id"] == first_id
        assert len(fake.items) == 1

        listed = client.get("/api/v1/question-templates")
        assert listed.status_code == 200
        assert listed.json()["items"][0]["body"] == payload["body"]

        deleted = client.delete(f"/api/v1/question-templates/{first_id}")
        assert deleted.status_code == 204
        assert fake.items == {}
    finally:
        app.dependency_overrides.clear()


def test_question_templates_require_authentication():
    response = client.get("/api/v1/question-templates")
    assert response.status_code == 401
