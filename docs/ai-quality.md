# AI quality gates

TsumoAI は既存の data/recognition_eval_set.jsonl と scripts/evaluate_recognition_set.py を認識品質の正本として使う。

## リリース前の確認

1. pytest -q を実行する。
2. ラベル済み評価セットで tile精度と完全一致率を計測し、前回基準を下回らないことを確認する。
3. 誤認識は recognition_feedback.jsonl と混同行列で分類する。
4. RECOGNIZE_ENSEMBLE_PASSES の変更時は、精度だけでなく呼び出し回数・レイテンシ・API費用を記録する。
5. 画像とフィードバックに含まれる個人情報を評価セットへ混入させない。
