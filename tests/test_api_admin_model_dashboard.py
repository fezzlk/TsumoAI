"""Admin dashboard APIs for model candidates, evaluations and training data (FEZ-213).

GCS is faked so nothing here touches real infrastructure or incurs cost."""

from __future__ import annotations

import json

import pytest
from fastapi.testclient import TestClient

from app import main as main_module
from app.auth import get_current_user, require_admin
from app.main import app
from app.training_data_store import TrainingDataStore

client = TestClient(app)

SHA_A = "a" * 64
SHA_B = "b" * 64


class _FakeBlob:
    def __init__(self, name, store):
        self.name = name
        self._store = store

    def exists(self):
        return self.name in self._store

    def download_as_text(self):
        return self._store[self.name].decode("utf-8")


class _FakeBucket:
    def __init__(self, store, failing_prefixes=()):
        self._store = store
        self._failing_prefixes = failing_prefixes

    def blob(self, name):
        return _FakeBlob(name, self._store)

    def list_blobs(self, prefix):
        if any(prefix.startswith(p) for p in self._failing_prefixes):
            raise RuntimeError("list failed")
        return [_FakeBlob(name, self._store) for name in sorted(self._store) if name.startswith(prefix)]


class _FakeClient:
    def __init__(self, store, failing_prefixes=()):
        self._store = store
        self._failing_prefixes = failing_prefixes

    def bucket(self, name):
        return _FakeBucket(self._store, self._failing_prefixes)


def _encode(value) -> bytes:
    return json.dumps(value).encode("utf-8")


def _evaluation(evaluated_at, sha, mode="local", tile_accuracy=0.9):
    return _encode({
        "saved_at": evaluated_at,
        "payload": {
            "evaluated_at": evaluated_at,
            "tile_accuracy": tile_accuracy,
            "exact_match_rate": 0.5,
            "n": 10,
            "model_sha256": sha,
            "mode": mode,
        },
    })


@pytest.fixture
def admin():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    yield
    app.dependency_overrides.clear()


@pytest.fixture
def fake_gcs(monkeypatch):
    def install(objects, failing_prefixes=()):
        fake = _FakeClient(objects, failing_prefixes)
        monkeypatch.setattr(main_module.settings, "gcs_bucket_name", "bucket")
        monkeypatch.setattr(main_module.accuracy_store, "bucket_name", "bucket")
        monkeypatch.setattr(main_module.accuracy_store, "_get_client", lambda: fake)
        monkeypatch.setattr("google.cloud.storage.Client", lambda project=None: fake)
        return fake

    return install


def _accuracy_name(name):
    return f"{main_module.accuracy_store.prefix}/{name}"


# ── GET /api/v1/model/candidates ──


def test_model_candidates_requires_login():
    response = client.get("/api/v1/model/candidates")
    assert response.status_code == 401


def test_model_candidates_requires_admin():
    app.dependency_overrides[get_current_user] = lambda: {"uid": "member"}
    try:
        response = client.get("/api/v1/model/candidates")
    finally:
        app.dependency_overrides.clear()
    assert response.status_code == 403


def test_model_candidates_503_when_gcs_not_configured(admin, monkeypatch):
    monkeypatch.setattr(main_module.settings, "gcs_bucket_name", None)
    response = client.get("/api/v1/model/candidates")
    assert response.status_code == 503


