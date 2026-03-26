"""Upload local public training datasets (camerash, kaggle, etc.) to GCS.

Usage:
    python scripts/upload_training_data_to_gcs.py [--dry-run]

Uploads ml/training_data/<source>/<tile_code>/<image> to:
    gs://<bucket>/training-data/images/<source>/<tile_code>/<image>
    gs://<bucket>/training-data/meta/<source>/<tile_code>/<stem>.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from google.cloud import storage

# -- paths ----------------------------------------------------------------
ROOT = Path(__file__).resolve().parent.parent
LOCAL_DATA_DIR = ROOT / "ml" / "training_data"

sys.path.insert(0, str(ROOT))
from app.config import settings  # noqa: E402


def upload(dry_run: bool = False) -> None:
    bucket_name = settings.gcs_bucket_name
    if not bucket_name:
        print("ERROR: GCS_BUCKET_NAME is not configured in .env")
        sys.exit(1)

    client = storage.Client(project=settings.gcp_project)
    bucket = client.bucket(bucket_name)
    prefix = "training-data"

    if not LOCAL_DATA_DIR.exists():
        print(f"ERROR: {LOCAL_DATA_DIR} does not exist")
        sys.exit(1)

    uploaded = 0
    skipped = 0

    for source_dir in sorted(LOCAL_DATA_DIR.iterdir()):
        if not source_dir.is_dir():
            continue
        source_name = source_dir.name

        for tile_dir in sorted(source_dir.iterdir()):
            if not tile_dir.is_dir():
                continue
            tile_code = tile_dir.name

            for img_file in sorted(tile_dir.iterdir()):
                if img_file.suffix.lower() not in (".jpg", ".jpeg", ".png"):
                    continue

                image_blob_name = f"{prefix}/images/{source_name}/{tile_code}/{img_file.name}"
                meta_blob_name = f"{prefix}/meta/{source_name}/{tile_code}/{img_file.stem}.json"

                meta = {
                    "id": f"pub_{source_name}_{tile_code}_{img_file.stem}",
                    "tile_code": tile_code,
                    "source": source_name,
                    "image_path": image_blob_name,
                    "created_at": "",
                }

                if dry_run:
                    print(f"[DRY-RUN] {img_file} -> {image_blob_name}")
                    uploaded += 1
                    continue

                content_type = "image/png" if img_file.suffix.lower() == ".png" else "image/jpeg"
                bucket.blob(image_blob_name).upload_from_filename(
                    str(img_file), content_type=content_type,
                )
                bucket.blob(meta_blob_name).upload_from_string(
                    json.dumps(meta, ensure_ascii=False),
                    content_type="application/json",
                )
                uploaded += 1

                if uploaded % 50 == 0:
                    print(f"  uploaded {uploaded} files ...")

    print(f"\nDone: uploaded={uploaded}, skipped(already exists)={skipped}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Upload training data to GCS")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be uploaded")
    args = parser.parse_args()
    upload(dry_run=args.dry_run)
