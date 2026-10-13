from fastapi.testclient import TestClient
from app.main import app, history_store
from app.auth import get_current_user
from app.schemas import ContextInput

client = TestClient(app)
HAND = ["1p", "2p", "3p", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "2s", "2s"]


def context():
    return ContextInput(win_type="tsumo", is_dealer=False, round_wind="E", seat_wind="S", riichi=False,
                        ippatsu=False, haitei=False, houtei=False, rinshan=False, chankan=False).model_dump(mode="json")


def test_capabilities_and_score_use_three_players():
    assert client.get('/api/v1/capabilities').json()['mahjong_variants'] == ['yonma', 'sanma']
    response = client.post('/api/v1/score', json={
        'rules': {'variant': 'sanma'}, 'context': context(),
        'hand': {'closed_tiles': HAND, 'win_tile': '2s', 'extracted_tiles': ['N']},
    })
    assert response.status_code == 200
    result = response.json()['result']
    assert result['dora']['nuki_dora'] == 1
    assert result['payments']['hand_points_received'] == result['points']['tsumo_dealer_pay'] + result['points']['tsumo_non_dealer_pay']


def test_invalid_sanma_inputs_are_not_silently_scored_as_yonma():
    invalid = HAND.copy()
    invalid[:3] = ['1m', '2m', '3m']
    response = client.post('/api/v1/score', json={
        'rules': {'variant': 'sanma'}, 'context': context(),
        'hand': {'closed_tiles': invalid, 'win_tile': '2s'},
    })
    assert response.status_code == 422
    for route, tiles in [('tenpai', invalid[:-1]), ('discards', invalid), ('calls', invalid[:-1])]:
        response = client.post(f'/api/v1/{route}/analyze', json={'closed_tiles': tiles, 'rules': {'variant': 'sanma'}})
        assert response.status_code == 422


def test_history_sync_retains_variant_and_migrates_missing_variant(monkeypatch):
    stored = {}
    def save(uid, item_id, data):
        stored.update({**data, 'id': item_id, 'updated_at': '2026-10-13T00:00:00Z'})
        return stored
    monkeypatch.setattr(history_store, 'upsert', save)
    monkeypatch.setattr(history_store, 'list', lambda uid, limit: [stored])
    app.dependency_overrides[get_current_user] = lambda: {'uid': 'test-user'}
    try:
        item_id = 'f326bb37-6e89-46db-a95b-fb763ac8936a'
        payload = {'created_at': '2026-10-13T00:00:00Z', 'purpose': 'score', 'title': '点数', 'summary': '結果', 'variant': 'sanma'}
        assert client.put(f'/api/v1/history/{item_id}', json=payload).json()['variant'] == 'sanma'
        assert client.get('/api/v1/history').json()['items'][0]['variant'] == 'sanma'
        payload.pop('variant')
        assert client.put(f'/api/v1/history/{item_id}', json=payload).json()['variant'] == 'yonma'
    finally:
        app.dependency_overrides.clear()
