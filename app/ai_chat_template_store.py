from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from app.config import resolve_gcp_project


DEFAULT_AI_CHAT_TEMPLATES = [
    {"id": "situation-parent-riichi", "kind": "situation", "purpose": "all", "label": "親リーチ", "body": "親リーチ", "enabled": True, "sort_order": 0},
    {"id": "situation-all-last", "kind": "situation", "purpose": "all", "label": "オーラス", "body": "オーラス", "enabled": True, "sort_order": 1},
    {"id": "situation-leading", "kind": "situation", "purpose": "all", "label": "トップ目", "body": "トップ目", "enabled": True, "sort_order": 2},
    {"id": "situation-last", "kind": "situation", "purpose": "all", "label": "ラス目", "body": "ラス目", "enabled": True, "sort_order": 3},
    {"id": "situation-defense", "kind": "situation", "purpose": "all", "label": "守備優先", "body": "守備優先", "enabled": True, "sort_order": 4},
    {"id": "situation-value", "kind": "situation", "purpose": "all", "label": "打点優先", "body": "打点優先", "enabled": True, "sort_order": 5},
    {"id": "situation-keep-dora", "kind": "situation", "purpose": "all", "label": "ドラを残す", "body": "ドラを残す", "enabled": True, "sort_order": 6},
    {"id": "situation-rank-up", "kind": "situation", "purpose": "all", "label": "着順UP", "body": "着順UP", "enabled": True, "sort_order": 7},
    {"id": "question-discard", "kind": "question", "purpose": "discard", "label": "何を切る？", "body": "何を切る？", "enabled": True, "sort_order": 0},
    {"id": "question-push-fold", "kind": "question", "purpose": "discard", "label": "押す？降りる？", "body": "押すべきか、降りるべきか教えて", "enabled": True, "sort_order": 1},
    {"id": "question-discard-reason", "kind": "question", "purpose": "discard", "label": "理由を詳しく", "body": "おすすめの打牌と理由を詳しく教えて", "enabled": True, "sort_order": 2},
    {"id": "question-call", "kind": "question", "purpose": "call_advice", "label": "鳴くべき？", "body": "鳴くべき？", "enabled": True, "sort_order": 0},
    {"id": "question-skip-call", "kind": "question", "purpose": "call_advice", "label": "見送るべき？", "body": "見送るべき？", "enabled": True, "sort_order": 1},
    {"id": "question-call-condition", "kind": "question", "purpose": "call_advice", "label": "判断が変わる条件は？", "body": "鳴き判断が変わる条件を教えて", "enabled": True, "sort_order": 2},
]


class AIChatTemplateStore:
    def __init__(self) -> None:
        self._client = None

    def _firestore(self):
        if self._client is None:
            from google.cloud import firestore

            self._client = firestore.Client(project=resolve_gcp_project())
        return self._client

    def _document(self):
        return self._firestore().collection("app_config").document("ai_chat_templates")

    def get(self) -> dict[str, Any]:
        snapshot = self._document().get()
        if not snapshot.exists:
            return {"version": 1, "items": DEFAULT_AI_CHAT_TEMPLATES}
        data = snapshot.to_dict() or {}
        return {
            "version": int(data.get("version", 1)),
            "updated_at": data.get("updated_at"),
            "items": data.get("items", DEFAULT_AI_CHAT_TEMPLATES),
        }

    def upsert(self, items: list[dict[str, Any]]) -> dict[str, Any]:
        previous = self.get()
        stored = {
            "version": int(previous.get("version", 1)) + 1,
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "items": items,
        }
        self._document().set(stored)
        return stored
