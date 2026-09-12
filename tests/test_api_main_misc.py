"""Coverage for app/main.py's remaining untested surface: static/health
pages, the anonymous-recognition rate limiter, 404/422/503 error boundaries
across the API, and the GCS/Cloud-Build-backed admin endpoints (dataset,
training-data, accuracy metrics, model retrain/candidates/download). GCS and
Cloud Build clients are faked so nothing here touches real infrastructure or
incurs cost."""

from __future__ import annotations

import json
from io import BytesIO
from pathlib import Path
from types import SimpleNamespace
from uuid import uuid4

from fastapi.testclient import TestClient
from PIL import Image

from app import main as main_module
from app.auth import get_current_user, require_admin
from app.main import app

client = TestClient(app)


def sample_image_bytes() -> bytes:
    return (Path(__file__).resolve().parents[1] / "app" / "static" / "tiles" / "Mpu1m.png").read_bytes()


def teardown_function():
    app.dependency_overrides.clear()
    main_module._recognition_rate_windows.clear()  # process-global state shared across tests/files


# ── Static / health / rate limiting ──


def test_health_endpoint():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_root_endpoint_returns_html():
    response = client.get("/")
    assert response.status_code == 200
    assert "TsumoAI" in response.text


def test_score_dataset_page_available():
    response = client.get("/score-dataset")
    assert response.status_code == 200


def test_recognize_rejects_empty_image_upload():
    response = client.post("/api/v1/recognize", files={"image": ("hand.png", b"", "image/png")})
    assert response.status_code == 400
    assert "image is required" in response.json()["detail"]


def test_training_data_viewer_page_available():
    response = client.get("/training-data")
    assert response.status_code == 200


def test_anonymous_recognition_rate_limit_returns_429(monkeypatch):
    main_module._recognition_rate_windows.clear()  # other tests share this process-global state
    monkeypatch.setattr(main_module.settings, "anonymous_recognition_requests_per_minute", 1)
    monkeypatch.setattr(main_module, "extract_hand_from_image", lambda image_bytes, should_cancel=None: {"tiles_count": 0, "slots": [], "warnings": []})

    files = {"image": ("hand.png", sample_image_bytes(), "image/png")}
    first = client.post("/api/v1/recognize", files=files)
    second = client.post("/api/v1/recognize", files=files)

    assert first.status_code == 200
    assert second.status_code == 429
    assert "rate limit" in second.json()["detail"]


def test_anonymous_recognition_rate_limit_window_expires(monkeypatch):
    main_module._recognition_rate_windows.clear()
    monkeypatch.setattr(main_module.settings, "anonymous_recognition_requests_per_minute", 1)
    monkeypatch.setattr(main_module, "extract_hand_from_image", lambda image_bytes, should_cancel=None: {"tiles_count": 0, "slots": [], "warnings": []})

    clock = {"t": 0.0}
    monkeypatch.setattr(main_module.time, "monotonic", lambda: clock["t"])

    files = {"image": ("hand.png", sample_image_bytes(), "image/png")}
    first = client.post("/api/v1/recognize", files=files)
    clock["t"] = 100.0  # past the 60s window -> the old entry must be pruned, not rate-limited
    second = client.post("/api/v1/recognize", files=files)

    assert first.status_code == 200
    assert second.status_code == 200


# ── Recognition jobs ──


def test_get_recognize_job_404_for_unknown_id():
    response = client.get(f"/api/v1/recognize-only/jobs/{uuid4()}")
    assert response.status_code == 404


def test_cancel_recognize_job_404_for_unknown_id():
    response = client.post(f"/api/v1/recognize-only/jobs/{uuid4()}/cancel")
    assert response.status_code == 404


# ── Interpretation / results ──


def test_interpret_recognition_404_when_record_missing():
    response = client.post(f"/api/v1/recognitions/{uuid4()}/interpret", json={})
    assert response.status_code == 404


