from __future__ import annotations

import os

import google.auth
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    openai_api_key: str | None = None
    openai_model: str = "gpt-4o-mini"
    recognize_ensemble_passes: int = 3
    image_ttl_hours: int = 24
    gcp_project: str | None = None
    gcs_bucket_name: str | None = None
    gcs_feedback_prefix: str = "score-feedback"
    gcs_dataset_prefix: str = "score-dataset"
    gcs_accuracy_prefix: str = "recognition-accuracy"
    recognition_feedback_path: str = "data/recognition_feedback.jsonl"
    firebase_project_id: str | None = None
    cors_origins: str = ""
    max_image_bytes: int = 10 * 1024 * 1024
    anonymous_recognition_requests_per_minute: int = 20

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")


settings = Settings()


class GcpProjectConfigurationError(ValueError):
    """Raised when explicit GCP project settings disagree."""


def _explicit_gcp_projects() -> dict[str, str]:
    candidates = {
        "GCP_PROJECT": settings.gcp_project,
        "GOOGLE_CLOUD_PROJECT": os.getenv("GOOGLE_CLOUD_PROJECT"),
        "GCLOUD_PROJECT": os.getenv("GCLOUD_PROJECT"),
    }
    return {
        name: value.strip()
        for name, value in candidates.items()
        if value and value.strip()
    }


def validate_gcp_project_configuration() -> str | None:
    """Return the explicit project, rejecting conflicting target projects.

    ADC identifies credentials, not the intended resource project, so its
    inferred project is used only when no explicit project variable exists.
    """
    projects = _explicit_gcp_projects()
    unique_projects = set(projects.values())
    if len(unique_projects) > 1:
        details = ", ".join(f"{name}={value}" for name, value in projects.items())
        raise GcpProjectConfigurationError(
            f"Conflicting GCP project settings: {details}. "
            "Set all explicit project variables to the same project."
        )
    return next(iter(unique_projects), None)


def resolve_gcp_project() -> str | None:
    """Resolve one resource project, using ADC only as a final fallback."""
    if project := validate_gcp_project_configuration():
        return project
    try:
        _, project = google.auth.default()
        return project
    except google.auth.exceptions.DefaultCredentialsError:
        return None


# Fail during application import instead of allowing different Google clients
# to silently target different projects.
validate_gcp_project_configuration()
