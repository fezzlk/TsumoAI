from __future__ import annotations

from app import config


def test_resolve_gcp_project_from_default_credentials(monkeypatch):
    monkeypatch.setattr(config.settings, "gcp_project", None)
    monkeypatch.delenv("GOOGLE_CLOUD_PROJECT", raising=False)
    monkeypatch.delenv("GCLOUD_PROJECT", raising=False)
    monkeypatch.setattr(config.google.auth, "default", lambda: (object(), "runtime-project"))
    assert config.resolve_gcp_project() == "runtime-project"


def test_resolve_gcp_project_uses_matching_explicit_values(monkeypatch):
    monkeypatch.setattr(config.settings, "gcp_project", "tsumoai")
    monkeypatch.setenv("GOOGLE_CLOUD_PROJECT", "tsumoai")
    monkeypatch.setenv("GCLOUD_PROJECT", "tsumoai")
    monkeypatch.setattr(
        config.google.auth,
        "default",
        lambda: (_ for _ in ()).throw(AssertionError("ADC must not be consulted")),
    )

    assert config.resolve_gcp_project() == "tsumoai"


def test_conflicting_explicit_gcp_projects_are_rejected(monkeypatch):
    monkeypatch.setattr(config.settings, "gcp_project", "tsumoai")
    monkeypatch.setenv("GOOGLE_CLOUD_PROJECT", "nazonator")
    monkeypatch.delenv("GCLOUD_PROJECT", raising=False)

    try:
        config.resolve_gcp_project()
    except config.GcpProjectConfigurationError as exc:
        message = str(exc)
        assert "GCP_PROJECT=tsumoai" in message
        assert "GOOGLE_CLOUD_PROJECT=nazonator" in message
    else:
        raise AssertionError("conflicting project settings must fail")
