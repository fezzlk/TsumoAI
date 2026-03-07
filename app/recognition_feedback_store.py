from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from app.config import settings


class RecognitionFeedbackStore:
    def __init__(self, path: str | None = None) -> None:
        self.path = Path(path or settings.recognition_feedback_path)

    def save(self, payload: dict) -> dict:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        feedback_id = str(uuid4())
        now = datetime.now(timezone.utc).isoformat()
        entry = {
            "feedback_id": feedback_id,
            "saved_at": now,
            "payload": payload,
        }
        with self.path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        return {"path": str(self.path), "feedback_id": feedback_id}
