from __future__ import annotations

import json
import time
from collections import defaultdict, deque
from io import BytesIO
from pathlib import Path
from uuid import UUID

from fastapi import Depends, FastAPI, File, Form, HTTPException, Query, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from PIL import Image

from app.config import resolve_gcp_project, settings
from app.auth import get_current_user, require_admin
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
    MyDataDeletionResponse,
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
    allow_origins=[origin.strip() for origin in settings.cors_origins.split(",") if origin.strip()],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
repo = InMemoryRepository(ttl_hours=settings.image_ttl_hours)
recognition_jobs = RecognitionJobManager(repo=repo, model_name=settings.openai_model)
STATIC_DIR = Path(__file__).resolve().parent / "static"
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
gcs_feedback_store = GCSFeedbackStore()
gcs_dataset_store = GCSFeedbackStore(prefix=settings.gcs_dataset_prefix)
accuracy_store = GCSFeedbackStore(prefix=settings.gcs_accuracy_prefix)
recognition_feedback_store = RecognitionFeedbackStore()

from app.training_data_store import TrainingDataStore
training_data_store = TrainingDataStore()
_recognition_rate_windows: dict[str, deque[float]] = defaultdict(deque)


@app.middleware("http")
async def limit_anonymous_recognition(request: Request, call_next):
    if request.method == "POST" and request.url.path in {
        "/api/v1/recognize",
        "/api/v1/recognize-only",
        "/api/v1/recognize-only/jobs",
        "/api/v1/recognize-and-score",
    }:
        key = request.client.host if request.client else "unknown"
        now = time.monotonic()
        window = _recognition_rate_windows[key]
        while window and now - window[0] >= 60:
            window.popleft()
        if len(window) >= settings.anonymous_recognition_requests_per_minute:
            return JSONResponse(status_code=429, content={"detail": "recognition rate limit exceeded"})
        window.append(now)
    return await call_next(request)


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
  <a class="card" href="/terms"><div class="icon">📜</div><div class="card-body"><div class="name">利用規約</div><div class="desc">サービスの利用条件</div></div></a>
  <a class="card" href="/privacy"><div class="icon">🔒</div><div class="card-body"><div class="name">プライバシーポリシー</div><div class="desc">データの取り扱い</div></div></a>
</div>
</body></html>""")


_LEGAL_STYLE = """
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,sans-serif;background:#1a1a2e;color:#e0e0e0;
  display:flex;justify-content:center;min-height:100vh;padding:40px 16px}
