from fastapi.testclient import TestClient
from io import BytesIO

from PIL import Image

from app.interpretation.interpreter import interpret_observations
from app.interpretation.models import InterpretationRequest
from app import main as main_module
from app.main import app
from app.tile_recognizer_local import recognize_tiles_local


def observation(index: int, tile: str, *, left: float | None = None, group: str | None = None, rotation: float = 0):
    item = {
        "observation_id": f"tile-{index}",
        "index": index,
        "candidates": [{"tile": tile, "confidence": 0.9}],
        "rotation_degrees": rotation,
        "visual_group_id": group,
    }
    if left is not None:
        item["bbox"] = {"left": left, "top": 0, "right": left + 10, "bottom": 20}
    return item


def test_winning_tile_stays_unknown_without_geometry():
    result = interpret_observations(
        InterpretationRequest.model_validate({"observations": [observation(0, "1m"), observation(1, "2m")]})
    )
    assert result.winning_tile.status == "unknown"
    assert result.winning_tile.observation_id is None
    assert result.requires_user_confirmation is True


def test_separated_end_tile_is_inferred_but_not_confirmed():
    request = InterpretationRequest.model_validate(
        {"observations": [observation(0, "1m", left=0), observation(1, "2m", left=10), observation(2, "3m", left=28)]}
    )
    result = interpret_observations(request)
    assert result.winning_tile.observation_id == "tile-2"
    assert result.winning_tile.status == "inferred"
    assert "end_of_concealed_run" in result.winning_tile.evidence


def test_user_confirmation_overrides_ambiguous_geometry():
    request = InterpretationRequest.model_validate(
        {
            "observations": [observation(0, "1m", left=0), observation(1, "2m", left=10)],
            "confirmed_winning_tile_id": "tile-0",
        }
    )
    result = interpret_observations(request)
    assert result.winning_tile.status == "confirmed"
    assert result.winning_tile.tile == "1m"
    assert result.requires_user_confirmation is False


def test_sideways_valid_visual_group_is_an_inferred_open_meld():
    request = InterpretationRequest.model_validate(
        {
            "observations": [
                observation(0, "E", group="group-a"),
                observation(1, "E", group="group-a", rotation=90),
                observation(2, "E", group="group-a"),
                observation(3, "5p"),
            ],
            "confirmed_winning_tile_id": "tile-3",
        }
    )
    result = interpret_observations(request)
    assert result.melds[0].type == "pon"
    assert result.melds[0].open is True
    assert result.melds[0].status == "inferred"
    assert result.requires_user_confirmation is True


def test_valid_group_without_open_evidence_requires_confirmation():
    request = InterpretationRequest.model_validate(
        {
            "observations": [
                observation(0, "1m", group="group-a"),
                observation(1, "2m", group="group-a"),
                observation(2, "3m", group="group-a"),
            ],
            "confirmed_winning_tile_id": "tile-2",
        }
    )
    result = interpret_observations(request)
    assert result.melds[0].status == "unknown"
    assert result.melds[0].open is None
    assert result.requires_user_confirmation is True


def test_api_rejects_invalid_confirmed_meld():
    response = TestClient(app).post(
        "/api/v1/interpretations",
        json={
            "observations": [observation(0, "1m"), observation(1, "2m"), observation(2, "4m")],
            "confirmed_melds": [{"observation_ids": ["tile-0", "tile-1", "tile-2"], "type": "chi", "open": True}],
        },
    )
    assert response.status_code == 422


def test_local_recognizer_preserves_detection_boxes(monkeypatch):
    monkeypatch.setattr("app.tile_recognizer_local._load_model", lambda: None)
    monkeypatch.setattr(
        "app.tile_recognizer_local._segment_tile_boxes",
        lambda _image: [(0, 20, index * 10, index * 10 + 10) for index in range(13)],
    )
    monkeypatch.setattr("app.tile_recognizer_local._classify_tile", lambda _image: ("characters-1", 0.9))
    buffer = BytesIO()
    Image.new("RGB", (140, 20), "white").save(buffer, format="PNG")

    result = recognize_tiles_local(buffer.getvalue())

    assert result["slots"][2]["observation_id"] == "tile-2"
    assert result["slots"][2]["bbox"] == {"left": 20, "top": 0, "right": 30, "bottom": 20}


def test_recognition_id_can_be_interpreted_and_user_confirmed():
    slots = [
        {
            "index": index,
            "top": tile,
            "candidates": [{"tile": tile, "confidence": 0.9}],
            "ambiguous": False,
            "observation_id": f"observed-{index}",
        }
        for index, tile in enumerate(("1m", "2m", "3m"))
    ]
    record = main_module.repo.create(
        "recognition",
        {"hand_estimate": {"tiles_count": 3, "slots": slots}},
    )

    response = TestClient(app).post(
        f"/api/v1/recognitions/{record.id}/interpret",
        json={"confirmed_winning_tile_id": "observed-1"},
    )

    assert response.status_code == 200
    assert response.json()["winning_tile"] == {
        "observation_id": "observed-1",
        "tile": "2m",
        "status": "confirmed",
        "confidence": 1.0,
        "evidence": ["user_confirmed"],
    }


def test_recognition_without_geometry_does_not_guess_last_tile():
    slots = [
        {"index": index, "top": tile, "candidates": [{"tile": tile, "confidence": 0.9}], "ambiguous": False}
        for index, tile in enumerate(("1m", "2m", "3m"))
    ]
    record = main_module.repo.create("recognition", {"hand_estimate": {"tiles_count": 3, "slots": slots}})

    response = TestClient(app).post(f"/api/v1/recognitions/{record.id}/interpret", json={})

    assert response.status_code == 200
    assert response.json()["winning_tile"]["status"] == "unknown"
    assert response.json()["winning_tile"]["observation_id"] is None
