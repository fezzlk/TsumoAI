# Backend domain architecture

編集可能な全体構成図: [tsumoai-architecture.drawio](./tsumoai-architecture.drawio)

## Goal

The backend domain layer is the single source of truth for mahjong structure and analysis.
It supports winning-hand scoring, shanten calculation, waits, and discard analysis without
depending on image recognition, HTTP, persistence, or a specific UI.

## Dependency direction

```text
API / future image interpretation
            |
         use case
            |
  domain analysis + scoring
```

Dependencies point inward. `app/domain` must remain deterministic and side-effect free.
Network calls, image bytes, model confidence, database records, and FastAPI exceptions do
not belong in it.

## Modules and contracts

### `domain.tiles`

- Owns valid tile codes and the canonical 34-index representation.
- Normalizes red fives for structural calculations.
- Rejects invalid codes and impossible normalized counts.
- Does not decide hand validity or scoring.

### `domain.decomposition`

- Determines standard, seven-pairs, and thirteen-orphans winning shapes.
- Enumerates every standard decomposition because yaku and fu may differ by interpretation.
- Accepts already completed meld count, but does not interpret image layout or table context.

### `domain.shanten`

- Calculates the minimum of standard, seven-pairs, and thirteen-orphans shanten.
- Uses only normalized tile counts and completed meld count.
- A return value of `-1` means complete; `0` means tenpai.

### `domain.analysis`

- Enumerates tiles that reduce shanten and their remaining visible count.
- Evaluates each distinct discard from a draw-state hand.
- Does not calculate points. This keeps structural analysis reusable and fast.

### `hand_analysis` use case

- Validates whether the request is a draw state or discard state.
- Combines structural analysis with the existing scoring engine.
- Requests a score only for a genuine winning draw from a tenpai state.
- A score error is retained per wait; for example, a structurally complete hand may have no yaku.

## Scoring components

Scoring is separated under `app/scoring` so each rules concern can be tested without HTTP or
image recognition.

- `payments.py` owns limit labels, base points, rounding, ron/tsumo allocation, honba, and kyotaku.
- `fu.py` owns pair, wait, meld, open/closed, ron/tsumo fu and rounding.
- `dora.py` owns indicator cycling and normal, red, and ura-dora counting.
- `yaku.py` owns context/event yaku evaluation.
- `hand_yaku.py` owns tile and decomposition-dependent ordinary yaku.
- `yakuman.py` owns yakuman and double-yakuman evaluation.
- `calculator.py` chooses the highest-value valid decomposition and assembles the score result.
- `hand_scoring.py` is an eight-line compatibility facade; it contains no scoring rules.

## Future image interpretation boundary

Image recognition must emit observations rather than final mahjong facts: tile candidates,
bounding boxes, orientation, spacing, and visual groups. A separate interpretation layer will
infer meld candidates and winning-tile candidates with confidence and evidence. Scoring accepts
only a confirmed hand state and never reads pixels or coordinates.

User confirmation is a first-class path for ambiguous melds and winning tiles. Fixed-phone
capture and placement guides may improve accuracy, but are not yet product requirements: they
trade recognition quality against setup burden and lack an obvious mounting position on a
typical mahjong table. The default capture contract remains undecided until UX testing.

`POST /api/v1/interpretations` implements this boundary. Its input contains structured tile
observations and optional user-confirmed facts. Its output deliberately remains an interpretation:
it does not call scoring or tenpai analysis and does not manufacture a confirmed `HandInput`.

`POST /api/v1/confirmed-hands` is the separate confirmation boundary. It accepts an
`ObservationV1` document and an explicit `ConfirmationV1`, rejects missing or overlapping tile
assignments, and returns `ConfirmedHandStateV1`. The mobile client then calls only the endpoint
named by the user's selected operation. Interpretation candidates are never promoted by this API;
every physical tile, meld, and scoring winning tile must be explicitly confirmed.

Fact status has three values:

- `confirmed`: supplied explicitly by the user.
- `inferred`: supported by sufficiently strong visual and tile evidence.
- `unknown`: plausible candidate but insufficient evidence; UI confirmation is required.

The initial deterministic policy can infer an open meld from a vision-provided spatial group,
valid chi/pon/kan tiles, and a sideways tile. It can infer a winning-tile candidate from a
separated tile at the end of the concealed run. These rules are intentionally conservative and
produce `unknown` when geometry or open-state evidence is absent. Thresholds are policy details,
not mahjong-domain rules, and will be tuned against a versioned interpretation evaluation set.

Local server recognition retains each detector bounding box in its recognition slot. The
recognition-to-interpretation adapter converts stored slots into observations without re-reading
the image. Recognition routes without geometry remain valid, but interpretation returns an
unknown winning tile instead of assuming that the final slot is the winning tile.

## API

The operation is always selected explicitly by the caller. Tile count is validation input and
must never select a feature implicitly.

- `POST /api/v1/tenpai/analyze` returns shanten and improving tiles. At shanten 0 these are waits.
- `POST /api/v1/discards/analyze` returns one result per distinct discard.
- `POST /api/v1/score` remains the explicit winning-hand scoring operation.
- `remaining` is calculated from the closed tiles and declared melds visible in the request.
- If `context` is supplied and score prediction is enabled, tenpai waits include a score using
  that context's ron/tsumo setting. Unknown future conditions such as ura-dora are not guessed.

For `m` declared melds, effective closed tile counts are `13 - 3m` for draw analysis and
`14 - 3m` for discard analysis. A kan still counts as one completed meld for structure even
though four physical tiles are visible.

## Accuracy and performance requirements

- Domain results must be deterministic and independently testable.
- All 34 candidate draws are evaluated locally; there are no module-to-module network calls.
- Recursive structural functions use bounded caches keyed by immutable 34-count tuples.
- Recognition candidates must eventually enter through a separate interpretation layer; visual
  confidence must not be silently overwritten by structural plausibility.
- Regression cases should cover standard hands, seven pairs, thirteen orphans, open hands,
  red-five normalization, multi-wait hands, exhausted tiles, and no-yaku winning shapes.
