from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import datetime, timezone
from threading import Lock
from typing import Any, Callable
from uuid import UUID, uuid4

from app.hand_extraction import RecognitionCancelledError, extract_hand_from_image
from app.repository import InMemoryRepository


JobStatus = str


@dataclass
class RecognitionJob:
    id: UUID
    status: JobStatus
    created_at: datetime
    updated_at: datetime
    game_id: str | None
    width: int
    height: int
    image_bytes: bytes = field(repr=False)
    cancel_requested: bool = False
    result: dict[str, Any] | None = None
    error: str | None = None


class RecognitionJobManager:
    def __init__(self, repo: InMemoryRepository, model_name: str, max_workers: int = 2) -> None:
        self._repo = repo
        self._model_name = model_name
        self._executor = ThreadPoolExecutor(max_workers=max_workers, thread_name_prefix="recognition-job")
        self._jobs: dict[UUID, RecognitionJob] = {}
        self._lock = Lock()

    def _now(self) -> datetime:
        return datetime.now(timezone.utc)

    def create_job(self, image_bytes: bytes, width: int, height: int, game_id: str | None) -> RecognitionJob:
        now = self._now()
        job = RecognitionJob(
            id=uuid4(),
            status="pending",
            created_at=now,
            updated_at=now,
            game_id=game_id,
            width=width,
            height=height,
            image_bytes=image_bytes,
        )
        with self._lock:
            self._jobs[job.id] = job
        self._executor.submit(self._run_job, job.id)
        return job

    def _run_job(self, job_id: UUID) -> None:
        with self._lock:
            job = self._jobs.get(job_id)
            if not job:
                return
            if job.cancel_requested:
                job.status = "canceled"
                job.updated_at = self._now()
                return
            job.status = "running"
            job.updated_at = self._now()

        try:
            payload = extract_hand_from_image(
                job.image_bytes,
                should_cancel=lambda: self.is_cancel_requested(job_id),
            )
            if self.is_cancel_requested(job_id):
                self._set_canceled(job_id)
                return

            model_name = payload.get("model_name", self._model_name)
            model_version = "local" if model_name == "tflite-mobilenetv2" else "api-current"
            record = self._repo.create(
                "recognition",
                {
                    "game_id": job.game_id,
                    "image": {"width": job.width, "height": job.height},
                    "hand_estimate": {"tiles_count": payload["tiles_count"], "slots": payload["slots"]},
                    "model": {"name": model_name, "version": model_version},
                    "warnings": payload.get("warnings", []),
                },
            )
            result = {
                "recognition_id": record.id,
                "status": "ok",
                "image": {
                    "width": job.width,
                    "height": job.height,
                    "expires_at": record.expires_at,
                },
                "hand_estimate": record.data["hand_estimate"],
                "model": record.data["model"],
                "warnings": record.data["warnings"],
            }
            with self._lock:
                live = self._jobs.get(job_id)
                if not live:
                    return
                if live.cancel_requested:
                    live.status = "canceled"
                    live.result = None
                else:
                    live.status = "completed"
                    live.result = result
                live.image_bytes = b""
                live.updated_at = self._now()
        except RecognitionCancelledError:
            self._set_canceled(job_id)
        except Exception as exc:
            with self._lock:
                live = self._jobs.get(job_id)
                if not live:
                    return
                live.status = "failed"
                live.error = str(exc)
                live.image_bytes = b""
                live.updated_at = self._now()

    def _set_canceled(self, job_id: UUID) -> None:
        with self._lock:
            job = self._jobs.get(job_id)
            if not job:
                return
            job.status = "canceled"
            job.result = None
            job.image_bytes = b""
            job.updated_at = self._now()

    def get_job(self, job_id: UUID) -> RecognitionJob | None:
        with self._lock:
            return self._jobs.get(job_id)

    def request_cancel(self, job_id: UUID) -> RecognitionJob | None:
        with self._lock:
            job = self._jobs.get(job_id)
            if not job:
                return None
            if job.status in {"completed", "failed", "canceled"}:
                return job
            job.cancel_requested = True
            job.updated_at = self._now()
            if job.status == "pending":
                job.status = "canceled"
            return job

    def is_cancel_requested(self, job_id: UUID) -> bool:
        with self._lock:
            job = self._jobs.get(job_id)
            return bool(job and job.cancel_requested)
