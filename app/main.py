from __future__ import annotations

import json
from io import BytesIO
from pathlib import Path
from uuid import UUID

from fastapi import FastAPI, File, Form, HTTPException, Query, Request, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from PIL import Image

from app.config import settings
from app.room_manager import RoomManager
from app.game_session import (
    GameOptions,
    GameSession,
    apply_draw,
    apply_multi_ron,
    apply_ron,
    apply_tsumo,
    create_game,
    get_dealer_seat,
    get_round_wind,
    undo_last,
)
from app.gcs_feedback_store import GCSFeedbackStore
from app.hand_extraction import extract_hand_from_image, hand_shape_from_estimate_with_warnings
from app.recognition_feedback_store import RecognitionFeedbackStore
from app.recognition_job_manager import RecognitionJobManager
from app.hand_scoring import score_hand_shape
from app.repository import InMemoryRepository
from app.schemas import (
    ClaimSeatRequest,
    ContextInput,
    CreateGameRequest,
    DatasetUploadRequest,
    DatasetUploadResponse,
    DrawRequest,
    GameOptionsResponse,
    GameRoundResponse,
    GameStateResponse,
    PlayerStateResponse,
    RecognizeJobCreateResponse,
    RecognizeJobStatusResponse,
    RecognitionFeedbackRequest,
    RecognitionFeedbackResponse,
    RecognizeAndScoreResponse,
    RecognizeResponse,
    ResultGetResponse,
    MultiRonRequest,
    RonRequest,
    RoundResultResponse,
    RuleSet,
    ScoreFeedbackRequest,
    ScoreFeedbackResponse,
    ScoreRequest,
    ScoreResponse,
    SwapSeatsRequest,
    TsumoRequest,
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
  <a class="card" href="/game"><div class="icon">🎮</div><div class="card-body"><div class="name">対戦記録</div><div class="desc">麻雀対戦の点数管理</div></div></a>
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


# --- Game session endpoints ---

_game_sessions: dict[UUID, GameSession] = {}
_room_code_to_game: dict[str, UUID] = {}
room_manager = RoomManager()


def _game_state_response(session: GameSession) -> GameStateResponse:
    dealer = get_dealer_seat(session)
    wind = get_round_wind(session)
    return GameStateResponse(
        game_id=session.game_id,
        status=session.status,
        players=[
            PlayerStateResponse(seat=p.seat, name=p.name, points=p.points)
            for p in session.players
        ],
        current_round=session.current_round,
        current_dealer=dealer,
        current_round_wind=wind,
        current_honba=session.current_honba,
        current_kyotaku=session.current_kyotaku,
        rounds_played=len(session.rounds),
        created_at=session.created_at,
        options=GameOptionsResponse(
            hakoire_end=session.options.hakoire_end,
            shanyu=session.options.shanyu,
            peinyu=session.options.peinyu,
        ),
    )


def _round_result_response(session: GameSession, record) -> RoundResultResponse:
    return RoundResultResponse(
        round_number=record.round_number,
        round_wind=record.round_wind,
        dealer_seat=record.dealer_seat,
        honba=record.honba,
        result_type=record.result_type,
        winner_seat=record.winner_seat,
        loser_seat=record.loser_seat,
        point_changes={str(k): v for k, v in record.point_changes.items()},
        player_points_after={str(p.seat): p.points for p in session.players},
    )


@app.post("/api/v1/games", response_model=GameRoundResponse, status_code=201)
def create_game_endpoint(req: CreateGameRequest) -> dict:
    options = GameOptions(
        hakoire_end=req.options.hakoire_end,
        shanyu=req.options.shanyu,
        peinyu=req.options.peinyu,
    )
    session = create_game(req.player_names, req.starting_points, req.game_type, options)
    _game_sessions[session.game_id] = session
    _room_code_to_game[session.room_code] = session.game_id
    room_manager.register_room(session.room_code, session.game_id)
    return {
        "game_id": session.game_id,
        "room_code": session.room_code,
        "round_result": RoundResultResponse(
            round_number=0,
            round_wind=get_round_wind(session),
            dealer_seat=get_dealer_seat(session),
            honba=0,
            result_type="init",
            point_changes={},
            player_points_after={str(p.seat): p.points for p in session.players},
        ),
        "game_state": _game_state_response(session),
    }


@app.get("/api/v1/games/{game_id}", response_model=GameStateResponse)
def get_game(game_id: UUID) -> GameStateResponse:
    session = _game_sessions.get(game_id)
    if not session:
        raise HTTPException(status_code=404, detail="game not found")
    return _game_state_response(session)


@app.post("/api/v1/games/{game_id}/ron", response_model=GameRoundResponse)
async def record_ron(game_id: UUID, req: RonRequest) -> dict:
    session = _game_sessions.get(game_id)
    if not session:
        raise HTTPException(status_code=404, detail="game not found")
    try:
        record = apply_ron(
            session, req.winner_seat, req.loser_seat,
            req.han, req.fu, req.yakuman_multiplier, req.riichi_seats,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    result = {
        "game_id": session.game_id,
        "round_result": _round_result_response(session, record),
        "game_state": _game_state_response(session),
    }
    await room_manager.broadcast_game_update(session.room_code, "ron", {
        "game_state": _game_state_response(session).model_dump(mode="json"),
        "round_result": _round_result_response(session, record).model_dump(mode="json"),
    })
    return result


@app.post("/api/v1/games/{game_id}/multi-ron", response_model=GameRoundResponse)
async def record_multi_ron(game_id: UUID, req: MultiRonRequest) -> dict:
    session = _game_sessions.get(game_id)
    if not session:
        raise HTTPException(status_code=404, detail="game not found")
    try:
        winners_dicts = [
            {"seat": w.seat, "han": w.han, "fu": w.fu, "yakuman_multiplier": w.yakuman_multiplier}
            for w in req.winners
        ]
        record = apply_multi_ron(session, req.loser_seat, winners_dicts, req.riichi_seats)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    result = {
        "game_id": session.game_id,
        "round_result": _round_result_response(session, record),
        "game_state": _game_state_response(session),
    }
    await room_manager.broadcast_game_update(session.room_code, "ron", {
        "game_state": _game_state_response(session).model_dump(mode="json"),
        "round_result": _round_result_response(session, record).model_dump(mode="json"),
    })
    return result


@app.post("/api/v1/games/{game_id}/tsumo", response_model=GameRoundResponse)
async def record_tsumo(game_id: UUID, req: TsumoRequest) -> dict:
    session = _game_sessions.get(game_id)
    if not session:
        raise HTTPException(status_code=404, detail="game not found")
    try:
        record = apply_tsumo(
            session, req.winner_seat,
            req.han, req.fu, req.yakuman_multiplier, req.riichi_seats,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    result = {
        "game_id": session.game_id,
        "round_result": _round_result_response(session, record),
        "game_state": _game_state_response(session),
    }
    await room_manager.broadcast_game_update(session.room_code, "tsumo", {
        "game_state": _game_state_response(session).model_dump(mode="json"),
        "round_result": _round_result_response(session, record).model_dump(mode="json"),
    })
    return result


@app.post("/api/v1/games/{game_id}/draw", response_model=GameRoundResponse)
async def record_draw(game_id: UUID, req: DrawRequest) -> dict:
    session = _game_sessions.get(game_id)
    if not session:
        raise HTTPException(status_code=404, detail="game not found")
    try:
        record = apply_draw(session, req.tenpai_seats, req.riichi_seats)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    result = {
        "game_id": session.game_id,
        "round_result": _round_result_response(session, record),
        "game_state": _game_state_response(session),
    }
    await room_manager.broadcast_game_update(session.room_code, "draw", {
        "game_state": _game_state_response(session).model_dump(mode="json"),
        "round_result": _round_result_response(session, record).model_dump(mode="json"),
    })
    return result


@app.get("/api/v1/games/{game_id}/history")
def get_game_history(game_id: UUID) -> dict:
    session = _game_sessions.get(game_id)
    if not session:
        raise HTTPException(status_code=404, detail="game not found")
    rounds = []
    for record in session.rounds:
        rounds.append({
            "round_number": record.round_number,
            "round_wind": record.round_wind,
            "dealer_seat": record.dealer_seat,
            "honba": record.honba,
            "result_type": record.result_type,
            "winner_seat": record.winner_seat,
            "loser_seat": record.loser_seat,
            "point_changes": {str(k): v for k, v in record.point_changes.items()},
            "riichi_seats": record.riichi_seats,
        })
    return {
        "game_id": str(session.game_id),
        "rounds": rounds,
        "game_state": _game_state_response(session).model_dump(mode="json"),
    }


@app.post("/api/v1/games/{game_id}/undo")
async def undo_round(game_id: UUID) -> dict:
    session = _game_sessions.get(game_id)
    if not session:
        raise HTTPException(status_code=404, detail="game not found")
    removed = undo_last(session)
    if removed is None:
        raise HTTPException(status_code=422, detail="nothing to undo")
    state = _game_state_response(session)
    await room_manager.broadcast_game_update(session.room_code, "undo", {
        "game_state": state.model_dump(mode="json"),
    })
    return {
        "status": "ok",
        "undone_round": removed.round_number,
        "game_state": state.model_dump(mode="json"),
    }


@app.post("/api/v1/games/{game_id}/seats/{seat}/claim")
async def claim_seat(game_id: UUID, seat: int, req: ClaimSeatRequest) -> dict:
    session = _game_sessions.get(game_id)
    if not session:
        raise HTTPException(status_code=404, detail="game not found")
    if seat < 0 or seat > 3:
        raise HTTPException(status_code=422, detail="seat must be 0-3")
    session.players[seat].name = req.name
    state = _game_state_response(session)
    await room_manager.broadcast_game_update(session.room_code, "seat_claimed", {
        "seat": seat,
        "name": req.name,
        "game_state": state.model_dump(mode="json"),
    })
    return {"status": "ok", "game_state": state.model_dump(mode="json")}


@app.post("/api/v1/games/{game_id}/seats/swap")
async def swap_seats(game_id: UUID, req: SwapSeatsRequest) -> dict:
    session = _game_sessions.get(game_id)
    if not session:
        raise HTTPException(status_code=404, detail="game not found")
    if req.seat_a == req.seat_b:
        raise HTTPException(status_code=422, detail="seats must be different")
    a, b = session.players[req.seat_a], session.players[req.seat_b]
    a.name, b.name = b.name, a.name
    a.points, b.points = b.points, a.points
    state = _game_state_response(session)
    await room_manager.broadcast_game_update(session.room_code, "seats_swapped", {
        "seat_a": req.seat_a,
        "seat_b": req.seat_b,
        "game_state": state.model_dump(mode="json"),
    })
    return {"status": "ok", "game_state": state.model_dump(mode="json")}


@app.get("/api/v1/games/{game_id}/qr")
def game_qr(game_id: UUID, request: Request) -> Response:
    session = _game_sessions.get(game_id)
    if not session:
        raise HTTPException(status_code=404, detail="game not found")
    import qrcode
    import qrcode.constants
    base_url = str(request.base_url).rstrip("/")
    join_url = f"{base_url}/game?room={session.room_code}"
    qr = qrcode.QRCode(version=1, error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=8, border=2)
    qr.add_data(join_url)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    buf = BytesIO()
    img.save(buf, format="PNG")
    return Response(content=buf.getvalue(), media_type="image/png")


@app.delete("/api/v1/games/{game_id}")
def delete_game(game_id: UUID) -> dict:
    session = _game_sessions.pop(game_id, None)
    if not session:
        raise HTTPException(status_code=404, detail="game not found")
    _room_code_to_game.pop(session.room_code, None)
    room_manager.remove_room(session.room_code)
    return {"status": "deleted", "game_id": str(game_id)}


@app.get("/api/v1/rooms/{room_code}")
def get_room(room_code: str) -> dict:
    game_id = _room_code_to_game.get(room_code.upper())
    if not game_id:
        raise HTTPException(status_code=404, detail="room not found")
    session = _game_sessions.get(game_id)
    if not session:
        raise HTTPException(status_code=404, detail="game not found")
    return {
        "room_code": room_code.upper(),
        "game_id": str(session.game_id),
        "game_state": _game_state_response(session).model_dump(mode="json"),
        "connected_players": room_manager.get_connected_players(room_code.upper()),
    }


@app.websocket("/ws/rooms/{room_code}")
async def room_websocket(websocket: WebSocket, room_code: str, player_name: str = ""):
    code = room_code.upper()
    if not await room_manager.connect(code, websocket, player_name):
        await websocket.close(code=4004, reason="room not found")
        return
    try:
        while True:
            data = await websocket.receive_text()
            # Client can send ping/pong or action requests
            msg = json.loads(data)
            if msg.get("type") == "ping":
                await websocket.send_text(json.dumps({"type": "pong"}))
            elif msg.get("type") in ("riichi_toggle", "tenpai_toggle"):
                await room_manager.broadcast_game_update(code, msg["type"], {
                    "seat": msg.get("seat"),
                    "active": msg.get("active"),
                })
            elif msg.get("type") == "request_sync":
                game_id = room_manager.get_game_id(code)
                if game_id and game_id in _game_sessions:
                    session = _game_sessions[game_id]
                    state = _game_state_response(session)
                    await room_manager.broadcast_game_update(code, "sync", {
                        "game_state": state.model_dump(mode="json"),
                    })
    except WebSocketDisconnect:
        room_manager.disconnect(code, websocket)
        await room_manager.broadcast_game_update(code, "player_left", {
            "player_name": player_name,
            "connected_count": len(room_manager.get_connected_players(code)),
        })


@app.get("/game")
def game_ui() -> FileResponse:
    return FileResponse(STATIC_DIR / "game.html")


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