def test_interpret_recognition_422_on_invalid_estimate():
    slots = [
        {"index": 0, "observation_id": "dup", "top": "1m", "candidates": [{"tile": "1m", "confidence": 0.9}]},
        {"index": 1, "observation_id": "dup", "top": "2m", "candidates": [{"tile": "2m", "confidence": 0.9}]},
    ]
    record = main_module.repo.create("recognition", {"hand_estimate": {"tiles_count": 2, "slots": slots}})
    response = client.post(f"/api/v1/recognitions/{record.id}/interpret", json={})
    assert response.status_code == 422


def test_get_result_404_for_unknown_id():
    response = client.get(f"/api/v1/results/{uuid4()}")
    assert response.status_code == 404


def test_get_result_returns_stored_record():
    record = main_module.repo.create("score", {"value": 1})
    response = client.get(f"/api/v1/results/{record.id}")
    assert response.status_code == 200
    body = response.json()
    assert body["id"] == str(record.id)
    assert body["type"] == "score"
    assert body["data"] == {"value": 1}


# ── recognize-and-score ──


def test_recognize_and_score_rejects_invalid_json(monkeypatch):
    monkeypatch.setattr(main_module, "extract_hand_from_image", lambda image_bytes, should_cancel=None: {"tiles_count": 0, "slots": [], "warnings": []})
    response = client.post(
        "/api/v1/recognize-and-score",
        files={"image": ("hand.png", sample_image_bytes(), "image/png")},
        data={"context_json": "not json", "rules_json": "{}"},
    )
    assert response.status_code == 422
    assert "Invalid JSON payload" in response.json()["detail"]


def test_recognize_and_score_rejects_unconvertible_estimate(monkeypatch):
    monkeypatch.setattr(main_module, "extract_hand_from_image", lambda image_bytes, should_cancel=None: {"tiles_count": 0, "slots": [], "warnings": []})
    context = {
        "win_type": "ron", "is_dealer": False, "round_wind": "E", "seat_wind": "S",
        "riichi": False, "ippatsu": False, "haitei": False, "houtei": False,
        "rinshan": False, "chankan": False,
    }
    response = client.post(
        "/api/v1/recognize-and-score",
        files={"image": ("hand.png", sample_image_bytes(), "image/png")},
        data={"context_json": json.dumps(context), "rules_json": "{}"},
    )
    assert response.status_code == 422


# ── Feedback ──


def test_score_feedback_returns_503_when_gcs_not_configured():
    app.dependency_overrides[get_current_user] = lambda: {"uid": "user-1"}
    monkeypatch_bucket = main_module.gcs_feedback_store.bucket_name
    main_module.gcs_feedback_store.bucket_name = None
    try:
        response = client.post("/api/v1/score/feedback", json={"comment": "test"})
        assert response.status_code == 503
    finally:
        main_module.gcs_feedback_store.bucket_name = monkeypatch_bucket


def test_recognition_feedback_rejects_wrong_tile_count():
    app.dependency_overrides[get_current_user] = lambda: {"uid": "user-1"}
    response = client.post(
        "/api/v1/recognition/feedback",
        json={"recognition_response": {}, "corrected_tiles": ["1m"] * 13, "comment": ""},
    )
    assert response.status_code == 422
    assert "exactly 14 tiles" in response.json()["detail"]


# ── GCS-backed helpers shared by dataset/accuracy/model endpoints ──


class _FakeBlob:
    def __init__(self, name, store, size=100, updated=None):
        self.name = name
        self._store = store
        self.size = size
        self.updated = updated

    def upload_from_string(self, data, content_type=None):
        self._store[self.name] = data if isinstance(data, bytes) else data.encode("utf-8")

    def exists(self):
        return self.name in self._store

    def download_as_text(self):
        return self._store[self.name].decode("utf-8")

    def download_as_bytes(self):
        return self._store[self.name]


class _FakeBucket:
    def __init__(self, store):
        self._store = store

    def blob(self, name):
        return _FakeBlob(name, self._store)

    def list_blobs(self, prefix):
        return [_FakeBlob(name, self._store) for name in sorted(self._store) if name.startswith(prefix)]


class _FakeGCSClient:
    def __init__(self, store):
        self._store = store

    def bucket(self, name):
        return _FakeBucket(self._store)


