import json
from copy import deepcopy
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.interpretation.confirmation import assemble_confirmed_hand_state
from app.interpretation.interpreter import interpret_observations
from app.interpretation.models import ConfirmationV1, InterpretationRequest, ObservationV1


FIXTURES = Path(__file__).parent / "fixtures" / "contracts"


def load(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text())


def documents() -> tuple[ObservationV1, ConfirmationV1]:
    return (
        ObservationV1.model_validate(load("observation-v1.json")),
        ConfirmationV1.model_validate(load("confirmation-v1.json")),
    )


def test_normative_fixtures_assemble_expected_confirmed_state():
    observation, confirmation = documents()

    result = assemble_confirmed_hand_state(observation, confirmation)

    assert result.model_dump(mode="json") == load("confirmed-hand-state-v1.json")
    assert "5pr" in result.hand.closed_tiles
    meld_ids = {item for meld in result.hand.melds for item in meld.source_observation_ids}
    assert meld_ids.isdisjoint(result.hand.closed_tile_observation_ids)


def test_every_observation_requires_explicit_tile_confirmation():
    observation_data = load("observation-v1.json")
    confirmation_data = load("confirmation-v1.json")
    confirmation_data["confirmed_tiles"].pop()

    with pytest.raises(ValueError, match="all observations must be explicitly confirmed"):
        assemble_confirmed_hand_state(
            ObservationV1.model_validate(observation_data),
            ConfirmationV1.model_validate(confirmation_data),
        )


def test_inferred_winning_tile_does_not_replace_explicit_confirmation():
    observation_data = load("observation-v1.json")
    confirmation_data = load("confirmation-v1.json")
    confirmation_data["confirmed_winning_tile_id"] = None
    request = InterpretationRequest.model_validate({"observations": observation_data["observations"]})
    interpretation = interpret_observations(request)
    assert interpretation.winning_tile.status in {"inferred", "unknown"}
    assert interpretation.requires_user_confirmation is True

    with pytest.raises(ValueError, match="explicitly confirmed winning tile"):
        assemble_confirmed_hand_state(
            ObservationV1.model_validate(observation_data),
            ConfirmationV1.model_validate(confirmation_data),
        )


def test_inferred_meld_requires_user_confirmation():
    observations = [
        {
            "observation_id": f"tile-{index}",
            "index": index,
            "candidates": [{"tile": "E", "confidence": 0.9}],
            "rotation_degrees": 90 if index == 1 else 0,
            "visual_group_id": "group-a",
        }
        for index in range(3)
    ]
    observations.append(
        {
            "observation_id": "tile-3",
            "index": 3,
            "candidates": [{"tile": "5p", "confidence": 0.9}],
        }
    )
    request = InterpretationRequest.model_validate(
        {
            "observations": observations,
            "confirmed_winning_tile_id": "tile-3",
        }
    )

    result = interpret_observations(request)

    assert result.melds[0].status == "inferred"
    assert result.requires_user_confirmation is True


def test_duplicate_or_overlapping_confirmation_is_rejected():
    confirmation_data = load("confirmation-v1.json")
    confirmation_data["confirmed_tiles"].append(deepcopy(confirmation_data["confirmed_tiles"][0]))
    with pytest.raises(ValidationError, match="confirmed as a tile only once"):
        ConfirmationV1.model_validate(confirmation_data)

    confirmation_data = load("confirmation-v1.json")
    confirmation_data["confirmed_melds"].append(
        {"observation_ids": ["tile-011", "tile-000", "tile-001"], "type": "chi", "open": True}
    )
    with pytest.raises(ValidationError, match="multiple confirmed melds"):
        ConfirmationV1.model_validate(confirmation_data)


def test_unknown_observation_references_are_rejected():
    observation, _ = documents()
    confirmation_data = load("confirmation-v1.json")
    confirmation_data["confirmed_tiles"][0]["observation_id"] = "missing-tile"
    with pytest.raises(ValueError, match="reference unknown observations"):
        assemble_confirmed_hand_state(observation, ConfirmationV1.model_validate(confirmation_data))

    confirmation_data = load("confirmation-v1.json")
    confirmation_data["confirmed_melds"][0]["observation_ids"][0] = "missing-meld-tile"
    with pytest.raises(ValueError, match="meld references unknown observations"):
        assemble_confirmed_hand_state(observation, ConfirmationV1.model_validate(confirmation_data))

    confirmation_data = load("confirmation-v1.json")
    confirmation_data["confirmed_winning_tile_id"] = "missing-winning-tile"
    with pytest.raises(ValueError, match="winning tile references an unknown observation"):
        assemble_confirmed_hand_state(observation, ConfirmationV1.model_validate(confirmation_data))