main{max-width:680px;width:100%;line-height:1.7}
h1{font-size:24px;margin-bottom:4px;color:#fff}
.updated{color:#888;font-size:13px;margin-bottom:24px}
h2{font-size:17px;color:#4ecca3;margin-top:24px;margin-bottom:8px}
p,li{font-size:14px;color:#e0e0e0}
ul{padding-left:20px;margin:4px 0}
a{color:#4ecca3}
code{background:#16213e;padding:1px 5px;border-radius:4px;font-size:12px}
"""


def _contact_html() -> str:
    if settings.contact_form_url:
        return f'<a href="{settings.contact_form_url}">こちらのフォーム</a>'
    return "本サービスのお問い合わせ窓口"


@app.get("/terms")
def terms() -> HTMLResponse:
    provider = settings.service_provider_name
    contact = _contact_html()
    return HTMLResponse(f"""<!DOCTYPE html>
<html lang="ja"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>利用規約 - TsumoAI</title><style>{_LEGAL_STYLE}</style></head><body><main>
<h1>利用規約</h1>
<p class="updated">最終更新日: 2026-08-26</p>

<h2>1. サービス概要</h2>
<p>TsumoAI（以下「本サービス」）は、{provider}（以下「運営者」）が提供する、麻雀の手牌画像をAIで認識し、点数計算を行うツールです。</p>

<h2>2. 利用条件</h2>
<p>本サービスは現時点で無料で提供しています。牌画像の認識・点数計算は未ログインでも利用できますが、
認識結果へのフィードバック投稿・学習データ提供には認証（Firebaseログイン）が必要です。
料金体系を変更する場合は、本規約の改定として事前に告知します。</p>

<h2>3. 認識結果に関する免責事項</h2>
<p>牌の認識・点数計算はAI（機械学習モデル・外部の画像認識API）により行われており、
撮影条件や牌の状態によっては誤認識・誤判定が発生することがあります。本サービスは認識結果・点数計算結果の
正確性を保証しません。実際の対局における点数の確定や精算は、必ずご自身で最終確認のうえ行ってください。
運営者は、認識結果の誤りに起因して生じた損害（対局結果・精算に関する紛争等を含む）について、
故意または重過失による場合を除き責任を負いません。</p>

<h2>4. 禁止事項</h2>
<ul>
<li>法令または公序良俗に違反する内容の画像を送信する行為</li>
<li>他者の権利（著作権・肖像権等）を侵害する画像を送信する行為</li>
<li>本サービスに過度な負荷をかける行為、不正アクセスや脆弱性を悪用する行為</li>
</ul>

<h2>5. 規約の変更・サービスの終了</h2>
<p>運営者は、本サービスの内容を予告なく変更・終了することがあります。本規約は必要に応じて改定し、本ページで告知します。</p>

<h2>6. 準拠法</h2>
<p>本規約は日本法に準拠します。</p>

<h2>7. お問い合わせ</h2>
<p>本サービスに関するお問い合わせは、{contact}からご連絡ください。</p>
</main></body></html>""")


@app.get("/privacy")
def privacy() -> HTMLResponse:
    provider = settings.service_provider_name
    contact = _contact_html()
    ttl = settings.image_ttl_hours
    return HTMLResponse(f"""<!DOCTYPE html>
<html lang="ja"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>プライバシーポリシー - TsumoAI</title><style>{_LEGAL_STYLE}</style></head><body><main>
<h1>プライバシーポリシー</h1>
<p class="updated">最終更新日: 2026-08-26</p>

<h2>1. 収集する情報と保存方針</h2>
<p>{provider}（以下「運営者」）は、TsumoAI（以下「本サービス」）の提供にあたり、利用方法に応じて次のように情報を取り扱います。</p>
<ul>
<li><b>未ログインでの牌認識・点数計算</b>: 送信された手牌画像・対局データはサーバーのメモリ上に一時保存され、
送信から{ttl}時間後に自動的に削除されます。永続的なストレージには保存されません。</li>
<li><b>ログインしての投稿（認識結果へのフィードバック・学習データの提供）</b>: Firebase認証のユーザーIDと、
投稿された画像・修正内容・コメントをGoogle Cloud Storageに保存し、認識モデルの改善に利用します。
この情報は「5. 削除」の方法でご自身が削除するまで保持されます。</li>
</ul>

<h2>2. 利用目的</h2>
<p>収集した情報は、本サービスの牌認識・点数計算機能の提供、および認識モデルの精度改善のためにのみ利用します。</p>

<h2>3. 第三者提供</h2>
<p>本サービスは牌認識のために外部のAI画像認識API（OpenAI Vision）を、認証にFirebase Authenticationを、
保存先としてGoogle Cloud Storageを利用しています。これらの外部サービスへの情報提供は本サービスの提供に
必要な範囲に限られ、法令に基づく場合を除き、それ以外の第三者への提供は行いません。</p>

<h2>4. 保存期間</h2>
<p>未ログイン利用時のデータは{ttl}時間で自動削除されます。ログインして投稿したデータは、
ユーザーが削除しない限り、本サービスの提供に必要な期間保存します。</p>

<h2>5. 削除</h2>
<p>ログインして投稿したフィードバック・学習データ・データセットは、認証済みで
<code>DELETE /api/v1/me/data</code> を呼び出すことでご自身のデータをすべて削除できます（取り消しはできません）。
API呼び出しが難しい場合は、下記のお問い合わせ窓口からご依頼いただければ運営者が代行して削除します。</p>

<h2>6. 収益化について</h2>
<p>本サービスは現在無料で提供しています。将来的に収益化を検討する場合も、本ページで告知します。</p>

<h2>7. 変更</h2>
<p>本ポリシーは必要に応じて改定し、本ページで告知します。</p>

<h2>8. お問い合わせ</h2>
<p>本サービスの情報の取り扱いに関するお問い合わせは、{contact}からご連絡ください。</p>
</main></body></html>""")


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


async def _read_limited_image(upload: UploadFile) -> bytes:
    image_bytes = await upload.read(settings.max_image_bytes + 1)
    if not image_bytes:
        raise HTTPException(status_code=400, detail="image is required")
    if len(image_bytes) > settings.max_image_bytes:
        raise HTTPException(status_code=413, detail="image is too large")
    return image_bytes


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
    image_bytes = await _read_limited_image(image)

    width, height, recognition_image_bytes = _to_recognition_image_bytes(image, image_bytes)
    payload = extract_hand_from_image(recognition_image_bytes)
    return _build_recognize_response(width=width, height=height, game_id=game_id, payload=payload)


@app.post("/api/v1/recognize-only", response_model=RecognizeResponse)
async def recognize_only(image: UploadFile = File(...), game_id: str | None = Form(None)) -> RecognizeResponse:
    """Dedicated image-recognition endpoint."""
    return await recognize(image=image, game_id=game_id)


@app.post("/api/v1/recognize-only/jobs", response_model=RecognizeJobCreateResponse)
async def create_recognize_job(image: UploadFile = File(...), game_id: str | None = Form(None)) -> RecognizeJobCreateResponse:
    image_bytes = await _read_limited_image(image)
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
def score_feedback(req: ScoreFeedbackRequest, _user: dict = Depends(get_current_user)) -> ScoreFeedbackResponse:
    payload = req.model_dump(mode="json")
    payload["comment"] = req.comment.strip()
    payload["uid"] = _user.get("uid")
    try:
        storage_info = gcs_feedback_store.save(payload)
    except ValueError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:  # pragma: no cover
        raise HTTPException(status_code=500, detail=f"Failed to save feedback to GCS: {exc}") from exc
    return ScoreFeedbackResponse(status="ok", storage=storage_info)


@app.post("/api/v1/recognition/feedback", response_model=RecognitionFeedbackResponse)
def recognition_feedback(req: RecognitionFeedbackRequest, _user: dict = Depends(get_current_user)) -> RecognitionFeedbackResponse:
    if len(req.corrected_tiles) != 14:
        raise HTTPException(status_code=422, detail="corrected_tiles must contain exactly 14 tiles")
    for tile in req.corrected_tiles:
        validate_tile(tile)

    payload = req.model_dump(mode="json")
    payload["comment"] = req.comment.strip()
    payload["uid"] = _user.get("uid")
    storage_info = recognition_feedback_store.save(payload)
    return RecognitionFeedbackResponse(status="ok", storage=storage_info)


@app.post("/api/v1/dataset/upload", response_model=DatasetUploadResponse)
def upload_dataset(req: DatasetUploadRequest, _user: dict = Depends(get_current_user)) -> DatasetUploadResponse:
    if not req.entries:
        raise HTTPException(status_code=422, detail="entries must not be empty")
    try:
        payload = {"entries": req.entries, "uid": _user.get("uid")}
        if req.contributor:
            payload["contributor"] = req.contributor
        storage_info = gcs_dataset_store.save(payload, contributor=req.contributor)
    except ValueError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:  # pragma: no cover
        raise HTTPException(status_code=500, detail=f"Failed to upload dataset to GCS: {exc}") from exc
    return DatasetUploadResponse(status="ok", count=len(req.entries), storage=storage_info)


@app.get("/api/v1/dataset/list")
def list_datasets(_admin: dict = Depends(require_admin)) -> dict:
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
def download_dataset(name: str = Query(...), _admin: dict = Depends(require_admin)) -> JSONResponse:
    bucket_name = gcs_dataset_store.bucket_name
    if not bucket_name:
        raise HTTPException(status_code=503, detail="GCS bucket is not configured")
    client = gcs_dataset_store._get_client()
    bucket = client.bucket(bucket_name)
    allowed_prefix = gcs_dataset_store.prefix.rstrip("/") + "/"
    if not name.startswith(allowed_prefix) or not name.endswith(".json") or ".." in name:
        raise HTTPException(status_code=400, detail="invalid dataset object name")
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
    _user: dict = Depends(get_current_user),
) -> TrainingDataUploadResponse:
    validate_tile(tile_code)
    image_bytes = await _read_limited_image(image)
    try:
        result = training_data_store.upload(image_bytes, tile_code, source, uid=_user.get("uid"))
    except ValueError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return TrainingDataUploadResponse(status="ok", **result)


@app.get("/api/v1/training-data/list")
def list_training_data(
    tile_code: str | None = Query(None),
    source: str | None = Query(None),
    limit: int = Query(500),
    refresh: bool = Query(False),
    _admin: dict = Depends(require_admin),
) -> dict:
    try:
        if refresh:
            training_data_store.invalidate_cache()
        entries = training_data_store.list_entries(tile_code=tile_code, source=source, limit=limit)
        stats = training_data_store.get_stats()
        timeline = training_data_store.get_daily_timeline()
    except ValueError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return {"entries": entries, "stats": stats, "timeline": timeline}


@app.get("/api/v1/training-data/image/{entry_id}")
def get_training_image(entry_id: str, _admin: dict = Depends(require_admin)) -> Response:
    try:
        data = training_data_store.get_image(entry_id)
    except ValueError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    if data is None:
        raise HTTPException(status_code=404, detail="image not found")
    return Response(content=data, media_type="image/jpeg")


@app.delete("/api/v1/training-data/{entry_id}")
def delete_training_data(entry_id: str, _admin: dict = Depends(require_admin)) -> dict:
    try:
        deleted = training_data_store.delete_entry(entry_id)
    except ValueError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    if not deleted:
        raise HTTPException(status_code=404, detail="entry not found")
    return {"status": "deleted", "id": entry_id}


@app.patch("/api/v1/training-data/{entry_id}")
def update_training_data_label(
    entry_id: str,
    tile_code: str = Query(...),
    _admin: dict = Depends(require_admin),
) -> dict:
    validate_tile(tile_code)
    try:
        updated = training_data_store.update_tile_code(entry_id, tile_code)
    except ValueError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    if not updated:
        raise HTTPException(status_code=404, detail="entry not found")
    return {"status": "updated", "id": entry_id, "tile_code": tile_code}


@app.get("/training-data")
def training_data_viewer() -> FileResponse:
    return FileResponse(STATIC_DIR / "training_data.html")


# --- Privacy: self-service deletion of contributed data ---
# Anonymous recognize/score calls are never persisted beyond the in-memory
# repository's TTL (settings.image_ttl_hours), so there is nothing to delete
# for them. This endpoint only covers data a signed-in user opted to
# contribute (feedback, dataset uploads, training-data images).


@app.delete("/api/v1/me/data", response_model=MyDataDeletionResponse)
def delete_my_data(_user: dict = Depends(get_current_user)) -> MyDataDeletionResponse:
    uid = _user.get("uid")
    if not uid:
        raise HTTPException(status_code=400, detail="token has no uid")
    return MyDataDeletionResponse(
        status="ok",
        deleted_training_data=training_data_store.delete_by_uid(uid),
        deleted_score_feedback=gcs_feedback_store.delete_by_uid(uid),
        deleted_recognition_feedback=recognition_feedback_store.delete_by_uid(uid),
        deleted_dataset_uploads=gcs_dataset_store.delete_by_uid(uid),
    )


@app.get("/api/v1/metrics/accuracy-history")
def get_accuracy_history(_admin: dict = Depends(require_admin)) -> dict:
    bucket_name = accuracy_store.bucket_name
    prefix = accuracy_store.prefix
    if not bucket_name:
        raise HTTPException(status_code=503, detail="GCS bucket is not configured")
    client = accuracy_store._get_client()
    bucket = client.bucket(bucket_name)
    blobs = bucket.list_blobs(prefix=prefix + "/")
    history = []
    for blob in blobs:
        if not blob.name.endswith(".json"):
            continue
        try:
            data = json.loads(blob.download_as_text())
        except Exception:
            continue
        payload = data.get("payload", {})
        history.append({
            "evaluated_at": payload.get("evaluated_at", data.get("saved_at")),
            "tile_accuracy": payload.get("tile_accuracy"),
            "exact_match_rate": payload.get("exact_match_rate"),
            "n": payload.get("n"),
        })
    history.sort(key=lambda h: h["evaluated_at"] or "")
    return {"history": history}




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
def trigger_retrain(_admin: dict = Depends(require_admin)) -> dict:
    """Trigger model retraining via Cloud Build."""
    project_id = resolve_gcp_project()
    if not project_id:
        raise HTTPException(status_code=503, detail="GCP project not configured")
    if not settings.gcs_bucket_name:
        raise HTTPException(status_code=503, detail="GCS not configured")
    try:
        from google.cloud.devtools import cloudbuild_v1
        client = cloudbuild_v1.CloudBuildClient()
        location = "asia-northeast1"
        parent = f"projects/{project_id}/locations/{location}"
        repository = (
            f"{parent}/connections/tsumoai-github/repositories/tsumoai-repo"
        )

        active_statuses = {
            cloudbuild_v1.Build.Status.QUEUED,
            cloudbuild_v1.Build.Status.WORKING,
        }
        for existing in client.list_builds(
            request={"project_id": project_id, "parent": parent, "page_size": 50}
        ):
            if "tsumoai-model-training" in existing.tags and existing.status in active_statuses:
                raise HTTPException(
                    status_code=409,
                    detail=f"model retraining is already active: {existing.id}",
                )

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
                connected_repository={
                    "repository": repository,
                    "revision": "refs/heads/main",
                }
            ),
            options=cloudbuild_v1.BuildOptions(
                logging=cloudbuild_v1.BuildOptions.LoggingMode.CLOUD_LOGGING_ONLY,
            ),
            timeout={"seconds": 3600},
            tags=["tsumoai-model-training"],
        )

        operation = client.create_build(
            request={"project_id": project_id, "parent": parent, "build": build}
        )
        build_id = operation.metadata.build.id
        return {
            "status": "started",
            "build_id": build_id,
            "message": "モデル再学習を開始しました（完了まで30〜60分）",
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Cloud Build起動エラー: {e}")


@app.post("/api/v1/model/candidates/{version}/approve")
def approve_model_candidate(version: str, _admin: dict = Depends(require_admin)) -> dict:
    if not version.isdigit() or len(version) != 14:
        raise HTTPException(status_code=400, detail="invalid model version")
    if not settings.gcs_bucket_name:
        raise HTTPException(status_code=503, detail="GCS not configured")
    try:
        from google.cloud import storage
        client = storage.Client(project=settings.gcp_project)
        bucket = client.bucket(settings.gcs_bucket_name)
        candidate = bucket.blob(f"models/candidates/{version}.json")
        if not candidate.exists():
            raise HTTPException(status_code=404, detail="model candidate not found")
        meta = json.loads(candidate.download_as_text())
        bucket.blob("models/latest.json").upload_from_string(
            json.dumps({**meta, "approved_by": _admin.get("uid")}),
            content_type="application/json",
        )
        return {"status": "approved", **meta}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


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
