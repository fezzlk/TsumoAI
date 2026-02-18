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
