from __future__ import annotations

import json
from io import BytesIO
from pathlib import Path
from uuid import UUID

from fastapi import FastAPI, File, Form, HTTPException, Query, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from PIL import Image

from app.config import settings
from app.gcs_feedback_store import GCSFeedbackStore
from app.hand_extraction import extract_hand_from_image, hand_shape_from_estimate_with_warnings
from app.recognition_feedback_store import RecognitionFeedbackStore
from app.recognition_job_manager import RecognitionJobManager
from app.hand_scoring import score_hand_shape
from app.repository import InMemoryRepository
from app.schemas import (
    ContextInput,
    DatasetUploadRequest,
    DatasetUploadResponse,
    RecognizeJobCreateResponse,
    RecognizeJobStatusResponse,
    RecognitionFeedbackRequest,
    RecognitionFeedbackResponse,
    RecognizeAndScoreResponse,
    RecognizeResponse,
    ResultGetResponse,
    RuleSet,
    ScoreFeedbackRequest,
    ScoreFeedbackResponse,
    ScoreRequest,
    ScoreResponse,
)
from app.validators import validate_score_request, validate_tile

try:  # pragma: no cover
    from pillow_heif import register_heif_opener

    register_heif_opener()
    HEIC_ENABLED = True
except Exception:  # pragma: no cover
    HEIC_ENABLED = False

app = FastAPI(title="Mahjong Hand Score PoC", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
repo = InMemoryRepository(ttl_hours=settings.image_ttl_hours)
recognition_jobs = RecognitionJobManager(repo=repo, model_name=settings.openai_model)
STATIC_DIR = Path(__file__).resolve().parent / "static"
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
gcs_feedback_store = GCSFeedbackStore()
gcs_dataset_store = GCSFeedbackStore(prefix=settings.gcs_dataset_prefix)
recognition_feedback_store = RecognitionFeedbackStore()

from app.training_data_store import TrainingDataStore
training_data_store = TrainingDataStore()


@app.get("/")
def root() -> HTMLResponse:
    return HTMLResponse("""<!DOCTYPE html>
<html lang="ja"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>TsumoAI</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,sans-serif;background:#1a1a2e;color:#e0e0e0;
  display:flex;flex-direction:column;align-items:center;min-height:100vh;padding:40px 16px}
h1{font-size:28px;margin-bottom:8px;color:#fff}
.subtitle{color:#888;margin-bottom:32px;font-size:14px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:12px;width:100%;max-width:700px}
a.card{display:flex;align-items:center;gap:12px;background:#16213e;padding:16px;border-radius:10px;
  text-decoration:none;color:#e0e0e0;transition:background .15s}
a.card:hover{background:#1a3055}
.icon{font-size:28px;width:40px;text-align:center}
.card-body .name{font-size:15px;font-weight:bold;color:#4ecca3}
.card-body .desc{font-size:11px;color:#999;margin-top:2px}
</style></head><body>
<h1>TsumoAI</h1>
<p class="subtitle">麻雀点数計算 &amp; 牌認識</p>
<div class="grid">
  <a class="card" href="/score-ui"><div class="icon">🀄</div><div class="card-body"><div class="name">点数計算UI</div><div class="desc">牌画像から点数を計算</div></div></a>
  <a class="card" href="/training-data"><div class="icon">📚</div><div class="card-body"><div class="name">学習データ一覧</div><div class="desc">牌分類モデルの学習データ管理</div></div></a>
  <a class="card" href="/score-dataset"><div class="icon">📊</div><div class="card-body"><div class="name">スコアデータセット</div><div class="desc">点数計算のデータセット管理</div></div></a>
  <a class="card" href="/docs"><div class="icon">📖</div><div class="card-body"><div class="name">API ドキュメント</div><div class="desc">FastAPI Swagger UI</div></div></a>
  <a class="card" href="/health"><div class="icon">💚</div><div class="card-body"><div class="name">ヘルスチェック</div><div class="desc">サーバーの稼働状態</div></div></a>
</div>
</body></html>""")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/score-ui")
def score_ui() -> FileResponse:
    return FileResponse(STATIC_DIR / "score_ui.html")


@app.get("/score-dataset")
def score_dataset() -> FileResponse:
    return FileResponse(STATIC_DIR / "score_dataset.html")


def _to_recognition_image_bytes(upload: UploadFile, image_bytes: bytes) -> tuple[int, int, bytes]:
    try:
        img = Image.open(BytesIO(image_bytes))
        width, height = img.size
    except Exception as exc:  # pragma: no cover
        filename = (upload.filename or "").lower()
        content_type = (upload.content_type or "").lower()
        if (filename.endswith(".heic") or filename.endswith(".heif") or "heic" in content_type or "heif" in content_type) and not HEIC_ENABLED:
            raise HTTPException(
                status_code=400,
                detail="HEIC/HEIF is not enabled. Install pillow-heif and restart the server.",
            ) from exc
        raise HTTPException(status_code=400, detail="invalid image file") from exc

    rgb = img.convert("RGB")
    out = BytesIO()
    rgb.save(out, format="JPEG", quality=95)
    return width, height, out.getvalue()


def _build_recognize_response(width: int, height: int, game_id: str | None, payload: dict) -> RecognizeResponse:
    model_name = payload.get("model_name", settings.openai_model)
    model_version = "local" if model_name == "tflite-mobilenetv2" else "api-current"
    record = repo.create(
        "recognition",
        {
            "game_id": game_id,
            "image": {"width": width, "height": height},
            "hand_estimate": {"tiles_count": payload["tiles_count"], "slots": payload["slots"]},
            "model": {"name": model_name, "version": model_version},
            "warnings": payload.get("warnings", []),
        },
    )
    return RecognizeResponse(
        recognition_id=record.id,
        status="ok",
        image={
            "width": width,
            "height": height,
            "expires_at": record.expires_at,
        },
        hand_estimate=record.data["hand_estimate"],
        model=record.data["model"],
        warnings=record.data["warnings"],
    )


@app.post("/api/v1/recognize", response_model=RecognizeResponse)
async def recognize(image: UploadFile = File(...), game_id: str | None = Form(None)) -> RecognizeResponse:
    image_bytes = await image.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="image is required")

    width, height, recognition_image_bytes = _to_recognition_image_bytes(image, image_bytes)
    payload = extract_hand_from_image(recognition_image_bytes)
    return _build_recognize_response(width=width, height=height, game_id=game_id, payload=payload)


