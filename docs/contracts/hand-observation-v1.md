# Hand Observation Contract V1

## Purpose

This contract separates image-derived observations from confirmed mahjong facts. Python and
Flutter exchange the same JSON without either side guessing missing geometry, a winning tile,
melds, or the requested feature.

The three example payloads under `tests/fixtures/contracts/` are normative V1 fixtures.
Producers may omit optional JSON members, but consumers must treat an omitted member and an
explicit `null` identically.

## Shared rules

- Every payload has `schema_version: "1"`.
- Tile codes use the existing TsumoAI notation: `1m`-`9m`, `1p`-`9p`, `1s`-`9s`, honors
  `E`, `S`, `W`, `N`, `P`, `F`, `C`, and red fives `5mr`, `5pr`, `5sr`.
- `observation_id` is stable within one capture and uniquely identifies one physical tile.
  Reordering the display must not change it.
- `index` is the producer's zero-based display order. Identity must never be inferred from it.
- Confidence is a finite number in the inclusive range `0.0` through `1.0`.
- Unknown data remains absent or `null`. A producer must not synthesize geometry or mahjong facts.
- `inferred` and `unknown` interpretation results are not confirmations. Only explicit user
  confirmation can produce a confirmed hand state.

## ObservationV1

ObservationV1 records what recognition saw. It does not select scoring, tenpai analysis, or
discard analysis.

```text
schema_version: "1"
image:
  width: positive integer
  height: positive integer
  coordinate_space: "oriented_image_pixels"
observations[]:
  observation_id: non-empty string, unique in the payload
  index: non-negative integer, unique in the payload
  candidates[]:
    tile: tile code
    confidence: 0.0 .. 1.0
  bbox: {left, top, right, bottom} | null
  rotation_degrees: number in [-180, 180) | null
  visual_group_id: non-empty string | null
```

### Coordinate convention

`oriented_image_pixels` means coordinates after EXIF orientation has been baked into the image.
The origin is the top-left pixel, +x points right, and +y points down. Bounding-box edges use
floating-point pixel coordinates and must satisfy:

```text
0 <= left < right <= image.width
0 <= top < bottom <= image.height
```

`rotation_degrees` is the angle of the physical tile's top edge relative to the image +x axis.
Because +y points down, positive values are clockwise. Values are normalized to `[-180, 180)`.
This is not the correction angle used to straighten a crop.

`visual_group_id` states only that observations belong to the same image-derived spatial group.
It does not assert that the group is a valid meld. Equal non-null IDs identify a group; IDs have
no meaning across captures.

Candidates are ordered from highest to lowest producer confidence. An empty candidate list is
valid and requires user correction.

## ConfirmationV1

ConfirmationV1 records explicit user choices over one ObservationV1 payload.

```text
schema_version: "1"
operation: "score" | "tenpai" | "discard_analysis"
confirmed_tiles[]:
  observation_id: an ID from ObservationV1, unique in this list
  tile: tile code
confirmed_winning_tile_id: observation ID | null
confirmed_melds[]:
  observation_ids: three or four unique observation IDs
  type: "chi" | "pon" | "kan" | "ankan" | "kakan"
  open: boolean
```

`operation` is always chosen explicitly by the user. Tile count validates an operation but never
selects one. `confirmed_winning_tile_id` is required for `score` and is `null` for `tenpai` and
`discard_analysis`. Every observation must have exactly one entry in `confirmed_tiles` before a
confirmed hand state can be assembled.

Observations in different melds must not overlap. A meld observation cannot also become a closed
tile. Meld shape, open state, physical count, tile multiplicity, and operation-specific hand size
are validated while assembling the confirmed hand state.

## ConfirmedHandStateV1

ConfirmedHandStateV1 contains mahjong facts only. It contains no bounding boxes, rotation,
recognition confidence, visual grouping, or inferred values.

```text
schema_version: "1"
operation: "score" | "tenpai" | "discard_analysis"
hand:
  closed_tiles: tile codes
  closed_tile_observation_ids: observation IDs in matching order
  melds[]:
    type: meld type
    tiles: three or four tile codes
    open: boolean
    source_observation_ids: observation IDs in matching order
  win_tile: tile code | null
  win_tile_observation_id: observation ID | null
```

All source observations are assigned exactly once to either `closed_tiles` or one meld.
`closed_tile_observation_ids` and `source_observation_ids` preserve traceability but do not carry
image semantics into domain calculations.

For `score`, `win_tile` designates one tile already present in `closed_tiles`; it is not an
additional physical tile. Its code must equal the closed tile associated with
`win_tile_observation_id`. Both winning-tile fields are `null` for the other operations.

The assembler must reject incomplete confirmation, unknown references, duplicate assignment,
invalid melds, invalid operation-specific tile counts, and five or more copies of a normalized
tile. Red-five spelling is retained in the confirmed state.

## Versioning

V1 readers must reject unsupported major versions. Adding an optional field with unchanged
meaning is backward-compatible. Renaming a field, changing coordinate semantics, changing
requiredness, or changing the meaning of an enum requires a new major version and new normative
fixtures.

## Migration targets from the current API

No production API is changed by this contract task. Follow-up work must address these gaps:

1. `InterpretationRequest` has no `schema_version`, image dimensions, or coordinate-space field.
2. The current interpretation confirmation accepts winning tile and melds but cannot confirm or
   correct each observation's tile code.
3. Current recognition slots allow geometry, but not every recognition path preserves it.
4. Current `requires_user_confirmation` can be false for inferred facts. V1 requires every
   inferred fact to remain unconfirmed until explicit user action.
5. There is no production `ConfirmedHandStateV1` model or assembler.
6. There is no endpoint connecting a confirmed state to an explicitly selected operation.
7. The legacy score path may derive a completed shape and use the last slot as the winning tile;
   it must not be used by the V1 confirmation flow.
8. Existing `HandInput` has no observation traceability. An adapter must intentionally remove
   traceability only after V1 validation, when calling the pure domain/scoring layer.
