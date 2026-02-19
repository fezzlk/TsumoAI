from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Literal
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
    honba_bonus: int = 0
    kyotaku_bonus: int = 0
    total_received: int


class ScoreResult(BaseModel):
    han: int
    fu: int
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
    score_request: ScoreRequest
    score_response: ScoreResponse
    comment: str


class ScoreFeedbackResponse(BaseModel):
    status: Literal["ok"]
    storage: dict