@app.post("/api/v1/recognize-only", response_model=RecognizeResponse)
async def recognize_only(image: UploadFile = File(...), game_id: str | None = Form(None)) -> RecognizeResponse:
    """Dedicated image-recognition endpoint."""
    return await recognize(image=image, game_id=game_id)


@app.post("/api/v1/recognize-only/jobs", response_model=RecognizeJobCreateResponse)
async def create_recognize_job(image: UploadFile = File(...), game_id: str | None = Form(None)) -> RecognizeJobCreateResponse:
    image_bytes = await image.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="image is required")
    width, height, recognition_image_bytes = _to_recognition_image_bytes(image, image_bytes)
    job = recognition_jobs.create_job(
        image_bytes=recognition_image_bytes,
        width=width,
        height=height,
        game_id=game_id,
    )
    return RecognizeJobCreateResponse(job_id=job.id, status=job.status, cancel_requested=job.cancel_requested)


@app.get("/api/v1/recognize-only/jobs/{job_id}", response_model=RecognizeJobStatusResponse)
def get_recognize_job(job_id: UUID) -> RecognizeJobStatusResponse:
    job = recognition_jobs.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    result = RecognizeResponse.model_validate(job.result) if job.result else None
    return RecognizeJobStatusResponse(
        job_id=job.id,
        status=job.status,
        cancel_requested=job.cancel_requested,
        created_at=job.created_at,
        updated_at=job.updated_at,
        result=result,
        error=job.error,
    )


@app.post("/api/v1/recognize-only/jobs/{job_id}/cancel", response_model=RecognizeJobStatusResponse)
def cancel_recognize_job(job_id: UUID) -> RecognizeJobStatusResponse:
    job = recognition_jobs.request_cancel(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    result = RecognizeResponse.model_validate(job.result) if job.result else None
    return RecognizeJobStatusResponse(
        job_id=job.id,
        status=job.status,
        cancel_requested=job.cancel_requested,
        created_at=job.created_at,
        updated_at=job.updated_at,
        result=result,
        error=job.error,
    )


@app.post("/api/v1/score", response_model=ScoreResponse)
def score(req: ScoreRequest) -> ScoreResponse:
    validate_score_request(req)
    try:
        result = score_hand_shape(req.hand, req.context, req.rules)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    record = repo.create(
        "score",
        {
            "recognition_id": str(req.recognition_id) if req.recognition_id else None,
            "hand": req.hand.model_dump(),
            "context": req.context.model_dump(),
            "rules": req.rules.model_dump(),
            "result": result.model_dump(),
            "warnings": [],
        },
    )
    return ScoreResponse(score_id=record.id, status="ok", result=result, warnings=[])


@app.post("/api/v1/recognize-and-score", response_model=RecognizeAndScoreResponse)
async def recognize_and_score(
    image: UploadFile = File(...),
    context_json: str = Form(...),
    rules_json: str = Form(...),
) -> RecognizeAndScoreResponse:
    recognized = await recognize(image=image)
    try:
        context = ContextInput.model_validate(json.loads(context_json))
        rules = RuleSet.model_validate(json.loads(rules_json))
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"Invalid JSON payload: {exc}") from exc

    try:
        hand_input, conversion_warnings = hand_shape_from_estimate_with_warnings(recognized.hand_estimate.model_dump())
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    score_req = ScoreRequest(
        recognition_id=recognized.recognition_id,
        hand=hand_input,
        context=context,
        rules=rules,
    )
    scored = score(score_req)
    scored.warnings = recognized.warnings + conversion_warnings
    return RecognizeAndScoreResponse(recognition=recognized, score=scored)


