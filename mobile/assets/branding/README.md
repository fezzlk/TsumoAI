# ツモロウ

TsumoAIの麻雀アシスタント。採用した画像は、角帽・丸メガネ・縦長の目・
額の黄色い3本線を持つ、麻雀牌と一体のフクロウです。

- `tsumorou_source.png`: 2026-10-05に採用した元画像（変更せず保持）。
- `tsumorou.png`: アプリ内で使う256pxの透過画像。
- 起動アイコン: iOS / Android / Web / macOS / Windowsの各リソースへ生成。

`mobile/`で以下を実行すると、既存の`image`依存を使って再生成できます。

```sh
dart run tool/generate_brand_assets.dart
```

起動アイコンの背景はアプリの淡い緑 `#E8F2ED`。iOSは透過なしで出力し、
Android adaptive iconとWeb maskable iconは帽子が切れない安全領域に配置します。
元画像を変更するときは、`tsumorou_source.png`を置換して再生成してください。
