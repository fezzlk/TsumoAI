from __future__ import annotations

import json
from typing import Any

from openai import OpenAI

from app.config import settings
from app.schemas import AIChatRequest


SYSTEM_PROMPT = """あなたは日本のリーチ麻雀を教えるコーチです。
初心者にも分かる短い日本語で答えてください。
提示された手牌、局情報、アプリの解析結果だけを根拠にしてください。
捨て牌、巡目、点数状況など不足している情報は推測で断定せず、条件を分けて説明してください。
最初に推奨行動を一文で示し、その後に理由と判断が変わる条件を説明してください。"""


class AIChatUnavailableError(RuntimeError):
    pass


def answer_ai_chat(request: AIChatRequest, *, client: Any | None = None) -> str:
    if client is None:
        if not settings.openai_api_key:
            raise AIChatUnavailableError("OPENAI_API_KEY is not configured")
        client = OpenAI(api_key=settings.openai_api_key)

    payload = {
        "context": request.context.model_dump(mode="json"),
        "conversation": [
            message.model_dump(mode="json") for message in request.conversation
        ],
        "question": request.message,
    }
    response = client.chat.completions.create(
        model=settings.openai_model,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "user",
                "content": json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
            },
        ],
        temperature=0.2,
        max_completion_tokens=500,
    )
    answer = (response.choices[0].message.content or "").strip()
    if not answer:
        raise AIChatUnavailableError("AI returned an empty response")
    return answer