def test_model_candidates_distinguish_serving_evaluation_and_invalid(admin, fake_gcs):
    fake_gcs({
        "models/latest.json": _encode({
            "version": "20260101000000",
            "created_at": "2026-01-01T00:00:00+00:00",
            "approved_by": "admin-1",
            "model_sha256": SHA_A,
        }),
        "models/candidates/20260101000000.json": _encode({
            "version": "20260101000000",
            "created_at": "2026-01-01T00:00:00+00:00",
            "val_accuracy": 0.91,
            "evaluation_scope": "random_image_split",
            "dataset_size": 1200,
            "model_sha256": SHA_A,
        }),
        "models/candidates/20260201000000.json": _encode({
            "version": "20260201000000",
            "created_at": "2026-02-01T00:00:00+00:00",
            "val_accuracy": 0.93,
            "model_sha256": SHA_B,
        }),
        "models/candidates/20260301000000.json": b"not json",
        "models/candidates/README.txt": b"ignored",
        _accuracy_name("2026/01/02/x.json"): _evaluation("2026-01-02T00:00:00+00:00", SHA_A, tile_accuracy=0.8),
        _accuracy_name("2026/01/03/y.json"): _evaluation("2026-01-03T00:00:00+00:00", SHA_A, tile_accuracy=0.85),
    })

    response = client.get("/api/v1/model/candidates")

    assert response.status_code == 200
    body = response.json()
    assert body["current"] == {
        "version": "20260101000000",
        "created_at": "2026-01-01T00:00:00+00:00",
        "approved_by": "admin-1",
    }
    candidates = body["candidates"]
    assert [c["version"] for c in candidates] == ["20260301000000", "20260201000000", "20260101000000"]

    invalid, unevaluated, serving = candidates
    assert invalid == {
        "version": "20260301000000",
        "status": "invalid",
        "approvable": False,
        "evaluation_status": "unavailable",
    }

    assert unevaluated["status"] == "candidate"
    assert unevaluated["approvable"] is True
    assert unevaluated["evaluation_status"] == "not_evaluated"
    assert unevaluated["evaluation_count"] == 0
    assert unevaluated["latest_evaluation"] is None
    # Missing metadata is reported as null, not 0.
    assert unevaluated["dataset_size"] is None
    assert unevaluated["val_accuracy"] == 0.93

    assert serving["status"] == "serving"
    assert serving["approvable"] is False
    assert serving["evaluation_status"] == "evaluated"
    assert serving["evaluation_count"] == 2
    assert serving["latest_evaluation"]["tile_accuracy"] == 0.85
    assert serving["latest_evaluation"]["model_sha256"] == SHA_A


def test_model_candidates_without_latest_has_no_serving_version(admin, fake_gcs):
    fake_gcs({
        "models/candidates/20260201000000.json": _encode({"version": "20260201000000", "model_sha256": SHA_B}),
    })

    body = client.get("/api/v1/model/candidates").json()

    assert body["current"] is None
    assert body["candidates"][0]["status"] == "candidate"
    assert body["candidates"][0]["approvable"] is True


def test_model_candidates_candidate_without_hash_is_not_matched(admin, fake_gcs):
    fake_gcs({
        "models/candidates/20260201000000.json": _encode({"version": "20260201000000"}),
        _accuracy_name("a.json"): _evaluation("2026-02-02", None),
    })

    candidate = client.get("/api/v1/model/candidates").json()["candidates"][0]

    assert candidate["evaluation_status"] == "not_evaluated"


def test_model_candidates_marks_evaluations_unavailable_when_history_fails(admin, fake_gcs):
    fake_gcs(
        {"models/candidates/20260201000000.json": _encode({"version": "20260201000000", "model_sha256": SHA_B})},
        failing_prefixes=(main_module.accuracy_store.prefix,),
    )

    response = client.get("/api/v1/model/candidates")

    assert response.status_code == 200
    candidate = response.json()["candidates"][0]
    assert candidate["evaluation_status"] == "unavailable"
    assert candidate["evaluation_count"] is None


# ── GET /api/v1/metrics/accuracy-history filters ──


def test_accuracy_history_requires_login():
    response = client.get("/api/v1/metrics/accuracy-history")
    assert response.status_code == 401


def test_accuracy_history_includes_model_hash_and_mode(admin, fake_gcs):
    fake_gcs({_accuracy_name("a.json"): _evaluation("2026-01-02", SHA_A, mode="pipeline")})

    history = client.get("/api/v1/metrics/accuracy-history").json()["history"]

    assert history[0]["model_sha256"] == SHA_A
    assert history[0]["mode"] == "pipeline"


def test_accuracy_history_filters_by_version_and_mode(admin, fake_gcs):
    fake_gcs({
        "models/candidates/20260101000000.json": _encode({"version": "20260101000000", "model_sha256": SHA_A}),
        _accuracy_name("a.json"): _evaluation("2026-01-02", SHA_A, mode="local"),
        _accuracy_name("b.json"): _evaluation("2026-01-03", SHA_A, mode="pipeline"),
        _accuracy_name("c.json"): _evaluation("2026-01-04", SHA_B, mode="local"),
    })

    by_version = client.get("/api/v1/metrics/accuracy-history?version=20260101000000").json()["history"]
    assert [h["evaluated_at"] for h in by_version] == ["2026-01-02", "2026-01-03"]

    by_mode = client.get("/api/v1/metrics/accuracy-history?mode=local").json()["history"]
    assert [h["evaluated_at"] for h in by_mode] == ["2026-01-02", "2026-01-04"]

    both = client.get("/api/v1/metrics/accuracy-history?version=20260101000000&mode=pipeline").json()["history"]
    assert [h["evaluated_at"] for h in both] == ["2026-01-03"]


