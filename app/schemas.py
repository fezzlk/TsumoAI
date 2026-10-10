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


class SlotBoundingBox(BaseModel):
    left: float
    top: float
    right: float
    bottom: float


class HandSlot(BaseModel):
    index: conint(ge=0)
    top: TileCode
    candidates: list[TileCandidate] = Field(default_factory=list)
    ambiguous: bool
    observation_id: str | None = None
    bbox: SlotBoundingBox | None = None
    rotation_degrees: float | None = None
    visual_group_id: str | None = None


class ImageMeta(BaseModel):
    width: int
    height: int
    expires_at: datetime


class ModelMeta(BaseModel):
    name: Literal["gpt-4o-mini", "tflite-mobilenetv2"]
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
    kazoe_yakuman_ari: bool = Field(
        default=True,
        description="When false, ordinary hands with 13+ han are capped at sanbaiman (base 6000); natural yakuman are unaffected.",
    )
    renpu_fu: Literal[2, 4] = 4


class MahjongRuleSettings(BaseModel):
    version: Literal[1] = 1
    rules: RuleSet = Field(default_factory=RuleSet)
    tobi_end: bool = True
    chips_enabled: bool = False
    open_hand_chips_enabled: bool = True


class MahjongRuleSettingsDocument(MahjongRuleSettings):
    updated_at: datetime


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


class AnalysisRequestBase(BaseModel):
    closed_tiles: list[TileCode]
    melds: list[Meld] = Field(default_factory=list)
    context: ContextInput | None = None
    rules: RuleSet = Field(default_factory=RuleSet)
    include_score_predictions: bool = True


class TenpaiAnalysisRequest(AnalysisRequestBase):
    pass


class DiscardAnalysisRequest(AnalysisRequestBase):
    pass


class WaitAnalysis(BaseModel):
    tile: TileCode
    remaining: conint(ge=0, le=4)
    score: ScoreResult | None = None
    score_error: str | None = None


class TenpaiWaitAnalysis(WaitAnalysis):
    ron_score: ScoreResult | None = None
    ron_score_error: str | None = None
    tsumo_score: ScoreResult | None = None
    tsumo_score_error: str | None = None


class CallYakuProspect(BaseModel):
    name: str
    han: int
    condition: str


class CallScoreEstimate(BaseModel):
    min_points: int
    max_points: int
    basis: str
    win_type: Literal["ron", "tsumo"] = "ron"


class CallWinningTile(BaseModel):
    tile: TileCode
    yaku: list[str]
    han: int
    fu: int
    ron_points: int | None = None
    win_type: Literal["ron", "tsumo"] = "ron"
    tsumo_dealer_pay: int | None = None
    tsumo_non_dealer_pay: int | None = None


class CallOutlook(BaseModel):
    status: Literal["available", "conditional", "no_yaku", "unknown"]
    summary: str
    yaku: list[CallYakuProspect] = Field(default_factory=list)
    nearby_yaku: list[CallYakuProspect] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    score_estimate: CallScoreEstimate | None = None
    winning_tiles: list[CallWinningTile] = Field(default_factory=list)
    no_yaku_tiles: list[TileCode] = Field(default_factory=list)


class DiscardAnalysisResult(BaseModel):
    discard: TileCode
    shanten: int
    improving_tiles: list[WaitAnalysis] = Field(default_factory=list)
    total_remaining: conint(ge=0) = 0
    call_outlook: CallOutlook | None = None


class TenpaiAnalysisResponse(BaseModel):
    shanten: int
    improving_tiles: list[TenpaiWaitAnalysis] = Field(default_factory=list)
    score_conditions: list[str] = Field(default_factory=list)


class DiscardAnalysisResponse(BaseModel):
    shanten: int
    # Shanten of the 14-tile hand itself: -1 means it is already complete
    # (a winning shape), 0 that it is tenpai before discarding.
    hand_shanten: int | None = None
    discards: list[DiscardAnalysisResult] = Field(default_factory=list)


class CallAnalysisRequest(AnalysisRequestBase):
    pass


