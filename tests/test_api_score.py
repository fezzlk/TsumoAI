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
            "ura_dora_indicators": [],
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
    assert body["result"]["han"] == 5
    assert body["result"]["points"]["ron"] == 8000


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


def test_score_endpoint_adds_ittsuu():
    payload = valid_payload()
    payload["hand"] = {
        "closed_tiles": ["1m", "2m", "3m", "4m", "5m", "6m", "7m", "8m", "9m", "2p", "2p", "2p", "5s", "5s"],
        "melds": [],
        "win_tile": "5s",
    }
    payload["context"]["round_wind"] = "W"
    payload["context"]["riichi"] = False
    payload["context"]["double_riichi"] = False
    payload["context"]["dora_indicators"] = []
    payload["context"]["aka_dora_count"] = 0
    response = client.post("/api/v1/score", json=payload)
    assert response.status_code == 200
    body = response.json()
    assert body["result"]["han"] == 2
    assert any(y["name"] == "一気通貫" and y["han"] == 2 for y in body["result"]["yaku"])


def test_score_endpoint_adds_toitoi_and_sanshoku_doukou():
    payload = valid_payload()
    payload["hand"] = {
        "closed_tiles": ["1p", "1p", "1p", "1s", "1s", "1s", "9m", "9m", "9m", "5p", "5p"],
        "melds": [{"type": "pon", "tiles": ["1m", "1m", "1m"], "open": True}],
        "win_tile": "5p",
    }
    payload["context"]["round_wind"] = "W"
    payload["context"]["riichi"] = False
    payload["context"]["double_riichi"] = False
    payload["context"]["dora_indicators"] = []
    payload["context"]["aka_dora_count"] = 0
    response = client.post("/api/v1/score", json=payload)
    assert response.status_code == 200
    body = response.json()
    assert body["result"]["han"] == 4
    assert any(y["name"] == "対々和" and y["han"] == 2 for y in body["result"]["yaku"])
    assert any(y["name"] == "三色同刻" and y["han"] == 2 for y in body["result"]["yaku"])


def test_score_endpoint_adds_chiitoitsu_and_honroutou():
    payload = valid_payload()
    payload["hand"] = {
        "closed_tiles": ["1m", "1m", "9m", "9m", "1p", "1p", "9p", "9p", "1s", "1s", "9s", "9s", "E", "E"],
        "melds": [],
        "win_tile": "E",
    }
    payload["context"]["round_wind"] = "W"
    payload["context"]["riichi"] = False
    payload["context"]["double_riichi"] = False
    payload["context"]["dora_indicators"] = []
    payload["context"]["aka_dora_count"] = 0
    response = client.post("/api/v1/score", json=payload)
    assert response.status_code == 200
    body = response.json()
    assert body["result"]["han"] == 4
    assert any(y["name"] == "七対子" and y["han"] == 2 for y in body["result"]["yaku"])
    assert any(y["name"] == "混老頭" and y["han"] == 2 for y in body["result"]["yaku"])


def test_score_endpoint_adds_kokushi():
    payload = valid_payload()
    payload["hand"] = {
        "closed_tiles": ["1m", "1m", "9m", "1p", "9p", "1s", "9s", "E", "S", "W", "N", "P", "F", "C"],
        "melds": [],
        "win_tile": "9m",
    }
    payload["context"]["round_wind"] = "W"
    payload["context"]["riichi"] = False
    payload["context"]["double_riichi"] = False
    payload["context"]["dora_indicators"] = []
    payload["context"]["aka_dora_count"] = 0
    response = client.post("/api/v1/score", json=payload)
    assert response.status_code == 200
    body = response.json()
    assert body["result"]["point_label"] == "役満"
    assert body["result"]["points"]["ron"] == 32000
    assert body["result"]["yakuman"] == ["国士無双"]


def test_score_endpoint_adds_kokushi_13_wait_double_yakuman():
    payload = valid_payload()
    payload["hand"] = {
        "closed_tiles": ["1m", "9m", "9m", "1p", "9p", "1s", "9s", "E", "S", "W", "N", "P", "F", "C"],
        "melds": [],
        "win_tile": "9m",
    }
    payload["context"]["round_wind"] = "W"
    payload["context"]["riichi"] = False
    payload["context"]["double_riichi"] = False
    payload["context"]["dora_indicators"] = []
    payload["context"]["aka_dora_count"] = 0
    payload["rules"]["double_yakuman_ari"] = True
    response = client.post("/api/v1/score", json=payload)
    assert response.status_code == 200
    body = response.json()
    assert body["result"]["point_label"] == "ダブル役満"
    assert body["result"]["points"]["ron"] == 64000
    assert body["result"]["yakuman"] == ["国士無双十三面待ち"]