def _install_fake_gcs(monkeypatch, gcs_store_instance, objects: dict, bucket_name="bucket"):
    gcs_store_instance.bucket_name = bucket_name
    monkeypatch.setattr(gcs_store_instance, "_get_client", lambda: _FakeGCSClient(objects))


# ── Dataset endpoints ──


def test_upload_dataset_rejects_empty_entries():
    app.dependency_overrides[get_current_user] = lambda: {"uid": "user-1"}
    response = client.post("/api/v1/dataset/upload", json={"entries": []})
    assert response.status_code == 422


def test_upload_dataset_503_when_gcs_not_configured():
    app.dependency_overrides[get_current_user] = lambda: {"uid": "user-1"}
    original = main_module.gcs_dataset_store.bucket_name
    main_module.gcs_dataset_store.bucket_name = None
    try:
        response = client.post("/api/v1/dataset/upload", json={"entries": [{"tile": "1m"}]})
        assert response.status_code == 503
    finally:
        main_module.gcs_dataset_store.bucket_name = original


def test_upload_dataset_succeeds_with_contributor(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"uid": "user-1"}
    monkeypatch.setattr(main_module.gcs_dataset_store, "save", lambda payload, contributor=None: {"bucket": "b", "object_name": "n"})
    response = client.post(
        "/api/v1/dataset/upload",
        json={"entries": [{"tile": "1m"}], "contributor": "user-1"},
    )
    assert response.status_code == 200
    assert response.json()["count"] == 1


def test_list_datasets_requires_admin():
    response = client.get("/api/v1/dataset/list")
    assert response.status_code == 401


def test_list_datasets_503_when_not_configured():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    original = main_module.gcs_dataset_store.bucket_name
    main_module.gcs_dataset_store.bucket_name = None
    try:
        response = client.get("/api/v1/dataset/list")
        assert response.status_code == 503
    finally:
        main_module.gcs_dataset_store.bucket_name = original


