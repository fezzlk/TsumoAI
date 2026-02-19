from fastapi.testclient import TestClient

from app.main import app, gcs_feedback_store


client = TestClient(app)


def valid_payload() -> dict:
    return {
        "hand": {
            "closed_tiles": ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "2p", "2p"],
            "melds": [],
            "win_tile": "2p",
        },
        "context": {
            "win_type": "ron",
            "is_dealer": False,
            "round_wind": "E",
            "seat_wind": "S",
            "riichi": True,
            "double_riichi": False,
            "ippatsu": False,
            "haitei": False,
            "houtei": False,
            "rinshan": False,
            "chankan": False,
            "chiihou": False,
            "tenhou": False,
            "dora_indicators": ["4m"],
            "aka_dora_count": 2,
            "honba": 0,
            "kyotaku": 0,
        },
        "rules": {
            "aka_ari": True,
            "kuitan_ari": True,
            "double_yakuman_ari": True,
            "kazoe_yakuman_ari": True,
            "renpu_fu": 4,
        },
    }


def test_score_ui_available():
    response = client.get("/score-ui")
    assert response.status_code == 200
    assert "麻雀 点数算出モジュール" in response.text


def test_tile_image_available():
    response = client.get("/static/tiles/Mpu1m.png")
    assert response.status_code == 200
    assert response.headers["content-type"] == "image/png"


def test_score_ui_has_feedback_controls():
    response = client.get("/score-ui")
    assert response.status_code == 200
    assert "誤り指摘（GCS保存）" in response.text
    assert "和了形" in response.text
    assert "4面子1雀頭" in response.text


def test_score_endpoint_success():
    response = client.post("/api/v1/score", json=valid_payload())
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["result"]["han"] == 4
    assert body["result"]["points"]["ron"] == 7700


def test_score_endpoint_validation_error():
    payload = valid_payload()
    payload["hand"]["closed_tiles"] = payload["hand"]["closed_tiles"][:-1]
    response = client.post("/api/v1/score", json=payload)
    assert response.status_code == 422
    assert "14 + number of kans" in response.text


def test_score_endpoint_accepts_kan_hand():
    payload = valid_payload()
    payload["hand"] = {
        "closed_tiles": ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "2p", "2p"],
        "melds": [
            {
                "type": "kan",
                "tiles": ["E", "E", "E", "E"],
                "open": True,
            }
        ],
        "win_tile": "2p",
    }
    response = client.post("/api/v1/score", json=payload)
    assert response.status_code == 200


def test_score_endpoint_accepts_two_kans_hand():
    payload = valid_payload()
    payload["hand"] = {
        "closed_tiles": ["1m", "2m", "3m", "4p", "5p", "6p", "2p", "2p"],
        "melds": [
            {"type": "kan", "tiles": ["E", "E", "E", "E"], "open": True},
            {"type": "kan", "tiles": ["S", "S", "S", "S"], "open": True},
        ],
        "win_tile": "2p",
    }
    response = client.post("/api/v1/score", json=payload)
    assert response.status_code == 200


def test_score_endpoint_accepts_three_kans_hand():
    payload = valid_payload()
    payload["hand"] = {
        "closed_tiles": ["1m", "2m", "3m", "2p", "2p"],
        "melds": [
            {"type": "kan", "tiles": ["E", "E", "E", "E"], "open": True},
            {"type": "kan", "tiles": ["S", "S", "S", "S"], "open": True},
            {"type": "kan", "tiles": ["W", "W", "W", "W"], "open": True},
        ],
        "win_tile": "2p",
    }
    response = client.post("/api/v1/score", json=payload)
    assert response.status_code == 200


def test_score_endpoint_accepts_four_kans_hand():
    payload = valid_payload()
    payload["hand"] = {
        "closed_tiles": ["2p", "2p"],
        "melds": [
            {"type": "kan", "tiles": ["E", "E", "E", "E"], "open": True},
            {"type": "kan", "tiles": ["S", "S", "S", "S"], "open": True},
            {"type": "kan", "tiles": ["W", "W", "W", "W"], "open": True},
            {"type": "kan", "tiles": ["N", "N", "N", "N"], "open": True},
        ],
        "win_tile": "2p",
    }
    response = client.post("/api/v1/score", json=payload)
    assert response.status_code == 200


def test_score_endpoint_rejects_non_winning_shape():
    payload = valid_payload()
    payload["hand"]["closed_tiles"] = ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "5mr", "5pr"]
    payload["hand"]["win_tile"] = "5pr"
    response = client.post("/api/v1/score", json=payload)
    assert response.status_code == 422
    assert "valid winning shape" in response.text


def test_score_feedback_success(monkeypatch):
    def fake_save(payload):
        assert "score_request" in payload
        assert "score_response" in payload
        assert "corrected_result" in payload
        return {"bucket": "test-bucket", "object_name": "score-feedback/test.json"}

    monkeypatch.setattr(gcs_feedback_store, "save", fake_save)
    score_res = client.post("/api/v1/score", json=valid_payload())
    assert score_res.status_code == 200

    feedback_res = client.post(
        "/api/v1/score/feedback",
        json={
            "score_request": valid_payload(),
            "score_response": score_res.json(),
            "corrected_result": {"han": 5, "point_label": "満貫"},
            "comment": "manual fix",
            "reporter": "tester",
        },
    )
    assert feedback_res.status_code == 200
    body = feedback_res.json()
    assert body["status"] == "ok"
    assert body["storage"]["bucket"] == "test-bucket"
