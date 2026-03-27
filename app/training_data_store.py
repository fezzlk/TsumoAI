"""Training data store: all data (user uploads + public datasets) served from GCS.

GCS layout:
  training-data/images/<source>/<tile_code>/<file>.jpg   (public datasets)
  training-data/images/<date_path>/<id>.jpg              (user uploads)
  training-data/meta/<source>/<tile_code>/<file>.json     (public datasets)
  training-data/meta/<date_path>/<id>.json               (user uploads)
"""

from __future__ import annotations

import json
import logging
import time
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from google.cloud import storage

from app.config import settings

logger = logging.getLogger(__name__)

# Local fallback (development only)
LOCAL_DATA_DIR = Path(__file__).resolve().parent.parent / "ml" / "training_data"


class TrainingDataStore:
    # Cache TTL in seconds
    _CACHE_TTL = 60

    def __init__(self) -> None:
        self.bucket_name = settings.gcs_bucket_name
        self.prefix = "training-data"
        self._client: storage.Client | None = None
        self._gcs_meta_cache: list[dict] | None = None
        self._cache_timestamp: float = 0.0

    def _get_client(self) -> storage.Client:
        if self._client is None:
            self._client = storage.Client(project=settings.gcp_project)
        return self._client

    def _bucket(self) -> storage.Bucket:
        if not self.bucket_name:
            raise ValueError("GCS bucket is not configured")
        return self._get_client().bucket(self.bucket_name)

    # ── Upload (GCS, user data) ──

    def upload(self, image_bytes: bytes, tile_code: str, source: str = "user") -> dict:
        now = datetime.now(timezone.utc)
        entry_id = uuid4().hex[:12]
        date_path = now.strftime("%Y/%m/%d")

        image_name = f"{self.prefix}/images/{date_path}/{entry_id}.jpg"
        bucket = self._bucket()
        blob = bucket.blob(image_name)
        blob.upload_from_string(image_bytes, content_type="image/jpeg")

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
        # Update index
        try:
            index = self._load_index()
            index.append(meta)
            self._save_index(index)
        except Exception as exc:
            logger.warning("Failed to update index on upload: %s", exc)
        return {"id": entry_id, "image_path": image_name}

    # ── List (GCS primary, local fallback) ──

    def list_entries(self, tile_code: str | None = None, source: str | None = None,
                     limit: int = 500) -> list[dict]:
        entries: list[dict] = []

        try:
            entries.extend(self._list_gcs(tile_code=tile_code, source=source))
        except Exception as exc:
            logger.warning("GCS list failed, falling back to local: %s", exc)
            entries.extend(self._list_local(tile_code=tile_code, source=source))

        entries.sort(key=lambda e: e.get("tile_code", ""))
        return entries[:limit]

    def invalidate_cache(self) -> None:
        self._gcs_meta_cache = None
        self._cache_timestamp = 0.0

    def _index_blob_name(self) -> str:
        return f"{self.prefix}/index.json"

    def _load_index(self, force: bool = False) -> list[dict]:
        """Load the index file from GCS (single HTTP request)."""
        now = time.monotonic()
        if not force and self._gcs_meta_cache is not None and (now - self._cache_timestamp) < self._CACHE_TTL:
            return self._gcs_meta_cache
        bucket = self._bucket()
        blob = bucket.blob(self._index_blob_name())
        if blob.exists():
            self._gcs_meta_cache = json.loads(blob.download_as_text())
        else:
            # Index doesn't exist yet — rebuild from individual meta files
            self._gcs_meta_cache = self._rebuild_index()
        self._cache_timestamp = now
        return self._gcs_meta_cache

    def _save_index(self, entries: list[dict]) -> None:
        """Save the index file to GCS."""
        bucket = self._bucket()
        blob = bucket.blob(self._index_blob_name())
        blob.upload_from_string(
            json.dumps(entries, ensure_ascii=False),
            content_type="application/json",
        )
        self._gcs_meta_cache = entries
        self._cache_timestamp = time.monotonic()

    def _rebuild_index(self) -> list[dict]:
        """One-time rebuild: scan all meta/*.json and create index.json."""
        bucket = self._bucket()
        blobs = bucket.list_blobs(prefix=f"{self.prefix}/meta/")
        cache: list[dict] = []
        for blob in blobs:
            if not blob.name.endswith(".json"):
                continue
            try:
                meta = json.loads(blob.download_as_text())
                cache.append(meta)
            except Exception:
                continue
        # Save so future requests are fast
        self._save_index(cache)
        logger.info("Rebuilt training data index: %d entries", len(cache))
        return cache

    def _list_gcs(self, tile_code: str | None = None, source: str | None = None) -> list[dict]:
        result = self._load_index()
        if tile_code:
            result = [e for e in result if e.get("tile_code") == tile_code]
        if source:
            result = [e for e in result if e.get("source") == source]
        return result

    def _list_local(self, tile_code: str | None = None, source: str | None = None) -> list[dict]:
        """Fallback: list from local ml/training_data/ (dev only)."""
        entries: list[dict] = []
        if not LOCAL_DATA_DIR.exists():
            return entries
        for source_dir in sorted(LOCAL_DATA_DIR.iterdir()):
            if not source_dir.is_dir():
                continue
            src_name = source_dir.name
            for tile_dir in sorted(source_dir.iterdir()):
                if not tile_dir.is_dir():
                    continue
                tc = tile_dir.name
                for img_file in sorted(tile_dir.iterdir()):
                    if img_file.suffix.lower() in (".jpg", ".jpeg", ".png"):
                        entry_id = f"local_{src_name}_{tc}_{img_file.stem}"
                        entries.append({
                            "id": entry_id,
                            "tile_code": tc,
                            "source": src_name,
                            "image_path": str(img_file),
                            "created_at": "",
                        })
        if tile_code:
            entries = [e for e in entries if e["tile_code"] == tile_code]
        if source:
            entries = [e for e in entries if e["source"] == source]
        return entries

    # ── Get image ──

    def get_image(self, entry_id: str) -> bytes | None:
        # Local fallback (dev)
        if entry_id.startswith("local_"):
            return self._get_local_image(entry_id)

        # GCS — look up image_path from index
        try:
            index = self._load_index()
            for meta in index:
                if meta.get("id") == entry_id:
                    image_path = meta.get("image_path", "")
                    if image_path:
                        blob = self._bucket().blob(image_path)
                        if blob.exists():
                            return blob.download_as_bytes()
                    break
        except Exception:
            pass
        return None

    def _get_local_image(self, entry_id: str) -> bytes | None:
        entries = self._list_local()
        for e in entries:
            if e["id"] == entry_id:
                path = Path(e["image_path"])
                if path.exists():
                    return path.read_bytes()
        return None

    # ── Delete ──

    def delete_entry(self, entry_id: str) -> bool:
        if entry_id.startswith("local_"):
            return False
        if entry_id.startswith("pub_"):
            return False  # Public datasets are read-only
        try:
            bucket = self._bucket()
            deleted = False
            for prefix in [f"{self.prefix}/images/", f"{self.prefix}/meta/"]:
                blobs = list(bucket.list_blobs(prefix=prefix))
                for blob in blobs:
                    if entry_id in blob.name:
                        blob.delete()
                        deleted = True
            # Update index
            if deleted:
                try:
                    index = self._load_index()
                    index = [e for e in index if e.get("id") != entry_id]
                    self._save_index(index)
                except Exception as exc:
                    logger.warning("Failed to update index on delete: %s", exc)
                    self._gcs_meta_cache = None
            return deleted
        except Exception:
            return False

    # ── Stats ──

    def get_stats(self) -> dict:
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