def test_invalid_meld_and_winning_tile_inside_meld_are_rejected():
    observation, confirmation = documents()
    invalid_data = load("confirmation-v1.json")
    invalid_data["confirmed_melds"][0]["type"] = "chi"
    invalid_meld = ConfirmationV1.model_validate(invalid_data)
    with pytest.raises(ValueError, match="do not form chi"):
        assemble_confirmed_hand_state(observation, invalid_meld)

    winning_in_meld = confirmation.model_copy(deep=True)
    winning_in_meld.confirmed_winning_tile_id = "tile-011"
    with pytest.raises(ValueError, match="cannot be inside"):
        assemble_confirmed_hand_state(observation, winning_in_meld)


def test_more_than_four_normalized_tiles_are_rejected():
    observation, confirmation = documents()
    too_many = confirmation.model_copy(deep=True)
    for tile in too_many.confirmed_tiles[:5]:
        tile.tile = "5m" if tile.observation_id != "tile-004" else "5mr"

    with pytest.raises(ValueError, match="more than four"):
        assemble_confirmed_hand_state(observation, too_many)


def test_operation_specific_counts_and_winning_tile_rules_are_enforced():
    observation, confirmation = documents()
    tenpai_data = load("confirmation-v1.json")
    tenpai_data["operation"] = "tenpai"
    tenpai_data["confirmed_winning_tile_id"] = None
    tenpai = ConfirmationV1.model_validate(tenpai_data)
    with pytest.raises(ValueError, match="tenpai requires 13 physical tiles"):
        assemble_confirmed_hand_state(observation, tenpai)

    discard_data = load("confirmation-v1.json")
    discard_data["operation"] = "discard_analysis"
    discard_data["confirmed_winning_tile_id"] = None
    discard = ConfirmationV1.model_validate(discard_data)
    result = assemble_confirmed_hand_state(observation, discard)
    assert result.hand.win_tile is None
    assert result.hand.win_tile_observation_id is None


def test_observation_geometry_uses_oriented_image_bounds():
    data = load("observation-v1.json")
    data["observations"][0]["bbox"]["right"] = data["image"]["width"] + 1
    with pytest.raises(ValidationError, match="outside the image"):
        ObservationV1.model_validate(data)

    data = load("observation-v1.json")
    data["observations"][0]["rotation_degrees"] = 180
    with pytest.raises(ValidationError, match="rotation_degrees"):
        ObservationV1.model_validate(data)


def test_observation_document_rejects_duplicate_ids_and_indices():
    data = load("observation-v1.json")
    data["observations"][1]["observation_id"] = data["observations"][0]["observation_id"]
    with pytest.raises(ValidationError, match="observation_id must be unique"):
        ObservationV1.model_validate(data)

    data = load("observation-v1.json")
    data["observations"][1]["index"] = data["observations"][0]["index"]
    with pytest.raises(ValidationError, match="observation index must be unique"):
        ObservationV1.model_validate(data)


def test_observation_document_rejects_empty_id_negative_index_and_empty_group():
    data = load("observation-v1.json")
    data["observations"][0]["observation_id"] = ""
    with pytest.raises(ValidationError, match="observation_id must not be empty"):
        ObservationV1.model_validate(data)

    data = load("observation-v1.json")
    data["observations"][0]["index"] = -1
    with pytest.raises(ValidationError, match="index must be non-negative"):
        ObservationV1.model_validate(data)

    data = load("observation-v1.json")
    data["observations"][0]["visual_group_id"] = ""
    with pytest.raises(ValidationError, match="visual_group_id must not be empty"):
        ObservationV1.model_validate(data)


