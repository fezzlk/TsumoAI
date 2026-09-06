# AI quality gates

TsumoAI は次のバージョン付き評価セットを品質の正本として使う。

- `data/recognition_eval_set.jsonl`: 牌認識
- `data/interpretation_eval_set.jsonl`: 鳴き・あがり牌の解釈
- `data/domain_analysis_eval_set.jsonl`: テンパイ・待ち・打牌分析

## リリース前の確認

1. pytest -q を実行する。
2. ラベル済み評価セットで tile精度と完全一致率を計測し、前回基準を下回らないことを確認する。
3. 誤認識は recognition_feedback.jsonl と混同行列で分類する。
4. RECOGNIZE_ENSEMBLE_PASSES の変更時は、精度だけでなく呼び出し回数・レイテンシ・API費用を記録する。
5. 画像とフィードバックに含まれる個人情報を評価セットへ混入させない。
6. `python scripts/evaluate_interpretation_set.py` を実行し、全ケース成功かつ
   `false_auto_confirm` が0であることを確認する。
7. `python scripts/evaluate_domain_analysis_set.py` を実行し、全ケース成功を確認する。
8. `flutter analyze` と `flutter test` を実行し、ObservationV1の座標、候補confidence、
   Interpretation API、ConfirmedHandState APIの契約が維持されていることを確認する。

## 自動確定の安全条件

- `inferred` と `unknown` は解析入力へ直接渡さない。
- あがり牌・鳴き・各牌コードはユーザーの確定操作後にのみConfirmedHandStateへ変換する。
- 牌枚数は明示選択されたoperationの検証にだけ使い、機能選択には使わない。
- 画像や枠、牌コードを変更したら、以前のInterpretationと解析結果を破棄する。