def test_list_datasets_returns_json_files_sorted_by_updated(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    objects = {
        "score-dataset/old.json": b"{}",
        "score-dataset/new.json": b"{}",
        "score-dataset/notes.txt": b"ignored",
    }
    from datetime import datetime, timezone

    class DatedFakeBucket(_FakeBucket):
        def list_blobs(self, prefix):
            return [
                _FakeBlob("score-dataset/old.json", objects, updated=datetime(2026, 1, 1, tzinfo=timezone.utc)),
                _FakeBlob("score-dataset/new.json", objects, updated=datetime(2026, 6, 1, tzinfo=timezone.utc)),
                _FakeBlob("score-dataset/notes.txt", objects),
            ]

    monkeypatch.setattr(main_module.gcs_dataset_store, "bucket_name", "bucket")
    monkeypatch.setattr(
        main_module.gcs_dataset_store, "_get_client",
        lambda: SimpleNamespace(bucket=lambda name: DatedFakeBucket(objects)),
    )

    response = client.get("/api/v1/dataset/list")
    assert response.status_code == 200
    names = [f["name"] for f in response.json()["files"]]
    assert names == ["score-dataset/new.json", "score-dataset/old.json"]


def test_download_dataset_503_when_not_configured():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    original = main_module.gcs_dataset_store.bucket_name
    main_module.gcs_dataset_store.bucket_name = None
    try:
        response = client.get("/api/v1/dataset/download", params={"name": "score-dataset/x.json"})
        assert response.status_code == 503
    finally:
        main_module.gcs_dataset_store.bucket_name = original


def test_download_dataset_rejects_path_traversal(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    _install_fake_gcs(monkeypatch, main_module.gcs_dataset_store, {})
    response = client.get("/api/v1/dataset/download", params={"name": "../../etc/passwd"})
    assert response.status_code == 400


def test_download_dataset_rejects_wrong_prefix_or_extension(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    _install_fake_gcs(monkeypatch, main_module.gcs_dataset_store, {})
    assert client.get("/api/v1/dataset/download", params={"name": "other-prefix/x.json"}).status_code == 400
    assert client.get("/api/v1/dataset/download", params={"name": "score-dataset/x.txt"}).status_code == 400


def test_download_dataset_404_when_missing(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    _install_fake_gcs(monkeypatch, main_module.gcs_dataset_store, {})
    response = client.get("/api/v1/dataset/download", params={"name": "score-dataset/missing.json"})
    assert response.status_code == 404


def test_download_dataset_returns_json_content(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    objects = {"score-dataset/x.json": json.dumps({"a": 1}).encode("utf-8")}
    _install_fake_gcs(monkeypatch, main_module.gcs_dataset_store, objects)
    response = client.get("/api/v1/dataset/download", params={"name": "score-dataset/x.json"})
    assert response.status_code == 200
    assert response.json() == {"a": 1}


# ── Training-data endpoints ──


def test_upload_training_data_success(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"uid": "user-1"}
    monkeypatch.setattr(main_module.training_data_store, "upload", lambda *a, **k: {"id": "abc", "image_path": "x"})
    response = client.post(
        "/api/v1/training-data/upload",
        files={"image": ("hand.jpg", b"x", "image/jpeg")},
        data={"tile_code": "1m"},
    )
    assert response.status_code == 200
    assert response.json()["id"] == "abc"


def test_upload_training_data_validates_predicted_tile_code(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"uid": "user-1"}
    captured = {}

    def fake_upload(image_bytes, tile_code, source, predicted_tile_code=None):
        captured["predicted"] = predicted_tile_code
        return {"id": "abc", "image_path": "x"}

    monkeypatch.setattr(main_module.training_data_store, "upload", fake_upload)
    response = client.post(
        "/api/v1/training-data/upload",
        files={"image": ("hand.jpg", b"x", "image/jpeg")},
        data={"tile_code": "1m", "predicted_tile_code": "2m"},
    )
    assert response.status_code == 200
    assert captured["predicted"] == "2m"


def test_upload_training_data_rejects_invalid_predicted_tile_code():
    app.dependency_overrides[get_current_user] = lambda: {"uid": "user-1"}
    response = client.post(
        "/api/v1/training-data/upload",
        files={"image": ("hand.jpg", b"x", "image/jpeg")},
        data={"tile_code": "1m", "predicted_tile_code": "10m"},
    )
    assert response.status_code == 422


def test_upload_training_data_503_when_store_raises(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"uid": "user-1"}

    def raise_value_error(*a, **k):
        raise ValueError("GCS bucket is not configured")

    monkeypatch.setattr(main_module.training_data_store, "upload", raise_value_error)
    response = client.post(
        "/api/v1/training-data/upload",
        files={"image": ("hand.jpg", b"x", "image/jpeg")},
        data={"tile_code": "1m"},
    )
    assert response.status_code == 503


def test_list_training_data_invalidates_cache_on_refresh(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    calls = {"invalidated": False}
    monkeypatch.setattr(main_module.training_data_store, "invalidate_cache", lambda: calls.__setitem__("invalidated", True))
    monkeypatch.setattr(main_module.training_data_store, "list_entries", lambda **_: [])
    monkeypatch.setattr(main_module.training_data_store, "get_stats", lambda: {})
    monkeypatch.setattr(main_module.training_data_store, "get_daily_timeline", lambda: [])

    response = client.get("/api/v1/training-data/list", params={"refresh": True})
    assert response.status_code == 200
    assert calls["invalidated"] is True


def test_list_training_data_503_when_store_raises(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}

    def raise_value_error(**k):
        raise ValueError("GCS bucket is not configured")

    monkeypatch.setattr(main_module.training_data_store, "list_entries", raise_value_error)
    response = client.get("/api/v1/training-data/list")
    assert response.status_code == 503


def test_get_training_image_404_when_missing(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    monkeypatch.setattr(main_module.training_data_store, "get_image", lambda entry_id: None)
    response = client.get("/api/v1/training-data/image/missing")
    assert response.status_code == 404


def test_get_training_image_returns_bytes(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    monkeypatch.setattr(main_module.training_data_store, "get_image", lambda entry_id: b"jpeg-bytes")
    response = client.get("/api/v1/training-data/image/abc")
    assert response.status_code == 200
    assert response.content == b"jpeg-bytes"


def test_get_training_image_503_when_store_raises(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}

    def raise_value_error(entry_id):
        raise ValueError("GCS bucket is not configured")

    monkeypatch.setattr(main_module.training_data_store, "get_image", raise_value_error)
    response = client.get("/api/v1/training-data/image/abc")
    assert response.status_code == 503


def test_delete_training_data_404_when_missing(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    monkeypatch.setattr(main_module.training_data_store, "delete_entry", lambda entry_id: False)
    response = client.delete("/api/v1/training-data/missing")
    assert response.status_code == 404


def test_delete_training_data_success(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    monkeypatch.setattr(main_module.training_data_store, "delete_entry", lambda entry_id: True)
    response = client.delete("/api/v1/training-data/abc")
    assert response.status_code == 200
    assert response.json() == {"status": "deleted", "id": "abc"}


def test_delete_training_data_503_when_store_raises(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}

    def raise_value_error(entry_id):
        raise ValueError("GCS bucket is not configured")

    monkeypatch.setattr(main_module.training_data_store, "delete_entry", raise_value_error)
    response = client.delete("/api/v1/training-data/abc")
    assert response.status_code == 503


def test_update_training_data_label_404_when_missing(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    monkeypatch.setattr(main_module.training_data_store, "update_tile_code", lambda entry_id, tile: False)
    response = client.patch("/api/v1/training-data/missing", params={"tile_code": "1m"})
    assert response.status_code == 404


def test_update_training_data_label_503_when_store_raises(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}

    def raise_value_error(entry_id, tile):
        raise ValueError("GCS bucket is not configured")

    monkeypatch.setattr(main_module.training_data_store, "update_tile_code", raise_value_error)
    response = client.patch("/api/v1/training-data/abc", params={"tile_code": "1m"})
    assert response.status_code == 503


# ── Accuracy history ──


def test_accuracy_history_503_when_not_configured():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    original = main_module.accuracy_store.bucket_name
    main_module.accuracy_store.bucket_name = None
    try:
        response = client.get("/api/v1/metrics/accuracy-history")
        assert response.status_code == 503
    finally:
        main_module.accuracy_store.bucket_name = original


def test_accuracy_history_skips_non_json_and_unparseable_blobs(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    prefix = main_module.accuracy_store.prefix
    objects = {
        f"{prefix}/a.json": json.dumps({"payload": {"evaluated_at": "2026-08-01", "tile_accuracy": 0.9, "exact_match_rate": 0.8, "n": 10}}).encode("utf-8"),
        f"{prefix}/b.json": b"not json",
        f"{prefix}/notes.txt": b"ignored",
        f"{prefix}/c.json": json.dumps({"saved_at": "2026-08-02", "payload": {}}).encode("utf-8"),
    }
    _install_fake_gcs(monkeypatch, main_module.accuracy_store, objects)

    response = client.get("/api/v1/metrics/accuracy-history")
    assert response.status_code == 200
    history = response.json()["history"]
    assert len(history) == 2
    assert history[0]["evaluated_at"] == "2026-08-01"
    assert history[1]["evaluated_at"] == "2026-08-02"


# ── Model retraining / candidates / download ──


def test_retraining_history_503_when_project_not_configured(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    monkeypatch.setattr(main_module, "resolve_gcp_project", lambda: None)
    response = client.get("/api/v1/model/retraining-history")
    assert response.status_code == 503


def test_retraining_history_500_on_unexpected_error(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    from google.cloud.devtools import cloudbuild_v1

    monkeypatch.setattr(main_module, "resolve_gcp_project", lambda: "tsumoai")

    class RaisingClient:
        def list_builds(self, request):
            raise RuntimeError("cloud build unavailable")

    monkeypatch.setattr(cloudbuild_v1, "CloudBuildClient", RaisingClient)
    response = client.get("/api/v1/model/retraining-history")
    assert response.status_code == 500


def test_latest_model_503_when_gcs_not_configured():
    original = main_module.settings.gcs_bucket_name
    main_module.settings.gcs_bucket_name = None
    try:
        response = client.get("/api/v1/model/latest")
        assert response.status_code == 503
    finally:
        main_module.settings.gcs_bucket_name = original


def test_latest_model_no_model_when_blob_missing(monkeypatch):
    monkeypatch.setattr(main_module.settings, "gcs_bucket_name", "bucket")
    monkeypatch.setattr("google.cloud.storage.Client", lambda project=None: _FakeGCSClient({}))
    response = client.get("/api/v1/model/latest")
    assert response.status_code == 200
    assert response.json()["status"] == "no_model"


def test_latest_model_returns_metadata(monkeypatch):
    monkeypatch.setattr(main_module.settings, "gcs_bucket_name", "bucket")
    objects = {"models/latest.json": json.dumps({"version": "20260101000000"}).encode("utf-8")}
    monkeypatch.setattr("google.cloud.storage.Client", lambda project=None: _FakeGCSClient(objects))
    response = client.get("/api/v1/model/latest")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "version": "20260101000000"}


def test_latest_model_500_on_unexpected_error(monkeypatch):
    monkeypatch.setattr(main_module.settings, "gcs_bucket_name", "bucket")

    def raise_error(project=None):
        raise RuntimeError("gcs unavailable")

    monkeypatch.setattr("google.cloud.storage.Client", raise_error)
    response = client.get("/api/v1/model/latest")
    assert response.status_code == 500


def test_trigger_retrain_503_project_not_configured(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    monkeypatch.setattr(main_module, "resolve_gcp_project", lambda: None)
    response = client.post("/api/v1/model/retrain")
    assert response.status_code == 503


def test_trigger_retrain_503_gcs_not_configured(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    monkeypatch.setattr(main_module, "resolve_gcp_project", lambda: "tsumoai")
    monkeypatch.setattr(main_module.settings, "gcs_bucket_name", None)
    response = client.post("/api/v1/model/retrain")
    assert response.status_code == 503


def test_trigger_retrain_409_when_already_active(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    from google.cloud.devtools import cloudbuild_v1

    monkeypatch.setattr(main_module, "resolve_gcp_project", lambda: "tsumoai")
    monkeypatch.setattr(main_module.settings, "gcs_bucket_name", "bucket")

    active_build = SimpleNamespace(id="build-1", tags=["tsumoai-model-training"], status=cloudbuild_v1.Build.Status.WORKING)

    class FakeClient:
        def list_builds(self, request):
            return [active_build]

    monkeypatch.setattr(cloudbuild_v1, "CloudBuildClient", FakeClient)
    response = client.post("/api/v1/model/retrain")
    assert response.status_code == 409


def test_trigger_retrain_starts_build_successfully(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    from google.cloud.devtools import cloudbuild_v1

    monkeypatch.setattr(main_module, "resolve_gcp_project", lambda: "tsumoai")
    monkeypatch.setattr(main_module.settings, "gcs_bucket_name", "bucket")

    class FakeClient:
        def list_builds(self, request):
            return []

        def create_build(self, request):
            return SimpleNamespace(metadata=SimpleNamespace(build=SimpleNamespace(id="new-build-id")))

    monkeypatch.setattr(cloudbuild_v1, "CloudBuildClient", FakeClient)
    response = client.post("/api/v1/model/retrain")
    assert response.status_code == 200
    assert response.json()["build_id"] == "new-build-id"


def test_trigger_retrain_500_on_unexpected_error(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    from google.cloud.devtools import cloudbuild_v1

    monkeypatch.setattr(main_module, "resolve_gcp_project", lambda: "tsumoai")
    monkeypatch.setattr(main_module.settings, "gcs_bucket_name", "bucket")

    class RaisingClient:
        def list_builds(self, request):
            raise RuntimeError("cloud build down")

    monkeypatch.setattr(cloudbuild_v1, "CloudBuildClient", RaisingClient)
    response = client.post("/api/v1/model/retrain")
    assert response.status_code == 500


def test_approve_model_candidate_rejects_invalid_version_format():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    response = client.post("/api/v1/model/candidates/not-a-version/approve")
    assert response.status_code == 400


def test_approve_model_candidate_503_gcs_not_configured(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    monkeypatch.setattr(main_module.settings, "gcs_bucket_name", None)
    response = client.post("/api/v1/model/candidates/20260101000000/approve")
    assert response.status_code == 503


def test_approve_model_candidate_404_when_missing(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    monkeypatch.setattr(main_module.settings, "gcs_bucket_name", "bucket")
    monkeypatch.setattr("google.cloud.storage.Client", lambda project=None: _FakeGCSClient({}))
    response = client.post("/api/v1/model/candidates/20260101000000/approve")
    assert response.status_code == 404


def test_approve_model_candidate_success(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    monkeypatch.setattr(main_module.settings, "gcs_bucket_name", "bucket")
    objects = {"models/candidates/20260101000000.json": json.dumps({"version": "20260101000000"}).encode("utf-8")}
    monkeypatch.setattr("google.cloud.storage.Client", lambda project=None: _FakeGCSClient(objects))

    response = client.post("/api/v1/model/candidates/20260101000000/approve")
    assert response.status_code == 200
    assert response.json()["status"] == "approved"
    latest = json.loads(objects["models/latest.json"].decode("utf-8"))
    assert latest["approved_by"] == "admin"


def test_approve_model_candidate_500_on_unexpected_error(monkeypatch):
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin", "admin": True}
    monkeypatch.setattr(main_module.settings, "gcs_bucket_name", "bucket")

    def raise_error(project=None):
        raise RuntimeError("gcs down")

    monkeypatch.setattr("google.cloud.storage.Client", raise_error)
    response = client.post("/api/v1/model/candidates/20260101000000/approve")
    assert response.status_code == 500


def test_download_model_file_rejects_invalid_filename():
    response = client.get("/api/v1/model/download/not-allowed.exe")
    assert response.status_code == 400


def test_download_model_file_503_gcs_not_configured(monkeypatch):
    monkeypatch.setattr(main_module.settings, "gcs_bucket_name", None)
    response = client.get("/api/v1/model/download/labels.txt")
    assert response.status_code == 503


def test_download_model_file_404_when_no_model(monkeypatch):
    monkeypatch.setattr(main_module.settings, "gcs_bucket_name", "bucket")
    monkeypatch.setattr("google.cloud.storage.Client", lambda project=None: _FakeGCSClient({}))
    response = client.get("/api/v1/model/download/labels.txt")
    assert response.status_code == 404


def test_download_model_file_404_when_file_missing(monkeypatch):
    monkeypatch.setattr(main_module.settings, "gcs_bucket_name", "bucket")
    objects = {"models/latest.json": json.dumps({"version": "20260101000000"}).encode("utf-8")}
    monkeypatch.setattr("google.cloud.storage.Client", lambda project=None: _FakeGCSClient(objects))
    response = client.get("/api/v1/model/download/labels.txt")
    assert response.status_code == 404


def test_download_model_file_returns_bytes_with_version_header(monkeypatch):
    monkeypatch.setattr(main_module.settings, "gcs_bucket_name", "bucket")
    objects = {
        "models/latest.json": json.dumps({"version": "20260101000000"}).encode("utf-8"),
        "models/20260101000000/labels.txt": b"1m\n2m\n",
    }
    monkeypatch.setattr("google.cloud.storage.Client", lambda project=None: _FakeGCSClient(objects))
    response = client.get("/api/v1/model/download/labels.txt")
    assert response.status_code == 200
    assert response.content == b"1m\n2m\n"
    assert response.headers["x-model-version"] == "20260101000000"


def test_download_model_file_500_on_unexpected_error(monkeypatch):
    monkeypatch.setattr(main_module.settings, "gcs_bucket_name", "bucket")

    def raise_error(project=None):
        raise RuntimeError("gcs down")

    monkeypatch.setattr("google.cloud.storage.Client", raise_error)
    response = client.get("/api/v1/model/download/labels.txt")
    assert response.status_code == 500
