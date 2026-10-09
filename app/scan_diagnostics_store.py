"""Private, opt-in scan diagnostics stored apart from training data."""

from __future__ import annotations

import json
import hashlib
from datetime import datetime, timezone
from io import BytesIO
from uuid import uuid4

from google.cloud import storage
from PIL import Image, ImageDraw

from app.config import resolve_gcp_project, settings


class ScanDiagnosticsStore:
    prefix = "scan-diagnostics"

    def __init__(self) -> None:
        self._client: storage.Client | None = None

    def _bucket(self) -> storage.Bucket:
        if not settings.gcs_bucket_name:
            raise ValueError("GCS bucket is not configured")
        if self._client is None:
            self._client = storage.Client(project=resolve_gcp_project())
        return self._client.bucket(settings.gcs_bucket_name)

    @staticmethod
    def _owner_prefix(uid: str) -> str:
        owner = hashlib.sha256(uid.encode("utf-8")).hexdigest()[:16]
        return f"{ScanDiagnosticsStore.prefix}/{owner}/"

    @staticmethod
    def _annotated_image(image_bytes: bytes, metadata: dict) -> bytes:
        with Image.open(BytesIO(image_bytes)) as source:
            image = source.convert("RGB")
        draw = ImageDraw.Draw(image)
        for index, box in enumerate(metadata.get("boxes", [])):
            if not isinstance(box, dict):
                continue
            try:
                left = float(box["left"])
                top = float(box["top"])
                right = float(box["right"])
                bottom = float(box["bottom"])
            except (KeyError, TypeError, ValueError):
                continue
            if not (0 <= left < right <= image.width and 0 <= top < bottom <= image.height):
                continue
            draw.rectangle((left, top, right, bottom), outline="#00ff88", width=4)
            draw.text((left + 3, top + 3), str(index + 1), fill="#ff2020")
        output = BytesIO()
        image.save(output, "JPEG", quality=85)
        return output.getvalue()

    def save(self, *, uid: str, raw: bytes, framed: bytes, metadata: dict) -> str:
        now = datetime.now(timezone.utc)
        capture_id = uuid4().hex
        base = f"{self._owner_prefix(uid)}{now:%Y/%m/%d}/{capture_id}"
        bucket = self._bucket()
        uploaded = []
        objects = (
            ("raw.jpg", raw, "image/jpeg"),
            ("framed.jpg", framed, "image/jpeg"),
            ("boxes.jpg", self._annotated_image(framed, metadata), "image/jpeg"),
            ("metadata.json", json.dumps({
                **metadata,
                "capture_id": capture_id,
                "saved_at": now.isoformat(),
                "uid": uid,
            }, ensure_ascii=False).encode(), "application/json"),
        )
        try:
            for suffix, data, content_type in objects:
                blob = bucket.blob(f"{base}/{suffix}")
                blob.upload_from_string(data, content_type=content_type)
                uploaded.append(blob)
        except Exception:
            for blob in uploaded:
                blob.delete()
            raise
        return capture_id

    def delete_by_uid(self, uid: str) -> int:
        """Delete a user's opted-in captures during self-service data deletion."""
        if not settings.gcs_bucket_name:
            return 0
        bucket = self._bucket()
        deleted = 0
        for blob in bucket.list_blobs(prefix=self._owner_prefix(uid)):
            blob.delete()
            deleted += 1
        return deleted

    def save_logs(self, *, uid: str, period_start: str, period_end: str,
                  entries: list[dict]) -> str:
        """Store one manually submitted, bounded device-log interval."""
        now = datetime.now(timezone.utc)
        log_id = uuid4().hex
        name = f"{self._owner_prefix(uid)}logs/{now:%Y/%m/%d}/{log_id}.json"
        payload = {
            "log_id": log_id,
            "saved_at": now.isoformat(),
            "uid": uid,
            "period_start": period_start,
            "period_end": period_end,
            "entries": entries,
        }
        self._bucket().blob(name).upload_from_string(
            json.dumps(payload, ensure_ascii=False), content_type="application/json"
        )
        return log_id
