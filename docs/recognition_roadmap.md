# Recognition Roadmap Memo

## Current focus (implemented now)
- Keep existing `score-ui` flow and improve "phase 2" recognition quality.
- Use multi-pass image preprocessing + ensemble merge in `app/hand_extraction.py`.
- Preserve current API contract (`/api/v1/recognize`, `/api/v1/recognize-only`, `/api/v1/recognize-and-score`).

## Future phase 1 (to implement later)
- Add camera preview mode in UI (`getUserMedia`) with real-time frame checks.
- Detect "tile-like 14 objects are stably visible" without classifying exact tile IDs.
- When stable condition is met, lock frame and switch UI to recognition mode.

## Future phase 3 (to implement later)
- Add explicit UX states:
  1. live scan
  2. lock/identify mode with loading
  3. recognition result review
  4. score confirmation
- Add progressive feedback in UI (scan confidence, lock reason, retry button).
- Store telemetry for false positives/false negatives during scan-to-lock transition.
