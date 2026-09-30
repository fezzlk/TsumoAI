from types import SimpleNamespace

import pytest

from app.ai_chat import AIChatUnavailableError, answer_ai_chat
from app.schemas import AIChatRequest


def _request() -> AIChatRequest:
    return AIChatRequest.model_validate(
        {
            "message": "何を切る？",
            "conversation": [{"role": "user", "content": "守備も考えて"}],
            "context": {
                "purpose": "discard",
                "tiles": ["1m", "2m", "3m", "E"],
                "round_context": {"round_wind": "E"},
                "analysis": {"discards": [{"discard": "E"}]},
                "situation_tags": ["守備優先"],
            },
        }
    )


def test_answer_ai_chat_sends_structured_context():
    captured = {}

    class Completions:
        def create(self, **kwargs):
            captured.update(kwargs)
            return SimpleNamespace(
                choices=[
                    SimpleNamespace(
                        message=SimpleNamespace(content=" 東を切るのがおすすめです。 ")
                    )
                ]
            )

    client = SimpleNamespace(chat=SimpleNamespace(completions=Completions()))

    answer = answer_ai_chat(_request(), client=client)

    assert answer == "東を切るのがおすすめです。"
    assert captured["max_completion_tokens"] == 500
    assert '"purpose":"discard"' in captured["messages"][1]["content"]
    assert '"question":"何を切る？"' in captured["messages"][1]["content"]


def test_answer_ai_chat_rejects_empty_response():
    client = SimpleNamespace(
        chat=SimpleNamespace(
            completions=SimpleNamespace(
                create=lambda **kwargs: SimpleNamespace(
                    choices=[SimpleNamespace(message=SimpleNamespace(content="  "))]
                )
            )
        )
    )

    with pytest.raises(AIChatUnavailableError, match="empty"):
        answer_ai_chat(_request(), client=client)
