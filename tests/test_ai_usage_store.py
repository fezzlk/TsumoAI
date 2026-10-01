from datetime import datetime, timezone

from app.ai_usage_store import AIUsageStore


class _Snapshot:
    def __init__(self, data):
        self._data = data
        self.exists = data is not None

    def to_dict(self):
        return self._data


class _Document:
    def __init__(self, document_id, data):
        self.id = document_id
        self._data = data

    def get(self):
        return _Snapshot(self._data)


class _Collection:
    def __init__(self, client):
        self.client = client

    def document(self, document_id):
        self.client.document_ids.append(document_id)
        return _Document(document_id, self.client.data)


class _Client:
    def __init__(self, data=None):
        self.data = data
        self.document_ids = []

    def collection(self, name):
        assert name == "ai_usage"
        return _Collection(self)


def test_new_monthly_allowance_uses_hashed_subject_and_utc_reset():
    client = _Client()
    store = AIUsageStore(
        client=client,
        now=lambda: datetime(2026, 12, 15, tzinfo=timezone.utc),
    )

    status = store.get_status("install:private-device-id")

    assert status["period"] == "2026-12"
    assert status["included_limit"] == 3
    assert status["remaining"] == 3
    assert status["resets_at"] == datetime(2027, 1, 1, tzinfo=timezone.utc)
    assert "private-device-id" not in client.document_ids[0]


def test_subscription_record_uses_subscription_default_when_limit_is_absent():
    client = _Client(
        {
            "period": "2026-10",
            "plan": "subscription",
            "included_used": 4,
            "bonus_granted": 2,
            "bonus_used": 1,
            "resets_at": datetime(2026, 11, 1, tzinfo=timezone.utc),
        }
    )
    store = AIUsageStore(
        client=client,
        now=lambda: datetime(2026, 10, 15, tzinfo=timezone.utc),
    )

    status = store.get_status("user:member-1")

    assert status["plan"] == "subscription"
    assert status["included_limit"] == 30
    assert status["bonus_remaining"] == 1
    assert status["remaining"] == 27
