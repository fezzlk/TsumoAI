import json
from datetime import datetime, timedelta, timezone
from io import BytesIO

from fastapi.testclient import TestClient
from PIL import Image

from app.auth import require_admin
from app.main import app
from app.scan_diagnostics_store import ScanDiagnosticsStore


client = TestClient(app)


def _jpeg() -> bytes:
    output = BytesIO()
    Image.new("RGB", (100, 80), "white").save(output, "JPEG")
    return output.getvalue()


def test_diagnostic_upload_requires_admin():
    response = client.post(
        "/api/v1/scan-diagnostics",
        files={
            "raw_image": ("raw.jpg", _jpeg(), "image/jpeg"),
            "framed_image": ("framed.jpg", _jpeg(), "image/jpeg"),
        },
        data={"metadata": "{}"},
    )
    assert response.status_code == 401


def test_diagnostic_upload_saves_capture_with_boxes(monkeypatch):
    from app import main

    saved = {}
    app.dependency_overrides[require_admin] = lambda: {"uid": "developer", "admin": True}

    def fake_save(**kwargs):
        saved.update(kwargs)
        return "capture-1"

    monkeypatch.setattr(main.scan_diagnostics_store, "save", fake_save)
    try:
        response = client.post(
            "/api/v1/scan-diagnostics",
            files={
                "raw_image": ("raw.jpg", _jpeg(), "image/jpeg"),
                "framed_image": ("framed.jpg", _jpeg(), "image/jpeg"),
            },
            data={"metadata": json.dumps({
                "platform": "android",
                "boxes": [{"left": 1, "top": 2, "right": 20, "bottom": 40}],
            })},
        )
    finally:
        app.dependency_overrides.clear()
    assert response.status_code == 200
    assert response.json()["capture_id"] == "capture-1"
    assert saved["uid"] == "developer"
    assert saved["metadata"]["boxes"][0]["right"] == 20


def test_box_overlay_is_created_from_framed_image():
    overlay = ScanDiagnosticsStore._annotated_image(
        _jpeg(), {"boxes": [{"left": 1, "top": 2, "right": 20, "bottom": 40}]}
    )
    with Image.open(BytesIO(overlay)) as image:
        assert image.size == (100, 80)
        assert image.getpixel((1, 20)) != (255, 255, 255)


def test_delete_by_uid_only_lists_own_diagnostics(monkeypatch):
    store = ScanDiagnosticsStore()
    seen = []

    class Blob:
        def delete(self):
            seen.append("deleted")

    class Bucket:
        def list_blobs(self, *, prefix):
            seen.append(prefix)
            return [Blob(), Blob()]

    monkeypatch.setattr(store, "_bucket", lambda: Bucket())
    monkeypatch.setattr("app.scan_diagnostics_store.settings.gcs_bucket_name", "test-bucket")
    assert store.delete_by_uid("alice") == 2
    assert seen[0] == ScanDiagnosticsStore._owner_prefix("alice")
    assert seen[0] != ScanDiagnosticsStore._owner_prefix("bob")


def test_diagnostic_upload_rejects_invalid_boxes():
    app.dependency_overrides[require_admin] = lambda: {"uid": "developer", "admin": True}
    try:
        response = client.post(
            "/api/v1/scan-diagnostics",
            files={
                "raw_image": ("raw.jpg", _jpeg(), "image/jpeg"),
                "framed_image": ("framed.jpg", _jpeg(), "image/jpeg"),
            },
            data={"metadata": '{"boxes": null}'},
        )
    finally:
        app.dependency_overrides.clear()
    assert response.status_code == 422


def _log_payload():
    end = datetime.now(timezone.utc)
    start = end - timedelta(hours=1)
    return {
        "period_start": start.isoformat(),
        "period_end": end.isoformat(),
        "entries": [{"time": end.isoformat(), "event": "captureFailed",
                     "error_type": "CameraException"}],
    }


def test_log_upload_requires_admin():
    assert client.post("/api/v1/scan-diagnostics/logs", json=_log_payload()).status_code == 401


def test_log_upload_stores_selected_interval(monkeypatch):
    from app import main
    saved = {}
    app.dependency_overrides[require_admin] = lambda: {"uid": "developer", "admin": True}

    def fake_save(**kwargs):
        saved.update(kwargs)
        return "log-1"

    monkeypatch.setattr(main.scan_diagnostics_store, "save_logs", fake_save)
    try:
        response = client.post("/api/v1/scan-diagnostics/logs", json=_log_payload())
    finally:
        app.dependency_overrides.clear()
    assert response.status_code == 200
    assert response.json()["log_id"] == "log-1"
    assert saved["uid"] == "developer"
    assert len(saved["entries"]) == 1


def test_log_upload_rejects_extra_fields(monkeypatch):
    payload = _log_payload()
    payload["entries"][0]["message"] = "private chat text"
    app.dependency_overrides[require_admin] = lambda: {"uid": "developer", "admin": True}
    try:
        response = client.post("/api/v1/scan-diagnostics/logs", json=payload)
    finally:
        app.dependency_overrides.clear()
    assert response.status_code == 422
