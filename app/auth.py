from __future__ import annotations

from typing import Any

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import settings


bearer = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
) -> dict[str, Any]:
    if credentials is None:
        raise HTTPException(status_code=401, detail="Firebase ID token is required")
    try:
        from firebase_admin import auth, get_app, initialize_app

        try:
            get_app()
        except ValueError:
            initialize_app(options={"projectId": settings.firebase_project_id} if settings.firebase_project_id else None)
        return auth.verify_id_token(credentials.credentials, check_revoked=True)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid or expired Firebase ID token") from exc


def require_admin(user: dict[str, Any] = Depends(get_current_user)) -> dict[str, Any]:
    if user.get("admin") is not True:
        raise HTTPException(status_code=403, detail="Administrator role is required")
    return user
