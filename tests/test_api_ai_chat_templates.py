from fastapi.testclient import TestClient

import app.main as main_module
from app.auth import require_admin


client = TestClient(main_module.app)


class _MemoryStore:
    def __init__(self):
        self.version = 3
        self.items = [
            {
                "id": "question-discard",
                "kind": "question",
                "purpose": "discard",
                "label": "何を切る？",
                "body": "何を切る？",
                "enabled": True,
                "sort_order": 0,
            }
        ]

    def get(self):
        return {"version": self.version, "items": self.items}

    def upsert(self, items):
        self.version += 1
        self.items = items
        return {"version": self.version, "items": self.items}


def test_official_templates_are_public_and_versioned(monkeypatch):
    store = _MemoryStore()
    monkeypatch.setattr(main_module, "ai_chat_template_store", store)

    response = client.get("/api/v1/ai-chat/templates")

    assert response.status_code == 200
    assert response.json()["version"] == 3
    assert response.json()["items"][0]["purpose"] == "discard"


def test_admin_can_publish_official_templates(monkeypatch):
    store = _MemoryStore()
    monkeypatch.setattr(main_module, "ai_chat_template_store", store)
    main_module.app.dependency_overrides[require_admin] = lambda: {
        "uid": "admin",
        "admin": True,
    }
    try:
        response = client.put(
            "/api/v1/ai-chat/templates",
            json={
                "items": [
                    {
                        "id": "situation-rank-up",
                        "kind": "situation",
                        "purpose": "all",
                        "label": "着順UP",
                        "body": "着順UP",
                        "enabled": False,
                        "sort_order": 2,
                    }
                ]
            },
        )
    finally:
        main_module.app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()["version"] == 4
    assert response.json()["items"][0]["enabled"] is False


def test_publish_rejects_duplicate_ids(monkeypatch):
    monkeypatch.setattr(main_module, "ai_chat_template_store", _MemoryStore())
    main_module.app.dependency_overrides[require_admin] = lambda: {
        "uid": "admin",
        "admin": True,
    }
    item = {
        "id": "duplicate",
        "kind": "question",
        "purpose": "discard",
        "label": "質問",
        "body": "質問です",
        "enabled": True,
        "sort_order": 0,
    }
    try:
        response = client.put(
            "/api/v1/ai-chat/templates",
            json={"items": [item, item]},
        )
    finally:
        main_module.app.dependency_overrides.clear()

    assert response.status_code == 422
