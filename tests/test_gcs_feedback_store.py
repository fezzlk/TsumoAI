from __future__ import annotations

import json

import pytest

from app.gcs_feedback_store import GCSFeedbackStore


class _FakeBlob:
    def __init__(self, name: str, sink: dict):
        self.name = name
        self._sink = sink

    def upload_from_string(self, data: str, content_type: str) -> None:
        self._sink[self.name] = {"data": data, "content_type": content_type}


class _FakeBucket:
    def __init__(self, name: str, sink: dict):
        self.name = name
        self._sink = sink

    def blob(self, object_name: str) -> _FakeBlob:
        return _FakeBlob(object_name, self._sink)


class _FakeClient:
    instances = 0

    def __init__(self, project=None):
        _FakeClient.instances += 1
        self.project = project
        self.uploaded: dict = {}

    def bucket(self, name: str) -> _FakeBucket:
        return _FakeBucket(name, self.uploaded)


@pytest.fixture(autouse=True)
def _reset_fake_client_counter():
    _FakeClient.instances = 0
    yield


def test_save_raises_when_bucket_not_configured():
    store = GCSFeedbackStore(bucket_name=None)
    with pytest.raises(ValueError, match="GCS bucket is not configured"):
        store.save({"comment": "hello"})


def test_save_uploads_payload_with_expected_object_naming(monkeypatch):
    monkeypatch.setattr("app.gcs_feedback_store.storage.Client", _FakeClient)
    store = GCSFeedbackStore(bucket_name="my-bucket", prefix="feedback")

    result = store.save({"comment": "hello"}, contributor="user-42")

    assert result["bucket"] == "my-bucket"
    assert result["object_name"].startswith("feedback/")
    assert "user-42_" in result["object_name"]
    assert result["object_name"].endswith(".json")

    client = store._client
    uploaded = client.uploaded[result["object_name"]]
    assert uploaded["content_type"] == "application/json"
    body = json.loads(uploaded["data"])
    assert body["payload"] == {"comment": "hello"}
    assert "saved_at" in body


def test_save_generates_a_random_name_without_contributor(monkeypatch):
    monkeypatch.setattr("app.gcs_feedback_store.storage.Client", _FakeClient)
    store = GCSFeedbackStore(bucket_name="my-bucket")

    result = store.save({"comment": "anon"})
    # object_name is "<prefix>/<yyyy>/<mm>/<dd>/<random-uuid>_<8-hex>.json"
    assert result["object_name"].count("/") == 4


def test_get_client_is_constructed_lazily_and_cached(monkeypatch):
    monkeypatch.setattr("app.gcs_feedback_store.storage.Client", _FakeClient)
    store = GCSFeedbackStore(bucket_name="my-bucket")
    assert _FakeClient.instances == 0

    store.save({"a": 1})
    store.save({"a": 2})

    assert _FakeClient.instances == 1
