from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.repository import InMemoryRepository


def test_create_and_get_round_trips():
    repo = InMemoryRepository(ttl_hours=24)
    record = repo.create("score", {"value": 1})
    assert repo.get(record.id) is record


def test_get_returns_none_for_unknown_id():
    repo = InMemoryRepository(ttl_hours=24)
    from uuid import uuid4

    assert repo.get(uuid4()) is None


def test_expired_records_are_pruned_on_access():
    repo = InMemoryRepository(ttl_hours=1)
    record = repo.create("score", {"value": 1})

    future = datetime.now(timezone.utc) + timedelta(hours=2)
    repo._utcnow = lambda: future

    assert repo.get(record.id) is None
    assert record.id not in repo._items
