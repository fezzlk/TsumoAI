from __future__ import annotations

from app.recognition_feedback_store import RecognitionFeedbackStore


def test_delete_by_uid_removes_only_matching_entries(tmp_path):
    store = RecognitionFeedbackStore(path=str(tmp_path / "recognition_feedback.jsonl"))
    store.save({"comment": "a", "uid": "user-1"})
    store.save({"comment": "b", "uid": "user-2"})
    store.save({"comment": "c", "uid": "user-1"})

    deleted = store.delete_by_uid("user-1")

    assert deleted == 2
    remaining = store.path.read_text(encoding="utf-8").strip().splitlines()
    assert len(remaining) == 1
    assert '"uid": "user-2"' in remaining[0]


def test_delete_by_uid_on_missing_file_returns_zero(tmp_path):
    store = RecognitionFeedbackStore(path=str(tmp_path / "does_not_exist.jsonl"))
    assert store.delete_by_uid("user-1") == 0
