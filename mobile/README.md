# TsumoAI — Flutter / Web

iOS・Androidと共通の画面で、写真から牌の認識・修正、点数計算、待ち・打牌・鳴き分析、対局管理を利用できます。
Web版は写真選択・端末の撮影画面から画像を読み込みます。カメラ映像の常時取得は行いません。

## 開発

リポジトリ直下で、既存の `.env` を準備してから:

```sh
docker compose up --build
```

Web: `http://localhost:8088`、API: `http://localhost:8000/docs`。
初回はFlutterイメージと依存ライブラリの取得、Webのコンパイルに時間がかかります。
`mobile/lib/` の変更は自動ホットリロード、`app/` の変更はuvicornのreloadで反映します。
`mobile/web/` のJavaScriptやmanifestの変更時はブラウザも再読み込みしてください。

ホストのFlutter 3.41.4 / Node.js 20以上を使う場合、APIを別途起動したうえで:

```sh
cd mobile
WEB_API_URL=http://127.0.0.1:8000 node tool/web_runtime/dev.mjs
```

同一オリジンの `/api/` をバックエンドに中継するため、開発用にCORSを全許可する必要はありません。

## Webビルド

```sh
cd mobile
npm ci --prefix tool/web_runtime
flutter pub get
flutter build web --release --pwa-strategy=none
```

成果物は `mobile/build/web/`。`npm ci` が固定バージョンの認識ランタイムを
`web/vendor/` に展開し、Flutterがビルドに同梱します。vendorとnode_modulesは生成物です。
サブパス配信には `--base-href=/app/` のように指定できます。

APIを起動したまま `node tool/web_runtime/preview.mjs` でリリース版を
`http://localhost:8089` から確認できます（開発用、ホットリロードなし）。

配信時はHTTPSを使い、同じオリジンの `/api/` を既存FastAPIへ中継してください。
別オリジンのAPIを使う場合は `--dart-define=API_BASE_URL=https://...` とバックエンドの
`CORS_ORIGINS` を明示的に設定します。HTML・JS・manifestには更新時に再検証される
Cache-Controlを設定し、`.wasm` は `application/wasm` で配信します。
本番の `Dockerfile` はFlutter 3.41.4と固定したnpm依存からWeb版をビルドし、
既存FastAPIと同じCloud Runサービスの `/app/` から配信します。
公開URLは `https://tsumoai.fezzlk.com/app/`。既存のトップページからも開けます。
静的ファイルはgzip圧縮と再検証に対応し、APIや管理画面のURLは維持します。
デプロイは `main` を対象とする既存の `tsumoai-deploy` トリガーだけを使います
（project: `tsumoai`、region: `asia-northeast1`）。サービス・トリガーの追加は不要です。

## ホーム画面への追加

- iPhone: Safariの共有メニュー → ホーム画面に追加 → Webアプリとして開く。
- Android: Chromeのメニュー → ホーム画面に追加／アプリをインストール。

ホーム画面アイコンと独立ウィンドウに対応します。完全オフライン対応ではありません。
点数計算・分析・AI相談・アカウント同期には通信が必要です。
Googleログインには配信ドメインを既存Firebaseプロジェクトの承認済みドメインに登録する必要があります。
設定には既存Webページと同じ公開Firebaseアプリ登録を利用します。

## 認識・保存

- Webは同梱TFLiteモデルをWeb Worker + WebAssemblyで実行します。画像認識のための外部API通信・料金は発生しません。
- 前処理と候補順位付けはネイティブ版と共通です。認識精度が向上したという変更ではありません。
- モデルが読み込めない場合はエラーを表示します。有料APIへの自動フォールバックはありません。
- 初回はモデルとWASMのダウンロードが必要です。Web版モデルはWebのリリースと一緒に更新します。
- 写真全体を保持し、EXIFの向きを補正して最大2048pxに縮小します。JPEG/PNGを推奨し、非対応形式はエラーを表示します。
- 履歴・設定・質問テンプレートはブラウザのlocalStorageに保存し、既存のログイン後同期を利用します。
  サイトデータの削除でローカル保存分が消えます。ネイティブ版の端末ファイルは直接引き継ぎません。
- AI相談など、既存のサーバー機能の通信と料金体系は従来どおりです。

## 検証

```sh
cd mobile
flutter analyze
flutter test
flutter test --platform chrome test/web_storage_test.dart
npm ci --prefix tool/web_runtime
npm test --prefix tool/web_runtime
# Safari系エンジン（実機iPhoneの代わりではありません）
npx --prefix tool/web_runtime playwright install webkit
BROWSER=webkit npm test --prefix tool/web_runtime
```

認識ランタイムのテストは、バージョン付きの `test/fixtures/web_recognition_eval_v1.json` にある
ネイティブTFLiteの基準出力と比較し、モデル不在・破棄後のエラーも検証します。
モデル更新時の基準再生成は `tool/web_runtime/reference.py` で行います。
