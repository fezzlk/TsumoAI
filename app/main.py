from __future__ import annotations

import json
from io import BytesIO
from pathlib import Path
from uuid import UUID

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
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
repo = InMemoryRepository(ttl_hours=settings.image_ttl_hours)
recognition_jobs = RecognitionJobManager(repo=repo, model_name=settings.openai_model)
STATIC_DIR = Path(__file__).resolve().parent / "static"
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
gcs_feedback_store = GCSFeedbackStore()
recognition_feedback_store = RecognitionFeedbackStore()


@app.get("/")
def root() -> dict[str, str]:
    return {
        "message": "Mahjong Hand Score PoC API",
        "docs": "/docs",
        "health": "/health",
        "score_ui": "/score-ui",
        "score_dataset": "/score-dataset",
    }


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
    record = repo.create(
        "recognition",
        {
            "game_id": game_id,
            "image": {"width": width, "height": height},
            "hand_estimate": {"tiles_count": payload["tiles_count"], "slots": payload["slots"]},
            "model": {"name": settings.openai_model, "version": "api-current"},
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
