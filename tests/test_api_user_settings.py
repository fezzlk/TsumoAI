from fastapi.testclient import TestClient

from app.auth import get_current_user
from app.main import app, user_settings_store


client = TestClient(app)


class FakeUserSettingsStore:
    def __init__(self):
        self.items = {}

    def get(self, uid, name):
        assert uid == "user-1"
        return self.items.get(name)

    def upsert(self, uid, name, data):
        assert uid == "user-1"
        stored = {**data, "updated_at": "2026-09-29T00:00:00Z"}
        self.items[name] = stored
        return stored


def test_mahjong_rule_settings_are_scoped_to_authenticated_account(monkeypatch):
    fake = FakeUserSettingsStore()
    monkeypatch.setattr(user_settings_store, "get", fake.get)
    monkeypatch.setattr(user_settings_store, "upsert", fake.upsert)
    app.dependency_overrides[get_current_user] = lambda: {"uid": "user-1"}
    payload = {
        "version": 1,
        "rules": {
            "aka_ari": True,
            "kuitan_ari": False,
            "double_yakuman_ari": True,
            "kazoe_yakuman_ari": False,
            "renpu_fu": 2,
        },
        "tobi_end": True,
        "chips_enabled": True,
        "open_hand_chips_enabled": True,
    }
    try:
        missing = client.get("/api/v1/settings/mahjong-rules")
        assert missing.status_code == 404

        saved = client.put("/api/v1/settings/mahjong-rules", json=payload)
        assert saved.status_code == 200
        assert saved.json()["rules"]["kuitan_ari"] is False
        assert saved.json()["chips_enabled"] is True

        loaded = client.get("/api/v1/settings/mahjong-rules")
        assert loaded.status_code == 200
        assert loaded.json() == saved.json()
    finally:
        app.dependency_overrides.clear()


def test_mahjong_rule_settings_require_authentication():
    response = client.get("/api/v1/settings/mahjong-rules")
    assert response.status_code == 401
