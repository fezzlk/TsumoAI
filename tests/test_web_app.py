from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.web_app import mount_web_app


def test_web_release_is_served_under_app_without_shadowing_api(tmp_path):
    release = tmp_path / "web"
    release.mkdir()
    (release / "index.html").write_text('<base href="/app/">TsumoAI')
    (release / "runtime.wasm").write_bytes(b"\x00asm" + b"a" * 2000)
    (tmp_path / "secret.txt").write_text("private")
    app = FastAPI()

    @app.get("/api/example")
    def example():
        return {"ok": True}

    mount_web_app(app, release)
    client = TestClient(app)
    index = client.get("/app")
    assert index.url.path == "/app/"
    assert '<base href="/app/">' in index.text
    assert index.headers["cache-control"] == "no-cache"
    assert client.get("/api/example").json() == {"ok": True}
    wasm = client.get("/app/runtime.wasm", headers={"Accept-Encoding": "gzip"})
    assert wasm.headers["content-type"] == "application/wasm"
    assert wasm.headers["content-encoding"] == "gzip"
    assert wasm.headers["x-content-type-options"] == "nosniff"
    assert client.get("/app/missing.js").status_code == 404
    assert client.get("/app/%2e%2e/secret.txt").status_code == 404


def test_api_only_development_does_not_require_flutter_build(tmp_path):
    app = FastAPI()
    mount_web_app(app, tmp_path / "missing")
    assert TestClient(app).get("/app/").status_code == 404
