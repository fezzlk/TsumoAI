# Mahjong Hand Score PoC

FastAPI + OpenAI (`gpt-4o-mini`) で、手牌画像から候補抽出し、和了点を返すPoCです。

## Quickstart

```bash
cp .env.example .env
./scripts/download_tiles.sh
docker compose up --build
```

開発時ホットリロード:

- `docker-compose.yml` は `uvicorn --reload` + `./app` のボリュームマウント設定済みです。
- `app/` 配下のコード変更は、保存後にコンテナ内で自動反映されます（通常はリビルド不要）。
- `requirements.txt` 変更時だけは再ビルドが必要です。

API docs:

- `http://localhost:8000/docs`
- `http://localhost:8000/` は案内レスポンスを返します
- `http://localhost:8000/score-ui` は点数算出UIです

Health check:

```bash
curl http://localhost:8000/health
```

## Deploy (Google Cloud Run)

この構成は Cloud Run 向けに対応済みです（`Dockerfile` が `PORT` 環境変数で起動）。

### 1. 前提

- `gcloud` CLI インストール済み
- GCP プロジェクト作成済み
- 課金有効化済み
- `GCS_BUCKET_NAME`（フィードバック保存先）作成済み

### 2. 初回ログイン

```bash
gcloud auth login
gcloud auth application-default login
```

### 3. OpenAI APIキーを Secret Manager に登録（任意）

未登録でもデプロイ可能ですが、`/recognize` はダミー応答になります。

```bash
export PROJECT_ID="<your-gcp-project-id>"
export OPENAI_API_KEY="<your-openai-api-key>"

printf '%s' "${OPENAI_API_KEY}" | gcloud secrets create openai-api-key \
  --project "${PROJECT_ID}" \
  --replication-policy="automatic" \
  --data-file=-
```

すでに secret がある場合は新バージョン追加:

```bash
printf '%s' "${OPENAI_API_KEY}" | gcloud secrets versions add openai-api-key \
  --project "${PROJECT_ID}" \
  --data-file=-
```

### 4. デプロイ実行

```bash
export PROJECT_ID="<your-gcp-project-id>"
export REGION="asia-northeast1"
export SERVICE_NAME="tsumoai-api"
export GCS_BUCKET_NAME="<your-feedback-bucket>"
export OPENAI_MODEL="gpt-4o-mini"

./scripts/deploy_cloud_run.sh
```

スクリプトが実行する内容:

- 必要 API の有効化
- Cloud Run 実行用サービスアカウント作成
- GCS 書き込み権限付与（`roles/storage.objectCreator`）
- `openai-api-key` secret が存在する場合のみ `OPENAI_API_KEY` を注入
- `gcloud run deploy --source .` によるビルドとデプロイ

### 5. 動作確認

```bash
SERVICE_URL="$(gcloud run services describe "${SERVICE_NAME}" --region "${REGION}" --format='value(status.url)')"
curl "${SERVICE_URL}/health"
```

`{"status":"ok"}` が返ればデプロイ成功です。

## Endpoints

- `POST /api/v1/recognize`
  - `multipart/form-data`
  - fields: `image` (file), `game_id` (optional)
- `POST /api/v1/score`
  - `application/json`
- `POST /api/v1/recognize-and-score`
  - `multipart/form-data`
  - fields: `image` (file), `context_json`, `rules_json`
- `GET /api/v1/results/{id}`
- `POST /api/v1/score/feedback`
  - `application/json`
  - score-ui の誤り指摘フォームから送信される訂正内容を GCS に保存

## Notes

- `OPENAI_API_KEY` 未設定時は、`/recognize` はフォールバックのダミー結果を返します。
- 保存はメモリ実装（TTL 24時間）。再起動で消えます。
- スコア計算はPoC簡易版です（現在は補完情報フラグ中心）。フル役判定は次フェーズで実装します。
- モジュール責務は分離済みです。
  - `app/hand_extraction.py`: 画像を読み取り、牌姿候補を抽出
  - `app/hand_scoring.py`: 牌姿（和了形）と補完情報から点数算出
- 牌画像は `scripts/download_tiles.sh` でネット上（Wikimedia Commons）から取得し、`app/static/tiles` に保存します。
- 点数訂正フィードバックは GCS に保存されます。
  - `.env` に `GCS_BUCKET_NAME` を設定してください
  - 必要なら `GCS_FEEDBACK_PREFIX` で保存先プレフィックスを変更できます

## Feedback Flow

1. `http://localhost:8000/score-ui` で点数算出する
2. 結果が誤っている場合、同ページの「誤り指摘（GCS保存）」フォームに訂正値を入力する
3. 送信すると、元の入力・元の算出結果・訂正内容が GCS に JSON で保存される
4. 保存データを参照して計算ロジックを修正する

## Tests

```bash
pytest -q
```

- `tests/test_hand_scoring.py`: 点数算出モジュール単体テスト
- `tests/test_api_score.py`: `/score-ui` と `/api/v1/score` のAPIテスト
