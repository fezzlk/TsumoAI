from __future__ import annotations

import json
from datetime import datetime, timezone
from uuid import uuid4

from google.cloud import storage

from app.config import settings


class GCSFeedbackStore:
    def __init__(self, bucket_name: str | None = None, prefix: str | None = None) -> None:
        self.bucket_name = bucket_name or settings.gcs_bucket_name
        self.prefix = (prefix or settings.gcs_feedback_prefix).strip("/")
        self._client: storage.Client | None = None

    def _get_client(self) -> storage.Client:
        if self._client is None:
            self._client = storage.Client()
        return self._client

    def save(self, payload: dict) -> dict:
        if not self.bucket_name:
            raise ValueError("GCS bucket is not configured")

        now = datetime.now(timezone.utc)
        object_name = f"{self.prefix}/{now.strftime('%Y/%m/%d')}/{uuid4()}.json"
        data = json.dumps(
            {
                "saved_at": now.isoformat(),
                "payload": payload,
            },
            ensure_ascii=False,
        )

        bucket = self._get_client().bucket(self.bucket_name)
        blob = bucket.blob(object_name)
        blob.upload_from_string(data, content_type="application/json")
        return {"bucket": self.bucket_name, "object_name": object_name}
