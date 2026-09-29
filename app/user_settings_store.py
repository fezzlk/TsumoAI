from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from app.config import resolve_gcp_project


class UserSettingsStore:
    """Firestore-backed account preferences.

    Each preference kind is a single document below the authenticated user so
    changing a setting never rewrites history or other account data.
    """

    def __init__(self) -> None:
        self._client = None

    def _firestore(self):
        if self._client is None:
            from google.cloud import firestore

            self._client = firestore.Client(project=resolve_gcp_project())
        return self._client

    def _document(self, uid: str, name: str):
        return (
            self._firestore()
            .collection("users")
            .document(uid)
            .collection("settings")
            .document(name)
        )

    def get(self, uid: str, name: str) -> dict[str, Any] | None:
        snapshot = self._document(uid, name).get()
        if not snapshot.exists:
            return None
        return snapshot.to_dict()

    def upsert(self, uid: str, name: str, data: dict[str, Any]) -> dict[str, Any]:
        stored = {
            **data,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        self._document(uid, name).set(stored)
        return stored
