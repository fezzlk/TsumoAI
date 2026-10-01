from __future__ import annotations

import hashlib
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Callable

from app.config import resolve_gcp_project, settings


class AIUsageLimitReached(RuntimeError):
    def __init__(self, status: dict[str, Any]) -> None:
        super().__init__("monthly AI chat limit reached")
        self.status = status


@dataclass(frozen=True)
class AIUsageReservation:
    status: dict[str, Any]
    source: str


class AIUsageStore:
    """Firestore-backed monthly AI allowance.

    Subjects are hashed before becoming document IDs. A subject is either a
    verified Firebase uid or an app-install identifier supplied by the mobile
    client. Consumption is transactional so concurrent sends cannot exceed the
    allowance. Failed model calls are refunded by the API layer.
    """

    def __init__(
        self,
        *,
        client: Any | None = None,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._client = client
        self._now = now or (lambda: datetime.now(timezone.utc))

    def _firestore(self):
        if self._client is None:
            from google.cloud import firestore

            self._client = firestore.Client(project=resolve_gcp_project())
        return self._client

    def _period(self) -> tuple[str, datetime]:
        now = self._now().astimezone(timezone.utc)
        period = f"{now.year:04d}-{now.month:02d}"
        if now.month == 12:
            reset = datetime(now.year + 1, 1, 1, tzinfo=timezone.utc)
        else:
            reset = datetime(now.year, now.month + 1, 1, tzinfo=timezone.utc)
        return period, reset

    def _document(self, subject: str):
        period, _ = self._period()
        digest = hashlib.sha256(subject.encode("utf-8")).hexdigest()
        return self._firestore().collection("ai_usage").document(f"{period}_{digest}")

    def _defaults(self) -> dict[str, Any]:
        period, reset = self._period()
        return {
            "period": period,
            "plan": "free",
            "included_limit": settings.free_ai_chat_requests_per_month,
            "included_used": 0,
            "bonus_granted": 0,
            "bonus_used": 0,
            "resets_at": reset,
        }

    def _normalized(self, data: dict[str, Any] | None) -> dict[str, Any]:
        values = {**self._defaults(), **(data or {})}
        plan = values.get("plan")
        if plan not in {"free", "subscription"}:
            plan = "free"
        values["plan"] = plan
        if "included_limit" not in (data or {}):
            values["included_limit"] = (
                settings.subscription_ai_chat_requests_per_month
                if plan == "subscription"
                else settings.free_ai_chat_requests_per_month
            )
        for key in ("included_limit", "included_used", "bonus_granted", "bonus_used"):
            values[key] = max(0, int(values.get(key, 0)))
        return values

    def _status(self, data: dict[str, Any]) -> dict[str, Any]:
        included_remaining = max(
            0, data["included_limit"] - data["included_used"]
        )
        bonus_remaining = max(0, data["bonus_granted"] - data["bonus_used"])
        resets_at = data["resets_at"]
        if isinstance(resets_at, str):
            resets_at = datetime.fromisoformat(resets_at)
        return {
            "period": data["period"],
            "plan": data["plan"],
            "included_limit": data["included_limit"],
            "included_used": data["included_used"],
            "bonus_remaining": bonus_remaining,
            "remaining": included_remaining + bonus_remaining,
            "resets_at": resets_at,
        }

    def get_status(self, subject: str) -> dict[str, Any]:
        snapshot = self._document(subject).get()
        data = snapshot.to_dict() if snapshot.exists else None
        return self._status(self._normalized(data))

    def consume(self, subject: str) -> AIUsageReservation:
        from google.cloud import firestore

        document = self._document(subject)
        transaction = self._firestore().transaction()

        @firestore.transactional
        def reserve(transaction):
            snapshot = document.get(transaction=transaction)
            data = self._normalized(snapshot.to_dict() if snapshot.exists else None)
            if data["included_used"] < data["included_limit"]:
                data["included_used"] += 1
                source = "included"
            elif data["bonus_used"] < data["bonus_granted"]:
                data["bonus_used"] += 1
                source = "bonus"
            else:
                raise AIUsageLimitReached(self._status(data))
            data["updated_at"] = self._now()
            transaction.set(document, data, merge=True)
            return AIUsageReservation(status=self._status(data), source=source)

        return reserve(transaction)

    def refund(self, subject: str, source: str) -> None:
        from google.cloud import firestore

        document = self._document(subject)
        transaction = self._firestore().transaction()

        @firestore.transactional
        def restore(transaction):
            snapshot = document.get(transaction=transaction)
            if not snapshot.exists:
                return
            data = self._normalized(snapshot.to_dict())
            key = "bonus_used" if source == "bonus" else "included_used"
            data[key] = max(0, data[key] - 1)
            data["updated_at"] = self._now()
            transaction.set(document, data, merge=True)

        restore(transaction)
