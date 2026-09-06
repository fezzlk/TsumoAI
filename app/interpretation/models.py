from __future__ import annotations

from enum import Enum
from typing import Literal

from pydantic import BaseModel, Field, confloat, model_validator

from app.schemas import MeldType, TileCandidate


class FactStatus(str, Enum):
    confirmed = "confirmed"
    inferred = "inferred"
    unknown = "unknown"


class Operation(str, Enum):
    score = "score"
    tenpai = "tenpai"
    discard_analysis = "discard_analysis"


class CoordinateSpace(str, Enum):
    oriented_image_pixels = "oriented_image_pixels"


class BoundingBox(BaseModel):
    left: float
    top: float
    right: float
    bottom: float


class ObservationImage(BaseModel):
    width: int = Field(gt=0)
    height: int = Field(gt=0)
    coordinate_space: CoordinateSpace


class TileObservation(BaseModel):
    observation_id: str
    index: int
    candidates: list[TileCandidate]
    bbox: BoundingBox | None = None
    rotation_degrees: float | None = None
    visual_group_id: str | None = None


class ObservationV1(BaseModel):
    schema_version: Literal["1"]
    image: ObservationImage
    observations: list[TileObservation]

    @model_validator(mode="after")
    def validate_observations(self) -> "ObservationV1":
        ids = [item.observation_id for item in self.observations]
        if len(ids) != len(set(ids)):
            raise ValueError("observation_id must be unique")
        indices = [item.index for item in self.observations]
        if len(indices) != len(set(indices)):
            raise ValueError("observation index must be unique")
        for item in self.observations:
            if not item.observation_id:
                raise ValueError("observation_id must not be empty")
            if item.index < 0:
                raise ValueError("observation index must be non-negative")
            if item.rotation_degrees is not None and not -180 <= item.rotation_degrees < 180:
                raise ValueError("rotation_degrees must be in [-180, 180)")
            if item.visual_group_id == "":
                raise ValueError("visual_group_id must not be empty")
            if item.bbox is not None and not (
                0 <= item.bbox.left < item.bbox.right <= self.image.width
                and 0 <= item.bbox.top < item.bbox.bottom <= self.image.height
            ):
                raise ValueError(f"bounding box is outside the image: {item.observation_id}")
        return self


class ConfirmedMeld(BaseModel):
    observation_ids: list[str]
    type: MeldType
    open: bool


class ConfirmedTile(BaseModel):
    observation_id: str
    tile: str


class ConfirmationV1(BaseModel):
    schema_version: Literal["1"]
    operation: Operation
    confirmed_tiles: list[ConfirmedTile]
    confirmed_winning_tile_id: str | None = None
    confirmed_melds: list[ConfirmedMeld] = Field(default_factory=list)

    @model_validator(mode="after")
    def validate_unique_assignments(self) -> "ConfirmationV1":
        tile_ids = [item.observation_id for item in self.confirmed_tiles]
        if len(tile_ids) != len(set(tile_ids)):
            raise ValueError("each observation can be confirmed as a tile only once")
        meld_ids = [item for meld in self.confirmed_melds for item in meld.observation_ids]
        if len(meld_ids) != len(set(meld_ids)):
            raise ValueError("an observation cannot belong to multiple confirmed melds")
        return self


class ConfirmedHandMeldV1(BaseModel):
    type: MeldType
    tiles: list[str]
    open: bool
    source_observation_ids: list[str]


class ConfirmedHandV1(BaseModel):
    closed_tiles: list[str]
    closed_tile_observation_ids: list[str]
    melds: list[ConfirmedHandMeldV1] = Field(default_factory=list)
    win_tile: str | None = None
    win_tile_observation_id: str | None = None


class ConfirmedHandStateV1(BaseModel):
    schema_version: Literal["1"] = "1"
    operation: Operation
    hand: ConfirmedHandV1


class InterpretationRequest(BaseModel):
    observations: list[TileObservation]
    confirmed_winning_tile_id: str | None = None
    confirmed_melds: list[ConfirmedMeld] = Field(default_factory=list)


class RecognitionInterpretationRequest(BaseModel):
    confirmed_winning_tile_id: str | None = None
    confirmed_melds: list[ConfirmedMeld] = Field(default_factory=list)


class MeldInterpretation(BaseModel):
    observation_ids: list[str]
    type: MeldType
    tiles: list[str]
    open: bool | None
    status: FactStatus
    confidence: confloat(ge=0.0, le=1.0)
    evidence: list[str] = Field(default_factory=list)


class WinningTileInterpretation(BaseModel):
    observation_id: str | None = None
    tile: str | None = None
    status: FactStatus
    confidence: confloat(ge=0.0, le=1.0)
    evidence: list[str] = Field(default_factory=list)


class InterpretationResponse(BaseModel):
    melds: list[MeldInterpretation] = Field(default_factory=list)
    winning_tile: WinningTileInterpretation
    requires_user_confirmation: bool
    warnings: list[str] = Field(default_factory=list)
