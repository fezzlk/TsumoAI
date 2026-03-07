from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, conint, confloat


class Wind(str, Enum):
    E = "E"
    S = "S"
    W = "W"
    N = "N"


class WinType(str, Enum):
    ron = "ron"
    tsumo = "tsumo"


class MeldType(str, Enum):
    chi = "chi"
    pon = "pon"
    kan = "kan"
    ankan = "ankan"
    kakan = "kakan"


TileCode = str


class ErrorBody(BaseModel):
    code: str
    message: str
    details: dict | None = None


class ErrorResponse(BaseModel):
    error: ErrorBody


class TileCandidate(BaseModel):
    tile: TileCode
    confidence: confloat(ge=0.0, le=1.0)


class HandSlot(BaseModel):
    index: conint(ge=0)
    top: TileCode
    candidates: list[TileCandidate] = Field(default_factory=list)
    ambiguous: bool


class ImageMeta(BaseModel):
    width: int
    height: int
    expires_at: datetime


class ModelMeta(BaseModel):
    name: Literal["gpt-4o-mini"]
    version: str


class HandEstimate(BaseModel):
    tiles_count: int
    slots: list[HandSlot]


class RecognizeResponse(BaseModel):
    recognition_id: UUID
    status: Literal["ok"]
    image: ImageMeta
    hand_estimate: HandEstimate
    model: ModelMeta
    warnings: list[str] = Field(default_factory=list)


class RecognizeJobCreateResponse(BaseModel):
    job_id: UUID
    status: Literal["pending", "running", "completed", "failed", "canceled"]
    cancel_requested: bool = False


class RecognizeJobStatusResponse(BaseModel):
    job_id: UUID
    status: Literal["pending", "running", "completed", "failed", "canceled"]
    cancel_requested: bool = False
    created_at: datetime
    updated_at: datetime
    result: RecognizeResponse | None = None
    error: str | None = None


class Meld(BaseModel):
    type: MeldType
    tiles: list[TileCode]
    open: bool


class HandInput(BaseModel):
    closed_tiles: list[TileCode]
    melds: list[Meld] = Field(default_factory=list)
    win_tile: TileCode


class ContextInput(BaseModel):
    win_type: WinType
    is_dealer: bool
    round_wind: Wind
    seat_wind: Wind
    riichi: bool
    double_riichi: bool = False
    ippatsu: bool
    haitei: bool
    houtei: bool
    rinshan: bool
    chankan: bool
    chiihou: bool = False
    tenhou: bool = False
    dora_indicators: list[TileCode] = Field(default_factory=list)
    ura_dora_indicators: list[TileCode] = Field(default_factory=list)
    aka_dora_count: conint(ge=0) = 0
    honba: conint(ge=0) = 0
    kyotaku: conint(ge=0) = 0


class RuleSet(BaseModel):
    aka_ari: bool = True
    kuitan_ari: bool = True
    double_yakuman_ari: bool = True
    kazoe_yakuman_ari: bool = True
    renpu_fu: Literal[2, 4] = 4


class ScoreRequest(BaseModel):
    recognition_id: UUID | None = None
    hand: HandInput
    context: ContextInput
    rules: RuleSet


class YakuItem(BaseModel):
    name: str
    han: int


class DoraBreakdown(BaseModel):
    dora: int
    aka_dora: int
    ura_dora: int


class Points(BaseModel):
    ron: int = 0
    tsumo_dealer_pay: int = 0
    tsumo_non_dealer_pay: int = 0


class Payments(BaseModel):
    hand_points_received: int
    hand_points_with_honba: int
    honba_bonus: int = 0
    kyotaku_bonus: int = 0
    total_received: int


class FuBreakdownItem(BaseModel):
    name: str
    fu: int


class ScoreResult(BaseModel):
    han: int
    fu: int
    fu_breakdown: list[FuBreakdownItem] = Field(default_factory=list)
    yaku: list[YakuItem] = Field(default_factory=list)
    yakuman: list[str] = Field(default_factory=list)
    dora: DoraBreakdown
    point_label: str
    points: Points
    payments: Payments
    explanation: list[str] = Field(default_factory=list)