@app.get("/api/v1/results/{item_id}", response_model=ResultGetResponse)
def get_result(item_id: UUID) -> ResultGetResponse:
    record = repo.get(item_id)
    if not record:
        raise HTTPException(status_code=404, detail="record not found or expired")
    return ResultGetResponse(
        id=record.id,
        type=record.type,
        created_at=record.created_at,
        expires_at=record.expires_at,
        data=record.data,
    )


@app.post("/api/v1/score/feedback", response_model=ScoreFeedbackResponse)
def score_feedback(req: ScoreFeedbackRequest) -> ScoreFeedbackResponse:
    payload = req.model_dump(mode="json")
    payload["comment"] = req.comment.strip()
    try:
        storage_info = gcs_feedback_store.save(payload)
    except ValueError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:  # pragma: no cover
        raise HTTPException(status_code=500, detail=f"Failed to save feedback to GCS: {exc}") from exc
    return ScoreFeedbackResponse(status="ok", storage=storage_info)


@app.post("/api/v1/recognition/feedback", response_model=RecognitionFeedbackResponse)
def recognition_feedback(req: RecognitionFeedbackRequest) -> RecognitionFeedbackResponse:
    if len(req.corrected_tiles) != 14:
        raise HTTPException(status_code=422, detail="corrected_tiles must contain exactly 14 tiles")
    for tile in req.corrected_tiles:
        validate_tile(tile)

    payload = req.model_dump(mode="json")
    payload["comment"] = req.comment.strip()
    storage_info = recognition_feedback_store.save(payload)
    return RecognitionFeedbackResponse(status="ok", storage=storage_info)


@app.post("/api/v1/dataset/upload", response_model=DatasetUploadResponse)
def upload_dataset(req: DatasetUploadRequest) -> DatasetUploadResponse:
    if not req.entries:
        raise HTTPException(status_code=422, detail="entries must not be empty")
    try:
        payload = {"entries": req.entries}
        if req.contributor:
            payload["contributor"] = req.contributor
        storage_info = gcs_dataset_store.save(payload, contributor=req.contributor)
    except ValueError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:  # pragma: no cover
        raise HTTPException(status_code=500, detail=f"Failed to upload dataset to GCS: {exc}") from exc
    return DatasetUploadResponse(status="ok", count=len(req.entries), storage=storage_info)


@app.get("/api/v1/dataset/list")
def list_datasets() -> dict:
    bucket_name = gcs_dataset_store.bucket_name
    prefix = gcs_dataset_store.prefix
    if not bucket_name:
        raise HTTPException(status_code=503, detail="GCS bucket is not configured")
    client = gcs_dataset_store._get_client()
    bucket = client.bucket(bucket_name)
    blobs = bucket.list_blobs(prefix=prefix + "/")
    files = []
    for blob in blobs:
        if blob.name.endswith(".json"):
            files.append({
                "name": blob.name,
                "size": blob.size,
                "updated": blob.updated.isoformat() if blob.updated else None,
            })
    files.sort(key=lambda f: f["updated"] or "", reverse=True)
    return {"files": files}


@app.get("/api/v1/dataset/download")
def download_dataset(name: str = Query(...)) -> JSONResponse:
    bucket_name = gcs_dataset_store.bucket_name
    if not bucket_name:
        raise HTTPException(status_code=503, detail="GCS bucket is not configured")
    client = gcs_dataset_store._get_client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(name)
    if not blob.exists():
        raise HTTPException(status_code=404, detail="file not found")
    data = json.loads(blob.download_as_text())
    return JSONResponse(content=data)


# --- Training data endpoints ---

from app.schemas import TrainingDataListResponse, TrainingDataUploadResponse


@app.post("/api/v1/training-data/upload", response_model=TrainingDataUploadResponse)
async def upload_training_data(
    image: UploadFile = File(...),
    tile_code: str = Form(...),
    source: str = Form("user"),
) -> TrainingDataUploadResponse:
    validate_tile(tile_code)
    image_bytes = await image.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="image is required")
    try:
        result = training_data_store.upload(image_bytes, tile_code, source)
    except ValueError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return TrainingDataUploadResponse(status="ok", **result)


