from fastapi.testclient import TestClient

from app.main import app


client = TestClient(app)


def observation_document(tile_count: int) -> dict:
    tiles = ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "2p", "2p"]
    return {
        "schema_version": "1",
        "image": {"width": 1400, "height": 400, "coordinate_space": "oriented_image_pixels"},
        "observations": [
            {
                "observation_id": f"tile-{index:03d}",
                "index": index,
                "candidates": [{"tile": tile, "confidence": 0.9}],
                "bbox": {"left": index * 90, "top": 100, "right": index * 90 + 60, "bottom": 200},
            }
            for index, tile in enumerate(tiles[:tile_count])
        ],
    }


def confirmation(operation: str, tile_count: int, winning_index: int | None = None) -> dict:
    tiles = ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "2p", "2p"]
    return {
        "schema_version": "1",
        "operation": operation,
        "confirmed_tiles": [
            {"observation_id": f"tile-{index:03d}", "tile": tile}
            for index, tile in enumerate(tiles[:tile_count])
        ],
        "confirmed_winning_tile_id": None if winning_index is None else f"tile-{winning_index:03d}",
        "confirmed_melds": [],
    }


def test_confirmed_hand_endpoint_builds_explicit_score_state():
    response = client.post(
        "/api/v1/confirmed-hands",
        json={"observation": observation_document(14), "confirmation": confirmation("score", 14, 13)},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["operation"] == "score"
    assert body["hand"]["win_tile"] == "2p"
    assert body["hand"]["win_tile_observation_id"] == "tile-013"
    assert len(body["hand"]["closed_tiles"]) == 14


def test_confirmed_hand_endpoint_keeps_operation_explicit_for_tenpai():
    response = client.post(
        "/api/v1/confirmed-hands",
        json={"observation": observation_document(13), "confirmation": confirmation("tenpai", 13)},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["operation"] == "tenpai"
    assert body["hand"]["win_tile"] is None


def test_confirmed_hand_endpoint_rejects_missing_user_confirmation():
    request_confirmation = confirmation("score", 14, 13)
    request_confirmation["confirmed_tiles"].pop()

    response = client.post(
        "/api/v1/confirmed-hands",
        json={"observation": observation_document(14), "confirmation": request_confirmation},
    )

    assert response.status_code == 422
    assert "explicitly confirmed" in response.json()["detail"]