class CallAnalysisResult(BaseModel):
    call_tile: TileCode
    call_type: Literal["chi", "pon", "kan"]
    consumed_tiles: list[TileCode]
    shanten_after_call: int
    recommendation: Literal["improves", "keeps", "worsens"]
    tenpai_effect: Literal["adds_yaku", "keeps", "breaks"] | None = None
    possible_yaku: list[str] = Field(default_factory=list)
    outlook: CallOutlook | None = None
    discards: list[DiscardAnalysisResult] = Field(default_factory=list)
    replacement_tiles: list[WaitAnalysis] = Field(default_factory=list)


class CallCurrentWait(BaseModel):
    tile: TileCode
    remaining: conint(ge=0, le=4)
    ron_status: Literal["available", "no_yaku", "unknown"]
    yaku: list[str] = Field(default_factory=list)


class CallAnalysisResponse(BaseModel):
    current_shanten: int
    current_waits: list[CallCurrentWait] = Field(default_factory=list)
    calls: list[CallAnalysisResult] = Field(default_factory=list)


class HistoryItemUpsert(BaseModel):
    created_at: datetime
    purpose: Literal["score", "wait", "discard", "call_advice"]
    title: str = Field(min_length=1, max_length=80)
    summary: str = Field(min_length=1, max_length=300)
    round_label: str | None = Field(default=None, max_length=40)
    details: dict[str, Any] = Field(default_factory=dict)


class HistoryItem(HistoryItemUpsert):
    id: UUID
    updated_at: datetime


class HistoryListResponse(BaseModel):
    items: list[HistoryItem] = Field(default_factory=list)


class QuestionTemplateUpsert(BaseModel):
    name: str = Field(min_length=1, max_length=30)
    body: str = Field(min_length=1, max_length=300)
    created_at: datetime | None = None


class QuestionTemplateItem(QuestionTemplateUpsert):
    id: UUID
    created_at: datetime
    updated_at: datetime


class QuestionTemplateListResponse(BaseModel):
    items: list[QuestionTemplateItem] = Field(default_factory=list)


class AIChatMessage(BaseModel):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=1200)

    model_config = ConfigDict(extra="forbid")


class AIChatContext(BaseModel):
    purpose: Literal["discard", "call_advice"]
    tiles: list[TileCode] = Field(min_length=1, max_length=18)
    round_context: dict[str, Any] = Field(default_factory=dict)
    analysis: dict[str, Any] = Field(default_factory=dict)
    situation_tags: list[str] = Field(default_factory=list, max_length=10)

    model_config = ConfigDict(extra="forbid")


class AIChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=600)
    conversation: list[AIChatMessage] = Field(default_factory=list, max_length=12)
    context: AIChatContext

    model_config = ConfigDict(extra="forbid")


class AIUsageStatus(BaseModel):
    period: str
    plan: Literal["free", "subscription"]
    included_limit: int = Field(ge=0)
    included_used: int = Field(ge=0)
    bonus_remaining: int = Field(ge=0)
    remaining: int = Field(ge=0)
    resets_at: datetime


class AIChatResponse(BaseModel):
    answer: str
    usage: AIUsageStatus


class OfficialAIChatTemplate(BaseModel):
    id: str = Field(min_length=1, max_length=60, pattern=r"^[a-zA-Z0-9_-]+$")
    kind: Literal["situation", "question"]
    purpose: Literal["all", "discard", "call_advice"] = "all"
    label: str = Field(min_length=1, max_length=40)
    body: str = Field(min_length=1, max_length=200)
    enabled: bool = True
    sort_order: int = Field(default=0, ge=0, le=1000)

    model_config = ConfigDict(extra="forbid")


class OfficialAIChatTemplateUpdate(BaseModel):
    items: list[OfficialAIChatTemplate] = Field(min_length=1, max_length=50)

    model_config = ConfigDict(extra="forbid")


class OfficialAIChatTemplateConfig(OfficialAIChatTemplateUpdate):
    version: int = Field(ge=1)
    updated_at: datetime | None = None


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


class TrainingDataEntry(BaseModel):
    id: str
    tile_code: str
    source: str
    image_path: str
    created_at: str


class TrainingDataListResponse(BaseModel):
    entries: list[TrainingDataEntry]
    stats: dict


class TrainingDataUploadResponse(BaseModel):
    status: Literal["ok"]
    id: str
    image_path: str


class MyDataDeletionResponse(BaseModel):
    status: Literal["ok"]
    deleted_training_data: int
    deleted_score_feedback: int
    deleted_recognition_feedback: int
    deleted_dataset_uploads: int
    deleted_scan_diagnostics: int = 0
