from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from app.config import resolve_gcp_project


class HistoryStore:
    """Firestore-backed per-account result summaries.

    Images and in-progress match state are intentionally excluded. The client
    owns an offline copy and treats this store as best-effort synchronization.
    """

    def __init__(self) -> None:
        self._client = None

    def _firestore(self):
        if self._client is None:
            from google.cloud import firestore

            self._client = firestore.Client(project=resolve_gcp_project())
        return self._client

    def _collection(self, uid: str):
        return self._firestore().collection("users").document(uid).collection("history")

    def list(self, uid: str, limit: int = 200) -> list[dict[str, Any]]:
        documents = self._collection(uid).order_by(
            "updated_at", direction="DESCENDING"
        ).limit(limit).stream()
        return [document.to_dict() for document in documents]

    def upsert(self, uid: str, item_id: str, data: dict[str, Any]) -> dict[str, Any]:
        stored = {
            **data,
            "id": item_id,
            "account_uid": uid,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        self._collection(uid).document(item_id).set(stored)
        return stored

    def delete_all(self, uid: str) -> int:
        documents = list(self._collection(uid).stream())
        for document in documents:
            document.reference.delete()
        return len(documents)
