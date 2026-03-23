"""GCS-based training data store for tile classifier images."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from io import BytesIO
from uuid import uuid4

from google.cloud import storage

from app.config import settings


class TrainingDataStore:
    def __init__(self) -> None:
        self.bucket_name = settings.gcs_bucket_name
        self.prefix = "training-data"
        self._client: storage.Client | None = None

    def _get_client(self) -> storage.Client:
        if self._client is None:
            self._client = storage.Client(project=settings.gcp_project)
        return self._client

    def _bucket(self) -> storage.Bucket:
        if not self.bucket_name:
            raise ValueError("GCS bucket is not configured")
        return self._get_client().bucket(self.bucket_name)

    def upload(self, image_bytes: bytes, tile_code: str, source: str = "user") -> dict:
        """Upload a training image with its label."""
        now = datetime.now(timezone.utc)
        entry_id = uuid4().hex[:12]
        date_path = now.strftime("%Y/%m/%d")

        # Save image
        image_name = f"{self.prefix}/images/{date_path}/{entry_id}.jpg"
        bucket = self._bucket()
        blob = bucket.blob(image_name)
        blob.upload_from_string(image_bytes, content_type="image/jpeg")

        # Save metadata
        meta = {
            "id": entry_id,
            "tile_code": tile_code,
            "source": source,
            "image_path": image_name,
            "created_at": now.isoformat(),
        }
        meta_name = f"{self.prefix}/meta/{date_path}/{entry_id}.json"
        meta_blob = bucket.blob(meta_name)
        meta_blob.upload_from_string(
            json.dumps(meta, ensure_ascii=False),
            content_type="application/json",
        )

        return {"id": entry_id, "image_path": image_name}

    def list_entries(self, tile_code: str | None = None, source: str | None = None,
                     limit: int = 500) -> list[dict]:
        """List training data entries."""
        bucket = self._bucket()
        blobs = bucket.list_blobs(prefix=f"{self.prefix}/meta/")
        entries = []
        for blob in blobs:
            if not blob.name.endswith(".json"):
                continue
            try:
                meta = json.loads(blob.download_as_text())
            except Exception:
                continue
            if tile_code and meta.get("tile_code") != tile_code:
                continue
            if source and meta.get("source") != source:
                continue
            entries.append(meta)
            if len(entries) >= limit:
                break
        entries.sort(key=lambda e: e.get("created_at", ""), reverse=True)
        return entries

    def get_image(self, entry_id: str) -> bytes | None:
        """Get image bytes by entry id."""
        bucket = self._bucket()
        # Search for the image in GCS
        blobs = list(bucket.list_blobs(prefix=f"{self.prefix}/images/", delimiter=None))
        for blob in blobs:
            if entry_id in blob.name and blob.name.endswith(".jpg"):
                return blob.download_as_bytes()
        return None

    def delete_entry(self, entry_id: str) -> bool:
        """Delete a training data entry (image + metadata)."""
        bucket = self._bucket()
        deleted = False
        for prefix in [f"{self.prefix}/images/", f"{self.prefix}/meta/"]:
            blobs = list(bucket.list_blobs(prefix=prefix))
            for blob in blobs:
                if entry_id in blob.name:
                    blob.delete()
                    deleted = True
        return deleted

    def get_stats(self) -> dict:
        """Get statistics: count per tile_code and source."""
        entries = self.list_entries(limit=10000)
        by_tile: dict[str, int] = {}
        by_source: dict[str, int] = {}
        for e in entries:
            tc = e.get("tile_code", "unknown")
            src = e.get("source", "unknown")
            by_tile[tc] = by_tile.get(tc, 0) + 1
            by_source[src] = by_source.get(src, 0) + 1
        return {
            "total": len(entries),
            "by_tile_code": dict(sorted(by_tile.items())),
            "by_source": dict(sorted(by_source.items())),
        }
