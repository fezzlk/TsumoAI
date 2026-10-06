"""Serve the Flutter release alongside the API, when included in the image."""

from pathlib import Path

from fastapi import FastAPI
from starlette.middleware.gzip import GZipMiddleware
from starlette.staticfiles import StaticFiles


class WebAppFiles(StaticFiles):
    async def get_response(self, path, scope):
        response = await super().get_response(path, scope)
        # Flutter's stable filenames must revalidate after each release.
        response.headers["Cache-Control"] = "no-cache"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response


def mount_web_app(app: FastAPI, directory: Path) -> None:
    # API-only local development and unit tests do not require a Flutter build.
    if (directory / "index.html").is_file():
        app.mount(
            "/app",
            GZipMiddleware(WebAppFiles(directory=directory, html=True), minimum_size=1000),
            name="web-app",
        )
