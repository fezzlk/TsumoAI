from app.tile_weighting import TILE34, build_tile_weight_model, tile_reliability_weight, tile_similarity


def test_tile_weight_model_builds_for_34_tiles():
    model = build_tile_weight_model()
    assert len(model.reliability) == 34
    assert set(model.reliability.keys()) == set(TILE34)


def test_tile_reliability_weight_range():
    for tile in TILE34:
        w = tile_reliability_weight(tile)
        assert 0.85 <= w <= 1.15


def test_tile_similarity_range_and_identity():
    assert tile_similarity("1m", "1m") == 1.0
    sim = tile_similarity("1m", "2m")
    assert 0.0 <= sim <= 1.0