def test_accuracy_history_rejects_invalid_version(admin, fake_gcs):
    fake_gcs({})
    response = client.get("/api/v1/metrics/accuracy-history?version=latest")
    assert response.status_code == 400


def test_accuracy_history_404_for_unknown_version(admin, fake_gcs):
    fake_gcs({})
    response = client.get("/api/v1/metrics/accuracy-history?version=20260101000000")
    assert response.status_code == 404


def test_accuracy_history_version_without_hash_returns_empty(admin, fake_gcs):
    fake_gcs({
        "models/candidates/20260101000000.json": _encode({"version": "20260101000000"}),
        _accuracy_name("a.json"): _evaluation("2026-01-02", None),
    })

    response = client.get("/api/v1/metrics/accuracy-history?version=20260101000000")

    assert response.status_code == 200
    assert response.json() == {"history": []}


def test_accuracy_history_without_filters_is_unchanged(admin, fake_gcs):
    fake_gcs({
        _accuracy_name("a.json"): _evaluation("2026-01-02", SHA_A),
        _accuracy_name("b.json"): _evaluation("2026-01-01", SHA_B, mode="pipeline"),
    })

    history = client.get("/api/v1/metrics/accuracy-history").json()["history"]

    assert [h["evaluated_at"] for h in history] == ["2026-01-01", "2026-01-02"]


# ── GET /api/v1/training-data/list filters ──


def test_training_data_list_passes_new_filters(admin, monkeypatch):
    captured = {}

    def fake_list_entries(**kwargs):
        captured.update(kwargs)
        return []

    monkeypatch.setattr(main_module.training_data_store, "list_entries", fake_list_entries)
    monkeypatch.setattr(main_module.training_data_store, "get_stats", lambda: {})
    monkeypatch.setattr(main_module.training_data_store, "get_daily_timeline", lambda: [])

    response = client.get("/api/v1/training-data/list?model_version=v2&corrected_only=true&source=user")

    assert response.status_code == 200
    assert captured["model_version"] == "v2"
    assert captured["corrected_only"] is True
    assert captured["source"] == "user"


def test_training_data_list_defaults_keep_existing_behavior(admin, monkeypatch):
    captured = {}

    def fake_list_entries(**kwargs):
        captured.update(kwargs)
        return []

    monkeypatch.setattr(main_module.training_data_store, "list_entries", fake_list_entries)
    monkeypatch.setattr(main_module.training_data_store, "get_stats", lambda: {})
    monkeypatch.setattr(main_module.training_data_store, "get_daily_timeline", lambda: [])

    client.get("/api/v1/training-data/list")

    assert captured["model_version"] is None
    assert captured["corrected_only"] is False


def _store_with_entries(monkeypatch, entries):
    store = TrainingDataStore.__new__(TrainingDataStore)
    monkeypatch.setattr(store, "_list_gcs", lambda tile_code=None, source=None: list(entries), raising=False)
    return store


ENTRIES = [
    {"id": "1", "tile_code": "1m", "recognition_model_version": "v1", "was_corrected": True},
    {"id": "2", "tile_code": "2m", "recognition_model_version": "v2", "was_corrected": False},
    {"id": "3", "tile_code": "3m", "recognition_model_version": "v2", "was_corrected": True},
    {"id": "4", "tile_code": "4m"},
]


def test_list_entries_filters_by_model_version(monkeypatch):
    store = _store_with_entries(monkeypatch, ENTRIES)
    assert [e["id"] for e in store.list_entries(model_version="v2")] == ["2", "3"]


def test_list_entries_corrected_only_excludes_unknown(monkeypatch):
    store = _store_with_entries(monkeypatch, ENTRIES)
    assert [e["id"] for e in store.list_entries(corrected_only=True)] == ["1", "3"]


def test_list_entries_applies_limit_after_filters(monkeypatch):
    store = _store_with_entries(monkeypatch, ENTRIES)
    assert [e["id"] for e in store.list_entries(model_version="v2", corrected_only=True, limit=1)] == ["3"]


def test_list_entries_without_filters_is_unchanged(monkeypatch):
    store = _store_with_entries(monkeypatch, ENTRIES)
    assert [e["id"] for e in store.list_entries(limit=2)] == ["1", "2"]
