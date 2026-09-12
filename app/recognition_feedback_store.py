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

    def delete_by_uid(self, uid: str) -> int:
        """Rewrite the JSONL file without entries saved with this uid."""
        if not self.path.exists():
            return 0
        kept: list[str] = []
        deleted = 0
        with self.path.open("r", encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    kept.append(line)
                    continue
                if entry.get("payload", {}).get("uid") == uid:
                    deleted += 1
                else:
                    kept.append(line)
        if deleted:
            with self.path.open("w", encoding="utf-8") as f:
                f.write("\n".join(kept) + ("\n" if kept else ""))
        return deleted