class ScoreResponse(BaseModel):
    score_id: UUID
    status: Literal["ok"]
    result: ScoreResult
    warnings: list[str] = Field(default_factory=list)


class RecognizeAndScorePayload(BaseModel):
    context: ContextInput
    rules: RuleSet

    model_config = ConfigDict(extra="forbid")


class RecognizeAndScoreResponse(BaseModel):
    recognition: RecognizeResponse
    score: ScoreResponse


class ResultGetResponse(BaseModel):
    id: UUID
    type: Literal["recognition", "score"]
    created_at: datetime
    expires_at: datetime
    data: dict


class ScoreFeedbackRequest(BaseModel):
    score_request: dict[str, Any] | None = None
    score_response: dict[str, Any] | None = None
    comment: str


class ScoreFeedbackResponse(BaseModel):
    status: Literal["ok"]
    storage: dict


class RecognitionFeedbackRequest(BaseModel):
    recognition_response: dict[str, Any]
    corrected_tiles: list[TileCode]
    comment: str = ""


class RecognitionFeedbackResponse(BaseModel):
    status: Literal["ok"]
    storage: dict


class DatasetUploadRequest(BaseModel):
    entries: list[dict[str, Any]]
    contributor: str | None = None


class DatasetUploadResponse(BaseModel):
    status: Literal["ok"]
    count: int
    storage: dict


# --- Game session schemas ---


class GameOptionsRequest(BaseModel):
    hakoire_end: bool = True     # 箱割れ即終了
    shanyu: bool = False         # シャーニュウ
    peinyu: bool = False         # ペーニュウ


class CreateGameRequest(BaseModel):
    player_names: list[str] = Field(
        default=["プレイヤー1", "プレイヤー2", "プレイヤー3", "プレイヤー4"],
        min_length=4,
        max_length=4,
    )
    starting_points: int = 25000
    game_type: Literal["east_only", "east_south"] = "east_only"
    options: GameOptionsRequest = Field(default_factory=GameOptionsRequest)


class ClaimSeatRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=20)


class SwapSeatsRequest(BaseModel):
    seat_a: conint(ge=0, le=3)
    seat_b: conint(ge=0, le=3)


class PlayerStateResponse(BaseModel):
    seat: int
    name: str
    points: int


class GameOptionsResponse(BaseModel):
    hakoire_end: bool
    shanyu: bool
    peinyu: bool


class GameStateResponse(BaseModel):
    game_id: UUID
    status: Literal["active", "finished"]
    players: list[PlayerStateResponse]
    current_round: int
    current_dealer: int
    current_round_wind: str
    current_honba: int
    current_kyotaku: int
    rounds_played: int
    created_at: datetime
    options: GameOptionsResponse | None = None


class RonRequest(BaseModel):
    winner_seat: conint(ge=0, le=3)
    loser_seat: conint(ge=0, le=3)
    han: conint(ge=1)
    fu: conint(ge=20) = 30
    yakuman_multiplier: int = 0
    riichi_seats: list[conint(ge=0, le=3)] = Field(default_factory=list)


class TsumoRequest(BaseModel):
    winner_seat: conint(ge=0, le=3)
    han: conint(ge=1)
    fu: conint(ge=20) = 30
    yakuman_multiplier: int = 0
    riichi_seats: list[conint(ge=0, le=3)] = Field(default_factory=list)


class DrawRequest(BaseModel):
    tenpai_seats: list[conint(ge=0, le=3)] = Field(default_factory=list)
    riichi_seats: list[conint(ge=0, le=3)] = Field(default_factory=list)


class RoundResultResponse(BaseModel):
    round_number: int
    round_wind: str
    dealer_seat: int
    honba: int
    result_type: str
    winner_seat: int | None = None
    loser_seat: int | None = None
    point_changes: dict[str, int]
    player_points_after: dict[str, int]


class GameRoundResponse(BaseModel):
    game_id: UUID
    room_code: str | None = None
    round_result: RoundResultResponse
    game_state: GameStateResponse
