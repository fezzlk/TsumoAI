from __future__ import annotations

from app import config


def test_resolve_gcp_project_from_default_credentials(monkeypatch):
    monkeypatch.setattr(config.settings, "gcp_project", None)
    monkeypatch.delenv("GOOGLE_CLOUD_PROJECT", raising=False)
    monkeypatch.delenv("GCLOUD_PROJECT", raising=False)
    monkeypatch.setattr(config.google.auth, "default", lambda: (object(), "runtime-project"))
    assert config.resolve_gcp_project() == "runtime-project"
