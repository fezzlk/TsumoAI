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
from app.hand_extraction import extract_hand_from_image, hand_shape_from_estimate
from app.hand_scoring import score_hand_shape
from app.repository import InMemoryRepository
from app.schemas import (
    ContextInput,
    RecognizeAndScoreResponse,
    RecognizeResponse,
    ResultGetResponse,
    RuleSet,
    ScoreFeedbackRequest,
    ScoreFeedbackResponse,
    ScoreRequest,
    ScoreResponse,
)
from app.validators import validate_score_request

app = FastAPI(title="Mahjong Hand Score PoC", version="0.1.0")
repo = InMemoryRepository(ttl_hours=settings.image_ttl_hours)
STATIC_DIR = Path(__file__).resolve().parent / "static"
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
gcs_feedback_store = GCSFeedbackStore()


@app.get("/")
def root() -> dict[str, str]:
    return {
        "message": "Mahjong Hand Score PoC API",
        "docs": "/docs",
        "health": "/health",
        "score_ui": "/score-ui",
    }


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/score-ui")
def score_ui() -> FileResponse:
    return FileResponse(STATIC_DIR / "score_ui.html")


@app.post("/api/v1/recognize", response_model=RecognizeResponse)
async def recognize(image: UploadFile = File(...), game_id: str | None = Form(None)) -> RecognizeResponse:
    image_bytes = await image.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="image is required")

    try:
        img = Image.open(BytesIO(image_bytes))
        width, height = img.size
    except Exception as exc:  # pragma: no cover
        raise HTTPException(status_code=400, detail="invalid image file") from exc

    payload = extract_hand_from_image(image_bytes)
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


@app.post("/api/v1/score", response_model=ScoreResponse)
def score(req: ScoreRequest) -> ScoreResponse:
    validate_score_request(req)
    result = score_hand_shape(req.hand, req.context, req.rules)
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

    score_req = ScoreRequest(
        recognition_id=recognized.recognition_id,
        hand=hand_shape_from_estimate(recognized.hand_estimate.model_dump()),
        context=context,
        rules=rules,
    )
    scored = score(score_req)
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