def test_score_endpoint_adds_daisangen():
    payload = valid_payload()
    payload["hand"] = {
        "closed_tiles": ["P", "P", "P", "F", "F", "F", "C", "C", "C", "1m", "1m", "1m", "9p", "9p"],
        "melds": [],
        "win_tile": "9p",
    }
    payload["context"]["round_wind"] = "W"
    payload["context"]["riichi"] = False
    payload["context"]["double_riichi"] = False
    payload["context"]["dora_indicators"] = []
    payload["context"]["aka_dora_count"] = 0
    response = client.post("/api/v1/score", json=payload)
    assert response.status_code == 200
    body = response.json()
    assert "大三元" in body["result"]["yakuman"]
    assert "四暗刻" in body["result"]["yakuman"]
    assert body["result"]["point_label"] == "ダブル役満"


def test_score_endpoint_adds_chuuren():
    payload = valid_payload()
    payload["hand"] = {
        "closed_tiles": ["1m", "1m", "1m", "2m", "3m", "4m", "5m", "6m", "7m", "8m", "9m", "9m", "9m", "5m"],
        "melds": [],
        "win_tile": "5m",
    }
    payload["context"]["round_wind"] = "W"
    payload["context"]["riichi"] = False
    payload["context"]["double_riichi"] = False
    payload["context"]["dora_indicators"] = []
    payload["context"]["aka_dora_count"] = 0
    payload["rules"]["double_yakuman_ari"] = True
    response = client.post("/api/v1/score", json=payload)
    assert response.status_code == 200
    body = response.json()
    assert "純正九蓮宝燈" in body["result"]["yakuman"]
    assert body["result"]["point_label"] == "ダブル役満"


def test_score_endpoint_rejects_dora_only_hand():
    payload = valid_payload()
    payload["context"]["round_wind"] = "W"
    payload["context"]["riichi"] = False
    payload["context"]["double_riichi"] = False
    payload["context"]["dora_indicators"] = ["4m"]
    payload["context"]["aka_dora_count"] = 0
    response = client.post("/api/v1/score", json=payload)
    assert response.status_code == 422
    assert "No yaku" in response.text


def test_score_feedback_success(monkeypatch):
    def fake_save(payload):
        assert "score_request" in payload
        assert "score_response" in payload
        assert "comment" in payload
        assert isinstance(payload["score_response"]["score_id"], str)
        return {"bucket": "test-bucket", "object_name": "score-feedback/test.json"}

    monkeypatch.setattr(gcs_feedback_store, "save", fake_save)
    score_res = client.post("/api/v1/score", json=valid_payload())
    assert score_res.status_code == 200

    feedback_res = client.post(
        "/api/v1/score/feedback",
        json={
            "score_request": valid_payload(),
            "score_response": score_res.json(),
            "comment": "manual fix",
        },
    )
    assert feedback_res.status_code == 200
    body = feedback_res.json()
    assert body["status"] == "ok"
    assert body["storage"]["bucket"] == "test-bucket"


def test_score_feedback_accepts_comment_without_score(monkeypatch):
    def fake_save(payload):
        assert payload["score_request"] is None
        assert payload["score_response"] is None
        assert payload["comment"] == "manual comment only"
        return {"bucket": "test-bucket", "object_name": "score-feedback/comment-only.json"}

    monkeypatch.setattr(gcs_feedback_store, "save", fake_save)
    feedback_res = client.post(
        "/api/v1/score/feedback",
        json={
            "comment": "manual comment only",
        },
    )
    assert feedback_res.status_code == 200
    body = feedback_res.json()
    assert body["status"] == "ok"


def test_score_feedback_accepts_error_response_payload(monkeypatch):
    def fake_save(payload):
        assert payload["score_request"] is not None
        assert payload["score_response"]["detail"] == "No yaku: dora-only hands cannot win"
        return {"bucket": "test-bucket", "object_name": "score-feedback/error-response.json"}

    monkeypatch.setattr(gcs_feedback_store, "save", fake_save)
    payload = valid_payload()
    payload["context"]["round_wind"] = "W"
    payload["context"]["riichi"] = False
    payload["context"]["double_riichi"] = False
    payload["context"]["dora_indicators"] = ["4m"]
    payload["context"]["aka_dora_count"] = 0
    score_res = client.post("/api/v1/score", json=payload)
    assert score_res.status_code == 422

    feedback_res = client.post(
        "/api/v1/score/feedback",
        json={
            "score_request": payload,
            "score_response": score_res.json(),
            "comment": "役なし判定の確認依頼",
        },
    )
    assert feedback_res.status_code == 200
