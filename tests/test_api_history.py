from fastapi.testclient import TestClient

from app.auth import get_current_user
from app.main import app, history_store


client = TestClient(app)


class FakeHistoryStore:
    def __init__(self):
        self.items = {}

    def list(self, uid, limit=200):
        assert uid == "user-1"
        return list(self.items.values())[:limit]

    def upsert(self, uid, item_id, data):
        stored = {
            **data,
            "id": item_id,
            "updated_at": "2026-09-22T00:00:01Z",
            "account_uid": uid,
        }
        self.items[item_id] = stored
        return stored

    def delete_all(self, uid):
        count = len(self.items)
        self.items.clear()
        return count


def test_history_is_scoped_to_authenticated_account(monkeypatch):
    fake = FakeHistoryStore()
    monkeypatch.setattr(history_store, "list", fake.list)
    monkeypatch.setattr(history_store, "upsert", fake.upsert)
    monkeypatch.setattr(history_store, "delete_all", fake.delete_all)
    app.dependency_overrides[get_current_user] = lambda: {"uid": "user-1"}
    item_id = "f326bb37-6e89-46db-a95b-fb763ac8936a"
    payload = {
        "created_at": "2026-09-22T00:00:00Z",
        "purpose": "score",
        "title": "点数計算",
        "summary": "3翻40符 5200点",
        "round_label": "東2局 1本場",
        "details": {"han": 3, "fu": 40},
    }
    try:
        saved = client.put(f"/api/v1/history/{item_id}", json=payload)
        assert saved.status_code == 200
        assert saved.json()["id"] == item_id

        listed = client.get("/api/v1/history")
        assert listed.status_code == 200
        assert listed.json()["items"][0]["summary"] == "3翻40符 5200点"

        deleted = client.delete("/api/v1/history")
        assert deleted.status_code == 200
        assert deleted.json() == {"deleted_count": 1}
    finally:
        app.dependency_overrides.clear()


def test_history_requires_authentication():
    response = client.get("/api/v1/history")
    assert response.status_code == 401
