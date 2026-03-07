from __future__ import annotations

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
    recognition_feedback_path: str = "data/recognition_feedback.jsonl"

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")


settings = Settings()