@app.get("/api/v1/training-data/list")
def list_training_data(
    tile_code: str | None = Query(None),
    source: str | None = Query(None),
    limit: int = Query(500),
    refresh: bool = Query(False),
) -> dict:
    try:
        if refresh:
            training_data_store.invalidate_cache()
        entries = training_data_store.list_entries(tile_code=tile_code, source=source, limit=limit)
        stats = training_data_store.get_stats()
    except ValueError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return {"entries": entries, "stats": stats}


@app.get("/api/v1/training-data/image/{entry_id}")
def get_training_image(entry_id: str) -> Response:
    try:
        data = training_data_store.get_image(entry_id)
    except ValueError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    if data is None:
        raise HTTPException(status_code=404, detail="image not found")
    return Response(content=data, media_type="image/jpeg")


@app.delete("/api/v1/training-data/{entry_id}")
def delete_training_data(entry_id: str) -> dict:
    try:
        deleted = training_data_store.delete_entry(entry_id)
    except ValueError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    if not deleted:
        raise HTTPException(status_code=404, detail="entry not found")
    return {"status": "deleted", "id": entry_id}


@app.get("/training-data")
def training_data_viewer() -> FileResponse:
    return FileResponse(STATIC_DIR / "training_data.html")




# --- Model retraining endpoints ---


@app.get("/api/v1/model/latest")
def get_latest_model_info() -> dict:
    """Get info about the latest trained model on GCS."""
    if not settings.gcs_bucket_name:
        raise HTTPException(status_code=503, detail="GCS not configured")
    try:
        from google.cloud import storage
        client = storage.Client(project=settings.gcp_project)
        bucket = client.bucket(settings.gcs_bucket_name)
        blob = bucket.blob("models/latest.json")
        if not blob.exists():
            return {"status": "no_model", "message": "学習済みモデルがありません"}
        meta = json.loads(blob.download_as_text())
        return {"status": "ok", **meta}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/model/retrain")
def trigger_retrain() -> dict:
    """Trigger model retraining via Cloud Build."""
    if not settings.gcp_project:
        raise HTTPException(status_code=503, detail="GCP project not configured")
    try:
        from google.cloud.devtools import cloudbuild_v1
        client = cloudbuild_v1.CloudBuildClient()

        build = cloudbuild_v1.Build(
            steps=[
                cloudbuild_v1.BuildStep(
                    name="python:3.11-slim",
                    entrypoint="bash",
                    args=[
                        "-c",
                        "pip install --no-cache-dir tensorflow-cpu==2.15.1 'scikit-learn>=1.3' 'Pillow>=10.0' 'google-cloud-storage>=2.0' && "
                        f"cd ml && python train.py --epochs 50 --gcs-bucket {settings.gcs_bucket_name} --upload",
                    ],
                )
            ],
            source=cloudbuild_v1.Source(
                repo_source=cloudbuild_v1.RepoSource(
                    project_id=settings.gcp_project,
                    repo_name="TsumoAI",
                    branch_name="main",
                )
            ),
            options=cloudbuild_v1.BuildOptions(
                logging=cloudbuild_v1.BuildOptions.LoggingMode.CLOUD_LOGGING_ONLY,
            ),
            timeout={"seconds": 3600},
        )

        operation = client.create_build(project_id=settings.gcp_project, build=build)
        build_id = operation.metadata.build.id
        return {
            "status": "started",
            "build_id": build_id,
            "message": "モデル再学習を開始しました（完了まで30〜60分）",
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Cloud Build起動エラー: {e}")


@app.get("/api/v1/model/download/{filename}")
def download_model_file(filename: str) -> Response:
    """Download the latest model file (tflite or labels.txt) from GCS."""
    if filename not in ("tile_classifier.tflite", "labels.txt"):
        raise HTTPException(status_code=400, detail="Invalid filename")
    if not settings.gcs_bucket_name:
        raise HTTPException(status_code=503, detail="GCS not configured")
    try:
        from google.cloud import storage
        client = storage.Client(project=settings.gcp_project)
        bucket = client.bucket(settings.gcs_bucket_name)

        # Get latest version
        latest_blob = bucket.blob("models/latest.json")
        if not latest_blob.exists():
            raise HTTPException(status_code=404, detail="No model available")
        meta = json.loads(latest_blob.download_as_text())
        version = meta["version"]

        blob = bucket.blob(f"models/{version}/{filename}")
        if not blob.exists():
            raise HTTPException(status_code=404, detail=f"{filename} not found")

        data = blob.download_as_bytes()
        content_type = "application/octet-stream" if filename.endswith(".tflite") else "text/plain"
        return Response(content=data, media_type=content_type,
                        headers={"X-Model-Version": version})
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
