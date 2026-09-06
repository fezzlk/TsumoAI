from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_analyze_thirteen_tiles_with_score_prediction():
    response = client.post(
        "/api/v1/tenpai/analyze",
        json={
            "closed_tiles": ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "2p"],
            "melds": [],
            "context": {
                "win_type": "ron", "is_dealer": False, "round_wind": "E", "seat_wind": "S",
                "riichi": True, "ippatsu": False, "haitei": False, "houtei": False,
                "rinshan": False, "chankan": False
            },
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["shanten"] == 0
    wait = next(item for item in body["improving_tiles"] if item["tile"] == "2p")
    assert wait["remaining"] == 3
    assert wait["score"]["points"]["ron"] > 0


def test_analyze_fourteen_tiles_returns_discard_options():
    response = client.post(
        "/api/v1/discards/analyze",
        json={
            "closed_tiles": ["1m", "2m", "3m", "4m", "5m", "6m", "7m", "8m", "9m", "2p", "3p", "4p", "5p", "C"],
            "include_score_predictions": False,
        },
    )
    assert response.status_code == 200
    body = response.json()
    discard = next(item for item in body["discards"] if item["discard"] == "C")
    assert discard["shanten"] == 0
    assert {item["tile"] for item in discard["improving_tiles"]} == {"2p", "5p"}


def test_analyze_rejects_wrong_concealed_tile_count():
    response = client.post("/api/v1/tenpai/analyze", json={"closed_tiles": ["1m", "2m"]})
    assert response.status_code == 422


def test_discard_analysis_accepts_red_five():
    response = client.post(
        "/api/v1/discards/analyze",
        json={
            "closed_tiles": ["1m", "2m", "3m", "4m", "5mr", "6m", "7m", "8m", "9m", "2p", "3p", "4p", "5p", "C"],
            "include_score_predictions": False,
        },
    )
    assert response.status_code == 200
    assert any(item["discard"] == "5m" for item in response.json()["discards"])


def test_operations_do_not_switch_implicitly_by_tile_count():
    fourteen_tiles = ["1m", "2m", "3m", "4m", "5m", "6m", "7m", "8m", "9m", "2p", "3p", "4p", "5p", "C"]
    thirteen_tiles = fourteen_tiles[:-1]
    assert client.post("/api/v1/tenpai/analyze", json={"closed_tiles": fourteen_tiles}).status_code == 422
    assert client.post("/api/v1/discards/analyze", json={"closed_tiles": thirteen_tiles}).status_code == 422
