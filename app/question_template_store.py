from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from app.config import resolve_gcp_project


class QuestionTemplateStore:
    max_items = 20

    def __init__(self) -> None:
        self._client = None

    def _firestore(self):
        if self._client is None:
            from google.cloud import firestore

            self._client = firestore.Client(project=resolve_gcp_project())
        return self._client

    def _collection(self, uid: str):
        return (
            self._firestore()
            .collection("users")
            .document(uid)
            .collection("question_templates")
        )

    def list(self, uid: str) -> list[dict[str, Any]]:
        documents = self._collection(uid).order_by(
            "updated_at", direction="DESCENDING"
        ).limit(self.max_items).stream()
        return [document.to_dict() for document in documents]

    def upsert(self, uid: str, item_id: str, data: dict[str, Any]) -> dict[str, Any]:
        collection = self._collection(uid)
        document = collection.document(item_id)
        previous = document.get()
        if not previous.exists:
            existing = list(collection.limit(self.max_items).stream())
            if len(existing) >= self.max_items:
                raise ValueError("Question template limit reached")
        now = datetime.now(timezone.utc).isoformat()
        previous_data = previous.to_dict() if previous.exists else {}
        stored = {
            **data,
            "id": item_id,
            "created_at": previous_data.get("created_at")
            or data.get("created_at")
            or now,
            "updated_at": now,
        }
        document.set(stored)
        return stored

    def delete(self, uid: str, item_id: str) -> None:
        self._collection(uid).document(item_id).delete()
