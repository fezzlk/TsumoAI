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
    gcp_region: str = "asia-northeast1"
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


def resolve_gcp_project() -> str | None:
    """Resolve the project explicitly or from the active GCP runtime credentials."""
    if settings.gcp_project:
        return settings.gcp_project
    for variable in ("GOOGLE_CLOUD_PROJECT", "GCLOUD_PROJECT"):
        if project := os.getenv(variable):
            return project
    try:
        _, project = google.auth.default()
        return project
    except google.auth.exceptions.DefaultCredentialsError:
        return None
