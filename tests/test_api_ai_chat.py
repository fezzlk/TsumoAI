from fastapi.testclient import TestClient

import app.main as main_module


client = TestClient(main_module.app)


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

    response = client.post("/api/v1/ai-chat", json=_payload())

    assert response.status_code == 200
    assert response.json() == {"answer": "東を切って安全を優先します。"}


def test_ai_chat_rejects_invalid_context():
    payload = _payload()
    payload["context"]["purpose"] = "score"

    response = client.post("/api/v1/ai-chat", json=payload)

    assert response.status_code == 422


def test_ai_chat_reports_unavailable_model(monkeypatch):
    def unavailable(request):
        raise main_module.AIChatUnavailableError("OPENAI_API_KEY is not configured")

    monkeypatch.setattr(main_module, "answer_ai_chat", unavailable)

    response = client.post("/api/v1/ai-chat", json=_payload())

    assert response.status_code == 503
