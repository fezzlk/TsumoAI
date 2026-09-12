from __future__ import annotations

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from app.auth import get_current_user, require_admin


def _credentials(token: str = "fake-token") -> HTTPAuthorizationCredentials:
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)


def test_get_current_user_requires_credentials():
    with pytest.raises(HTTPException) as exc_info:
        get_current_user(None)
    assert exc_info.value.status_code == 401
    assert "Firebase ID token is required" in exc_info.value.detail


def test_get_current_user_verifies_token_when_app_already_initialized(monkeypatch):
    monkeypatch.setattr("firebase_admin.get_app", lambda: object())
    monkeypatch.setattr(
        "firebase_admin.auth.verify_id_token",
        lambda token, check_revoked=True: {"uid": "user-1", "admin": True},
    )
    result = get_current_user(_credentials())
    assert result == {"uid": "user-1", "admin": True}


def test_get_current_user_initializes_app_when_not_yet_initialized(monkeypatch):
    def raise_not_initialized():
        raise ValueError("no app")

    initialized = {}

    def fake_initialize_app(options=None):
        initialized["options"] = options
        return object()

    monkeypatch.setattr("firebase_admin.get_app", raise_not_initialized)
    monkeypatch.setattr("firebase_admin.initialize_app", fake_initialize_app)
    monkeypatch.setattr(
        "firebase_admin.auth.verify_id_token",
        lambda token, check_revoked=True: {"uid": "user-1"},
    )

    result = get_current_user(_credentials())
    assert result == {"uid": "user-1"}
    assert "options" in initialized


def test_get_current_user_rejects_invalid_or_revoked_token(monkeypatch):
    monkeypatch.setattr("firebase_admin.get_app", lambda: object())

    def raise_invalid(token, check_revoked=True):
        raise ValueError("token revoked")

    monkeypatch.setattr("firebase_admin.auth.verify_id_token", raise_invalid)

    with pytest.raises(HTTPException) as exc_info:
        get_current_user(_credentials())
    assert exc_info.value.status_code == 401
    assert "Invalid or expired Firebase ID token" in exc_info.value.detail


def test_get_current_user_reraises_http_exception_unwrapped(monkeypatch):
    """An HTTPException raised inside the verification path must pass through
    unchanged, not get re-wrapped as a generic 401."""
    monkeypatch.setattr("firebase_admin.get_app", lambda: object())

    def raise_http_exception(token, check_revoked=True):
        raise HTTPException(status_code=503, detail="firebase temporarily unavailable")

    monkeypatch.setattr("firebase_admin.auth.verify_id_token", raise_http_exception)

    with pytest.raises(HTTPException) as exc_info:
        get_current_user(_credentials())
    assert exc_info.value.status_code == 503
    assert exc_info.value.detail == "firebase temporarily unavailable"


def test_require_admin_returns_user_when_admin_true():
    user = {"uid": "user-1", "admin": True}
    assert require_admin(user) == user


def test_require_admin_rejects_non_admin_user():
    with pytest.raises(HTTPException) as exc_info:
        require_admin({"uid": "user-1"})
    assert exc_info.value.status_code == 403
