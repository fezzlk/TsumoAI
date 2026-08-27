from app.training_data_store import TrainingDataStore


def test_stats_calculate_correction_based_recognition_accuracy(monkeypatch):
    store = TrainingDataStore()
    entries = [
        {
            "tile_code": "1m",
            "predicted_tile_code": "1m",
            "source": "user",
            "created_at": "2026-08-26T01:00:00+00:00",
        },
        {
            "tile_code": "1m",
            "predicted_tile_code": "2m",
            "source": "user",
            "created_at": "2026-08-26T02:00:00+00:00",
        },
        {
            "tile_code": "2m",
            "predicted_tile_code": "2m",
            "source": "user",
            "created_at": "2026-08-27T01:00:00+00:00",
        },
        {"tile_code": "3m", "source": "kaggle", "created_at": ""},
    ]
    monkeypatch.setattr(store, "list_entries", lambda **_: entries)

    stats = store.get_stats()
    accuracy = stats["recognition_accuracy"]

    assert accuracy["total"] == 3
    assert accuracy["correct"] == 2
    assert accuracy["corrected"] == 1
    assert accuracy["accuracy"] == 2 / 3
    assert accuracy["by_actual_tile"]["1m"] == {"total": 2, "correct": 1}
    assert accuracy["by_day"]["2026-08-26"] == {"total": 2, "correct": 1}
    assert accuracy["top_confusions"] == [
        {"predicted": "2m", "actual": "1m", "count": 1}
    ]


def test_stats_ignore_legacy_entries_without_prediction(monkeypatch):
    store = TrainingDataStore()
    monkeypatch.setattr(
        store,
        "list_entries",
        lambda **_: [{"tile_code": "1m", "source": "user", "created_at": ""}],
    )

    accuracy = store.get_stats()["recognition_accuracy"]

    assert accuracy["total"] == 0
    assert accuracy["accuracy"] is None
