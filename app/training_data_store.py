"""Training data store: GCS for user uploads + local files for public datasets."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from google.cloud import storage

from app.config import settings

# Local training data directory (converted public datasets)
LOCAL_DATA_DIR = Path(__file__).resolve().parent.parent / "ml" / "training_data"


class TrainingDataStore:
    def __init__(self) -> None:
        self.bucket_name = settings.gcs_bucket_name
        self.prefix = "training-data"
        self._client: storage.Client | None = None
        self._local_cache: list[dict] | None = None

    def _get_client(self) -> storage.Client:
        if self._client is None:
            self._client = storage.Client(project=settings.gcp_project)
        return self._client

    def _bucket(self) -> storage.Bucket:
        if not self.bucket_name:
            raise ValueError("GCS bucket is not configured")
        return self._get_client().bucket(self.bucket_name)

    # ── Upload (GCS only) ──

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
        return {"id": entry_id, "image_path": image_name}

    # ── List (GCS + local) ──

    def list_entries(self, tile_code: str | None = None, source: str | None = None,
                     limit: int = 500) -> list[dict]:
        entries: list[dict] = []

        # Local datasets
        if source is None or source != "user":
            entries.extend(self._list_local(tile_code=tile_code, source=source))

        # GCS user uploads
        if source is None or source == "user":
            try:
                entries.extend(self._list_gcs(tile_code=tile_code, source=source))
            except Exception:
                pass  # GCS not configured is ok

        entries.sort(key=lambda e: e.get("tile_code", ""))
        return entries[:limit]

    def _list_local(self, tile_code: str | None = None, source: str | None = None) -> list[dict]:
        """List entries from local ml/training_data/ directory."""
        if self._local_cache is not None:
            entries = self._local_cache
        else:
            entries = []
            if LOCAL_DATA_DIR.exists():
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
            self._local_cache = entries

        result = entries
        if tile_code:
            result = [e for e in result if e["tile_code"] == tile_code]
        if source:
            result = [e for e in result if e["source"] == source]
        return result

    def _list_gcs(self, tile_code: str | None = None, source: str | None = None) -> list[dict]:
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
        return entries

    # ── Get image ──

    def get_image(self, entry_id: str) -> bytes | None:
        # Local file
        if entry_id.startswith("local_"):
            return self._get_local_image(entry_id)
        # GCS
        try:
            bucket = self._bucket()
            blobs = list(bucket.list_blobs(prefix=f"{self.prefix}/images/"))
            for blob in blobs:
                if entry_id in blob.name:
                    return blob.download_as_bytes()
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

    # ── Delete (GCS only) ──

    def delete_entry(self, entry_id: str) -> bool:
        if entry_id.startswith("local_"):
            return False  # Local datasets are read-only
        try:
            bucket = self._bucket()
            deleted = False
            for prefix in [f"{self.prefix}/images/", f"{self.prefix}/meta/"]:
                blobs = list(bucket.list_blobs(prefix=prefix))
                for blob in blobs:
                    if entry_id in blob.name:
                        blob.delete()
                        deleted = True
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