def test_assemble_rejects_invalid_confirmed_tile_code():
    observation, _ = documents()
    confirmation_data = load("confirmation-v1.json")
    confirmation_data["confirmed_tiles"][0]["tile"] = "10m"
    with pytest.raises(ValueError, match="invalid confirmed tile code"):
        assemble_confirmed_hand_state(observation, ConfirmationV1.model_validate(confirmation_data))


def test_assemble_rejects_overlapping_melds_added_after_validation():
    """ConfirmationV1's own validator rejects this at construction time; this
    guards the service function itself against a mutated-after-validation object."""
    observation, confirmation = documents()
    mutated = confirmation.model_copy(deep=True)
    mutated.confirmed_melds.append(mutated.confirmed_melds[0].model_copy(deep=True))
    with pytest.raises(ValueError, match="multiple confirmed melds"):
        assemble_confirmed_hand_state(observation, mutated)


def test_assemble_rejects_winning_tile_when_operation_is_not_score():
    observation, confirmation = documents()
    non_score = confirmation.model_copy(deep=True)
    non_score.operation = "tenpai"
    with pytest.raises(ValueError, match="winning tile must be null unless operation is score"):
        assemble_confirmed_hand_state(observation, non_score)


def test_validate_meld_rejects_wrong_observation_count():
    observation, _ = documents()
    confirmation_data = load("confirmation-v1.json")
    confirmation_data["confirmed_melds"] = [
        {"observation_ids": ["tile-000", "tile-001", "tile-002", "tile-003"], "type": "pon", "open": True}
    ]
    with pytest.raises(ValueError, match="pon must contain exactly 3 observations"):
        assemble_confirmed_hand_state(observation, ConfirmationV1.model_validate(confirmation_data))


def test_validate_meld_rejects_chi_with_unsuited_tile():
    observation, _ = documents()
    confirmation_data = load("confirmation-v1.json")
    confirmation_data["confirmed_melds"] = [
        {"observation_ids": ["tile-009", "tile-000", "tile-001"], "type": "chi", "open": True}
    ]
    with pytest.raises(ValueError, match="chi must contain suited tiles"):
        assemble_confirmed_hand_state(observation, ConfirmationV1.model_validate(confirmation_data))


def test_validate_meld_accepts_valid_open_chi():
    observation, _ = documents()
    confirmation_data = load("confirmation-v1.json")
    confirmation_data["confirmed_melds"] = [
        {"observation_ids": ["tile-000", "tile-001", "tile-002"], "type": "chi", "open": True}
    ]
    result = assemble_confirmed_hand_state(observation, ConfirmationV1.model_validate(confirmation_data))
    assert result.hand.melds[0].tiles == ["1m", "2m", "3m"]


def test_validate_meld_rejects_closed_chi():
    observation, _ = documents()
    confirmation_data = load("confirmation-v1.json")
    confirmation_data["confirmed_melds"] = [
        {"observation_ids": ["tile-000", "tile-001", "tile-002"], "type": "chi", "open": False}
    ]
    with pytest.raises(ValueError, match="chi must be open"):
        assemble_confirmed_hand_state(observation, ConfirmationV1.model_validate(confirmation_data))


def test_validate_meld_rejects_ankan_declared_open():
    observation, _ = documents()
    confirmation_data = load("confirmation-v1.json")
    confirmation_data["confirmed_tiles"][0]["tile"] = "5s"  # tile-000 -> a 4th "5s" alongside tile-011..013
    confirmation_data["confirmed_melds"] = [
        {"observation_ids": ["tile-011", "tile-012", "tile-013", "tile-000"], "type": "ankan", "open": True}
    ]
    with pytest.raises(ValueError, match="ankan open must be false"):
        assemble_confirmed_hand_state(observation, ConfirmationV1.model_validate(confirmation_data))


def test_validate_meld_rejects_pon_with_non_identical_tiles():
    observation, _ = documents()
    confirmation_data = load("confirmation-v1.json")
    confirmation_data["confirmed_melds"] = [
        {"observation_ids": ["tile-000", "tile-001", "tile-002"], "type": "pon", "open": True}
    ]
    with pytest.raises(ValueError, match="do not form pon"):
        assemble_confirmed_hand_state(observation, ConfirmationV1.model_validate(confirmation_data))
