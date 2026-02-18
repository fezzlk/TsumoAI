from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from threading import Lock
from typing import Literal
from uuid import UUID, uuid4


RecordType = Literal["recognition", "score"]


@dataclass
class StoredRecord:
    id: UUID
    type: RecordType
    created_at: datetime
    expires_at: datetime
    data: dict


class InMemoryRepository:
    def __init__(self, ttl_hours: int = 24) -> None:
        self._ttl_hours = ttl_hours
        self._items: dict[UUID, StoredRecord] = {}
        self._lock = Lock()

    def _utcnow(self) -> datetime:
        return datetime.now(timezone.utc)

    def _prune(self) -> None:
        now = self._utcnow()
        expired = [item_id for item_id, item in self._items.items() if item.expires_at <= now]
        for item_id in expired:
            del self._items[item_id]

    def create(self, record_type: RecordType, data: dict) -> StoredRecord:
        with self._lock:
            self._prune()
            now = self._utcnow()
            item = StoredRecord(
                id=uuid4(),
                type=record_type,
                created_at=now,
                expires_at=now + timedelta(hours=self._ttl_hours),
                data=data,
            )
            self._items[item.id] = item
            return item

    def get(self, item_id: UUID) -> StoredRecord | None:
        with self._lock:
            self._prune()
            return self._items.get(item_id)
