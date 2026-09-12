from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

from app.hand_extraction import RecognitionCancelledError
from app.recognition_job_manager import RecognitionJob, RecognitionJobManager
from app.repository import InMemoryRepository


def make_manager() -> RecognitionJobManager:
    return RecognitionJobManager(repo=InMemoryRepository(), model_name="test-model")


def make_job(**overrides) -> RecognitionJob:
    now = datetime.now(timezone.utc)
    defaults = dict(
        id=uuid4(),
        status="pending",
        created_at=now,
        updated_at=now,
        game_id=None,
        width=100,
        height=100,
        image_bytes=b"fake-image",
        cancel_requested=False,
        result=None,
        error=None,
    )
    defaults.update(overrides)
    return RecognitionJob(**defaults)


def sample_payload() -> dict:
    tiles = ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "2p", "2p"]
    slots = [{"index": i, "top": t, "candidates": [{"tile": t, "confidence": 0.9}], "ambiguous": False} for i, t in enumerate(tiles)]
    return {"tiles_count": 14, "slots": slots, "warnings": []}


def test_run_job_returns_immediately_when_job_missing():
    manager = make_manager()
    manager._run_job(uuid4())  # no job registered -> must not raise


def test_run_job_cancels_immediately_when_cancel_requested_before_start(monkeypatch):
    manager = make_manager()
    job = make_job(cancel_requested=True)
    manager._jobs[job.id] = job

    def fail_if_called(*args, **kwargs):
        raise AssertionError("extract_hand_from_image must not be called for a pre-canceled job")

    monkeypatch.setattr("app.recognition_job_manager.extract_hand_from_image", fail_if_called)
    manager._run_job(job.id)
    assert job.status == "canceled"


def test_run_job_completes_successfully(monkeypatch):
    manager = make_manager()
    job = make_job()
    manager._jobs[job.id] = job
    monkeypatch.setattr("app.recognition_job_manager.extract_hand_from_image", lambda image_bytes, should_cancel=None: sample_payload())

    manager._run_job(job.id)

    assert job.status == "completed"
    assert job.result["status"] == "ok"
    assert job.result["hand_estimate"]["tiles_count"] == 14
    assert job.image_bytes == b""


def test_run_job_cancels_when_flagged_right_after_extraction(monkeypatch):
    manager = make_manager()
    job = make_job()
    manager._jobs[job.id] = job

    def fake_extract(image_bytes, should_cancel=None):
        job.cancel_requested = True
        return sample_payload()

    monkeypatch.setattr("app.recognition_job_manager.extract_hand_from_image", fake_extract)
    manager._run_job(job.id)

    assert job.status == "canceled"
    assert job.result is None


def test_run_job_cancels_when_flagged_during_repository_write(monkeypatch):
    manager = make_manager()
    job = make_job()
    manager._jobs[job.id] = job
    monkeypatch.setattr("app.recognition_job_manager.extract_hand_from_image", lambda image_bytes, should_cancel=None: sample_payload())

    original_create = manager._repo.create

    def create_and_cancel(*args, **kwargs):
        job.cancel_requested = True
        return original_create(*args, **kwargs)

    monkeypatch.setattr(manager._repo, "create", create_and_cancel)
    manager._run_job(job.id)

    assert job.status == "canceled"
    assert job.result is None


def test_run_job_returns_when_job_disappears_before_final_write(monkeypatch):
    manager = make_manager()
    job = make_job()
    manager._jobs[job.id] = job

    def fake_extract(image_bytes, should_cancel=None):
        del manager._jobs[job.id]
        return sample_payload()

    monkeypatch.setattr("app.recognition_job_manager.extract_hand_from_image", fake_extract)
    manager._run_job(job.id)  # must not raise even though the job vanished mid-flight


def test_run_job_marks_failed_on_unexpected_exception(monkeypatch):
    manager = make_manager()
    job = make_job()
    manager._jobs[job.id] = job

    def raise_error(image_bytes, should_cancel=None):
        raise RuntimeError("boom")

    monkeypatch.setattr("app.recognition_job_manager.extract_hand_from_image", raise_error)
    manager._run_job(job.id)

    assert job.status == "failed"
    assert job.error == "boom"
    assert job.image_bytes == b""


def test_set_canceled_is_noop_when_job_missing():
    manager = make_manager()
    manager._set_canceled(uuid4())  # must not raise


def test_request_cancel_returns_none_for_unknown_job():
    manager = make_manager()
    assert manager.request_cancel(uuid4()) is None


def test_request_cancel_is_noop_for_terminal_status():
    manager = make_manager()
    job = make_job(status="completed")
    manager._jobs[job.id] = job

    result = manager.request_cancel(job.id)

    assert result is job
    assert job.cancel_requested is False
    assert job.status == "completed"


def test_request_cancel_immediately_cancels_pending_job():
    manager = make_manager()
    job = make_job(status="pending")
    manager._jobs[job.id] = job

    result = manager.request_cancel(job.id)

    assert result.status == "canceled"
    assert job.cancel_requested is True


def test_run_job_cancels_on_recognition_cancelled_error(monkeypatch):
    manager = make_manager()
    job = make_job()
    manager._jobs[job.id] = job

    def raise_cancelled(image_bytes, should_cancel=None):
        raise RecognitionCancelledError("canceled mid-extraction")

    monkeypatch.setattr("app.recognition_job_manager.extract_hand_from_image", raise_cancelled)
    manager._run_job(job.id)

    assert job.status == "canceled"


def test_run_job_returns_when_job_disappears_during_exception_handling(monkeypatch):
    manager = make_manager()
    job = make_job()
    manager._jobs[job.id] = job

    def raise_after_removal(image_bytes, should_cancel=None):
        del manager._jobs[job.id]
        raise RuntimeError("boom")

    monkeypatch.setattr("app.recognition_job_manager.extract_hand_from_image", raise_after_removal)
    manager._run_job(job.id)  # must not raise even though the job vanished before failure handling


def test_create_job_registers_job_and_schedules_execution(monkeypatch):
    manager = make_manager()
    started = []
    monkeypatch.setattr(manager, "_run_job", lambda job_id: started.append(job_id))

    job = manager.create_job(image_bytes=b"fake", width=640, height=480, game_id="game-1")

    assert job.status == "pending"
    assert job.game_id == "game-1"
    assert manager.get_job(job.id) is job
    manager._executor.shutdown(wait=True)
    assert started == [job.id]


def test_get_job_returns_none_for_unknown_id():
    manager = make_manager()
    assert manager.get_job(uuid4()) is None
