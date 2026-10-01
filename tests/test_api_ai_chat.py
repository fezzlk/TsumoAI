from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient

import app.main as main_module
from app.ai_usage_store import AIUsageLimitReached, AIUsageReservation
from app.auth import get_optional_user


client = TestClient(main_module.app)
INSTALL_HEADERS = {"X-TsumoAI-Install-ID": "test-install-0001"}


class FakeUsageStore:
    def __init__(self, *, used=0, limit=3):
        self.used = used
        self.limit = limit
        self.refunds = []
        self.subjects = []

    def _status(self):
        return {
            "period": "2026-10",
            "plan": "free",
            "included_limit": self.limit,
            "included_used": self.used,
            "bonus_remaining": 0,
            "remaining": max(0, self.limit - self.used),
            "resets_at": datetime(2026, 11, 1, tzinfo=timezone.utc),
        }

    def get_status(self, subject):
        self.subjects.append(subject)
        return self._status()

    def consume(self, subject):
        self.subjects.append(subject)
        if self.used >= self.limit:
            raise AIUsageLimitReached(self._status())
        self.used += 1
        return AIUsageReservation(status=self._status(), source="included")

    def refund(self, subject, source):
        self.refunds.append((subject, source))
        self.used = max(0, self.used - 1)


@pytest.fixture(autouse=True)
def fake_usage_store(monkeypatch):
    store = FakeUsageStore()
    monkeypatch.setattr(main_module, "ai_usage_store", store)
    main_module._ai_chat_rate_windows.clear()
    yield store
    main_module.app.dependency_overrides.clear()


def _payload():
    return {
        "message": "親リーチ中なら何を切る？",
        "conversation": [],
        "context": {
            "purpose": "discard",
            "tiles": [
                "1m", "2m", "3m", "4m", "5m", "6m", "2p",
                "3p", "4p", "5s", "6s", "7s", "E", "E",
            ],
            "round_context": {"round_wind": "E", "seat_wind": "S"},
            "analysis": {"discards": [{"discard": "E"}]},
            "situation_tags": ["親リーチ", "守備優先"],
        },
    }


def test_ai_chat_returns_coaching_answer(monkeypatch):
    monkeypatch.setattr(
        main_module,
        "answer_ai_chat",
        lambda request: "東を切って安全を優先します。",
    )

    response = client.post(
        "/api/v1/ai-chat", json=_payload(), headers=INSTALL_HEADERS
    )

    assert response.status_code == 200
    assert response.json()["answer"] == "東を切って安全を優先します。"
    assert response.json()["usage"]["remaining"] == 2


def test_ai_chat_rejects_invalid_context():
    payload = _payload()
    payload["context"]["purpose"] = "score"

    response = client.post(
        "/api/v1/ai-chat", json=payload, headers=INSTALL_HEADERS
    )

    assert response.status_code == 422


def test_ai_chat_reports_unavailable_model(monkeypatch):
    def unavailable(request):
        raise main_module.AIChatUnavailableError("OPENAI_API_KEY is not configured")

    monkeypatch.setattr(main_module, "answer_ai_chat", unavailable)

    response = client.post(
        "/api/v1/ai-chat", json=_payload(), headers=INSTALL_HEADERS
    )

    assert response.status_code == 503


def test_ai_chat_refunds_usage_when_model_fails(monkeypatch, fake_usage_store):
    monkeypatch.setattr(
        main_module,
        "answer_ai_chat",
        lambda request: (_ for _ in ()).throw(RuntimeError("model failed")),
    )

    response = client.post(
        "/api/v1/ai-chat", json=_payload(), headers=INSTALL_HEADERS
    )

    assert response.status_code == 502
    assert fake_usage_store.used == 0
    assert fake_usage_store.refunds == [("install:test-install-0001", "included")]


def test_ai_chat_rejects_when_monthly_allowance_is_empty(
    monkeypatch, fake_usage_store
):
    fake_usage_store.used = fake_usage_store.limit
    monkeypatch.setattr(main_module, "answer_ai_chat", lambda request: "unused")

    response = client.post(
        "/api/v1/ai-chat", json=_payload(), headers=INSTALL_HEADERS
    )

    assert response.status_code == 429
    assert response.json()["detail"]["code"] == "monthly_ai_limit_reached"
    assert response.json()["detail"]["usage"]["remaining"] == 0


def test_ai_usage_status_is_available_before_opening_chat():
    response = client.get("/api/v1/ai-chat/usage", headers=INSTALL_HEADERS)

    assert response.status_code == 200
    assert response.json()["included_limit"] == 3
    assert response.json()["remaining"] == 3


def test_anonymous_ai_usage_requires_install_id():
    response = client.get("/api/v1/ai-chat/usage")

    assert response.status_code == 400


def test_logged_in_usage_uses_verified_uid_without_install_id(fake_usage_store):
    main_module.app.dependency_overrides[get_optional_user] = lambda: {
        "uid": "member-1"
    }

    response = client.get("/api/v1/ai-chat/usage")

    assert response.status_code == 200
    assert fake_usage_store.subjects == ["user:member-1"]
