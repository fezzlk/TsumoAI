"""Tests for TrainingDataStore's real GCS-backed CRUD logic, using an
in-memory fake GCS client so no real bucket or network is touched."""

from __future__ import annotations

import json

import pytest

from app.training_data_store import TrainingDataStore


class _FakeBlob:
    def __init__(self, name: str, store: "_FakeGCS"):
        self.name = name
        self._store = store

    def upload_from_string(self, data, content_type: str) -> None:
        self._store.objects[self.name] = data if isinstance(data, bytes) else data.encode("utf-8")

    def exists(self) -> bool:
        return self.name in self._store.objects

    def download_as_text(self) -> str:
        return self._store.objects[self.name].decode("utf-8")

    def download_as_bytes(self) -> bytes:
        return self._store.objects[self.name]

    def delete(self) -> None:
        self._store.objects.pop(self.name, None)


class _FakeGCS:
    """Shared in-memory object store, plus the bucket/client wrappers the
    real google-cloud-storage API exposes."""

    def __init__(self):
        self.objects: dict[str, bytes] = {}

    def bucket(self, name: str) -> "_FakeBucket":
        return _FakeBucket(self)


class _FakeBucket:
    def __init__(self, store: _FakeGCS):
        self._store = store

    def blob(self, name: str) -> _FakeBlob:
        return _FakeBlob(name, self._store)

    def list_blobs(self, prefix: str):
        return [_FakeBlob(name, self._store) for name in sorted(self._store.objects) if name.startswith(prefix)]


class _FakeClient:
    def __init__(self, gcs: _FakeGCS, project=None):
        self._gcs = gcs

    def bucket(self, name: str):
        return self._gcs.bucket(name)


@pytest.fixture
def store(monkeypatch):
    gcs = _FakeGCS()
    monkeypatch.setattr("app.training_data_store.storage.Client", lambda project=None: _FakeClient(gcs, project))
    s = TrainingDataStore()
    s.bucket_name = "test-bucket"
    s._gcs = gcs  # expose for assertions
    return s


def test_bucket_raises_when_not_configured():
    s = TrainingDataStore()
    s.bucket_name = None
    with pytest.raises(ValueError, match="GCS bucket is not configured"):
        s._bucket()


def test_upload_writes_image_meta_and_index(store):
    result = store.upload(b"fake-jpeg-bytes", tile_code="1m", predicted_tile_code="2m")

    assert result["id"]
    assert result["image_path"] in store._gcs.objects
    meta_path = result["image_path"].replace("images/", "meta/").replace(".jpg", ".json")
    meta = json.loads(store._gcs.objects[meta_path].decode("utf-8"))
    assert meta["tile_code"] == "1m"
    assert meta["predicted_tile_code"] == "2m"
    assert meta["was_corrected"] is True

    index = json.loads(store._gcs.objects["training-data/index.json"].decode("utf-8"))
    assert len(index) == 1
    assert index[0]["id"] == result["id"]


def test_upload_without_prediction_omits_correction_fields(store):
    result = store.upload(b"bytes", tile_code="1m")
    meta_path = result["image_path"].replace("images/", "meta/").replace(".jpg", ".json")
    meta = json.loads(store._gcs.objects[meta_path].decode("utf-8"))
    assert "predicted_tile_code" not in meta
    assert "was_corrected" not in meta


def test_load_index_rebuilds_from_meta_when_index_missing(store):
    store._gcs.objects["training-data/meta/user/1m/a.json"] = json.dumps(
        {"id": "a", "tile_code": "1m"}
    ).encode("utf-8")
    store._gcs.objects["training-data/meta/user/2m/b.json"] = json.dumps(
        {"id": "b", "tile_code": "2m"}
    ).encode("utf-8")

    index = store._load_index()

    assert {e["id"] for e in index} == {"a", "b"}
    assert "training-data/index.json" in store._gcs.objects  # rebuild persists


def test_rebuild_index_skips_non_json_blobs_under_meta_prefix(store):
    store._gcs.objects["training-data/meta/user/1m/a.json"] = json.dumps(
        {"id": "a", "tile_code": "1m"}
    ).encode("utf-8")
    store._gcs.objects["training-data/meta/user/1m/a.jpg.tmp"] = b"stray non-json blob"

    index = store._load_index()
    assert [e["id"] for e in index] == ["a"]


def test_upload_still_writes_blobs_when_initial_index_load_fails(store, monkeypatch):
    monkeypatch.setattr(store, "_load_index", lambda **_: (_ for _ in ()).throw(RuntimeError("boom")))

    result = store.upload(b"bytes", tile_code="1m")

    assert result["image_path"] in store._gcs.objects
    assert "training-data/index.json" not in store._gcs.objects


def test_upload_logs_and_continues_when_save_index_fails(store, monkeypatch):
    store._save_index([])  # seed index.json so the pre-load below doesn't itself rebuild-and-save
    monkeypatch.setattr(store, "_save_index", lambda entries: (_ for _ in ()).throw(RuntimeError("boom")))

    result = store.upload(b"bytes", tile_code="1m")

    assert result["image_path"] in store._gcs.objects  # image/meta still written


def test_load_index_skips_unparseable_meta_files(store):
    store._gcs.objects["training-data/meta/user/1m/a.json"] = b"not json"
    store._gcs.objects["training-data/meta/user/2m/b.json"] = json.dumps(
        {"id": "b", "tile_code": "2m"}
    ).encode("utf-8")

    index = store._load_index()
    assert [e["id"] for e in index] == ["b"]


def test_load_index_uses_cache_within_ttl(store, monkeypatch):
    store._save_index([{"id": "cached"}])
    calls = {"n": 0}
    original_bucket = store._bucket

    def counting_bucket():
        calls["n"] += 1
        return original_bucket()

    monkeypatch.setattr(store, "_bucket", counting_bucket)
    store._load_index()
    store._load_index()
    assert calls["n"] == 0  # fully served from cache, no GCS call at all


def test_load_index_force_refresh_bypasses_cache(store):
    store._save_index([{"id": "first"}])
    store._gcs.objects["training-data/index.json"] = json.dumps([{"id": "second"}]).encode("utf-8")
    index = store._load_index(force=True)
    assert index == [{"id": "second"}]


def test_list_gcs_filters_by_tile_code_and_source(store):
    store._save_index(
        [
            {"id": "a", "tile_code": "1m", "source": "user"},
            {"id": "b", "tile_code": "1m", "source": "kaggle"},
            {"id": "c", "tile_code": "2m", "source": "user"},
        ]
    )
    assert [e["id"] for e in store._list_gcs(tile_code="1m")] == ["a", "b"]
    assert [e["id"] for e in store._list_gcs(source="user")] == ["a", "c"]
    assert [e["id"] for e in store._list_gcs(tile_code="1m", source="user")] == ["a"]


def test_list_entries_falls_back_to_local_when_gcs_fails(store, monkeypatch):
    monkeypatch.setattr(store, "_list_gcs", lambda **_: (_ for _ in ()).throw(RuntimeError("gcs down")))
    monkeypatch.setattr(store, "_list_local", lambda **_: [{"id": "local_x", "tile_code": "1m"}])
    entries = store.list_entries()
    assert entries == [{"id": "local_x", "tile_code": "1m"}]


def test_list_local_scans_source_and_tile_directories(tmp_path, monkeypatch):
    (tmp_path / "kaggle" / "1m").mkdir(parents=True)
    (tmp_path / "kaggle" / "1m" / "a.jpg").write_bytes(b"x")
    (tmp_path / "kaggle" / "2m").mkdir(parents=True)
    (tmp_path / "kaggle" / "2m" / "b.png").write_bytes(b"x")
    (tmp_path / "kaggle" / "not_a_dir.txt").write_text("ignored")

    monkeypatch.setattr("app.training_data_store.LOCAL_DATA_DIR", tmp_path)
    store = TrainingDataStore()

    entries = store._list_local()
    assert {e["tile_code"] for e in entries} == {"1m", "2m"}
    assert all(e["id"].startswith("local_kaggle_") for e in entries)

    filtered = store._list_local(tile_code="1m")
    assert [e["tile_code"] for e in filtered] == ["1m"]


def test_list_local_skips_stray_file_at_source_level(tmp_path, monkeypatch):
    (tmp_path / "README.txt").write_text("not a source directory")
    (tmp_path / "kaggle" / "1m").mkdir(parents=True)
    (tmp_path / "kaggle" / "1m" / "a.jpg").write_bytes(b"x")

    monkeypatch.setattr("app.training_data_store.LOCAL_DATA_DIR", tmp_path)
    store = TrainingDataStore()

    entries = store._list_local()
    assert len(entries) == 1
    assert entries[0]["source"] == "kaggle"


def test_list_local_filters_by_source(tmp_path, monkeypatch):
    (tmp_path / "kaggle" / "1m").mkdir(parents=True)
    (tmp_path / "kaggle" / "1m" / "a.jpg").write_bytes(b"x")
    (tmp_path / "other" / "1m").mkdir(parents=True)
    (tmp_path / "other" / "1m" / "b.jpg").write_bytes(b"x")

    monkeypatch.setattr("app.training_data_store.LOCAL_DATA_DIR", tmp_path)
    store = TrainingDataStore()

    filtered = store._list_local(source="kaggle")
    assert [e["source"] for e in filtered] == ["kaggle"]


def test_list_local_returns_empty_when_dir_missing(tmp_path, monkeypatch):
    monkeypatch.setattr("app.training_data_store.LOCAL_DATA_DIR", tmp_path / "does-not-exist")
    store = TrainingDataStore()
    assert store._list_local() == []


def test_get_image_returns_none_for_local_prefix_without_match(monkeypatch):
    monkeypatch.setattr(TrainingDataStore, "_list_local", lambda self, **_: [])
    store = TrainingDataStore()
    assert store.get_image("local_missing") is None


def test_get_local_image_reads_file_from_disk(tmp_path, monkeypatch):
    (tmp_path / "kaggle" / "1m").mkdir(parents=True)
    image_path = tmp_path / "kaggle" / "1m" / "a.jpg"
    image_path.write_bytes(b"jpeg-bytes")
    monkeypatch.setattr("app.training_data_store.LOCAL_DATA_DIR", tmp_path)
    store = TrainingDataStore()

    entries = store._list_local()
    entry_id = entries[0]["id"]
    assert store.get_image(entry_id) == b"jpeg-bytes"


def test_get_image_downloads_from_gcs_when_indexed(store):
    store._gcs.objects["training-data/images/user/2026/09/12/abc.jpg"] = b"gcs-bytes"
    store._save_index([{"id": "abc", "image_path": "training-data/images/user/2026/09/12/abc.jpg"}])
    assert store.get_image("abc") == b"gcs-bytes"


def test_get_image_returns_none_when_blob_missing(store):
    store._save_index([{"id": "abc", "image_path": "training-data/images/nope.jpg"}])
    assert store.get_image("abc") is None


def test_get_image_returns_none_when_id_not_in_index(store):
    store._save_index([{"id": "other"}])
    assert store.get_image("abc") is None


def test_get_image_returns_none_when_index_load_fails(store, monkeypatch):
    monkeypatch.setattr(store, "_load_index", lambda **_: (_ for _ in ()).throw(RuntimeError("boom")))
    assert store.get_image("abc") is None


def test_update_tile_code_rejects_local_entries():
    store = TrainingDataStore()
    assert store.update_tile_code("local_x", "1m") is False


def test_update_tile_code_returns_false_for_unknown_id(store):
    store._save_index([{"id": "other", "tile_code": "1m"}])
    assert store.update_tile_code("missing", "2m") is False


def test_update_tile_code_is_a_noop_when_unchanged(store):
    store._save_index([{"id": "a", "tile_code": "1m", "image_path": "training-data/images/x.jpg"}])
    assert store.update_tile_code("a", "1m") is True


def test_update_tile_code_updates_meta_blob_and_index(store):
    store._save_index(
        [{"id": "a", "tile_code": "1m", "image_path": "training-data/images/user/2026/09/12/a.jpg"}]
    )
    assert store.update_tile_code("a", "9s") is True

    meta = json.loads(store._gcs.objects["training-data/meta/user/2026/09/12/a.json"].decode("utf-8"))
    assert meta["tile_code"] == "9s"
    index = json.loads(store._gcs.objects["training-data/index.json"].decode("utf-8"))
    assert index[0]["tile_code"] == "9s"


def test_update_tile_code_skips_meta_write_when_image_path_unrecognized(store):
    store._save_index([{"id": "a", "tile_code": "1m", "image_path": "some/other/path.jpg"}])
    assert store.update_tile_code("a", "9s") is True  # only the index gets updated


def test_delete_entry_rejects_local_and_public_prefixes():
    store = TrainingDataStore()
    assert store.delete_entry("local_x") is False
    assert store.delete_entry("pub_x") is False


def test_delete_entry_removes_matching_blobs_and_index_entry(store):
    entry_id = "abc123"
    store._gcs.objects[f"training-data/images/user/2026/09/12/{entry_id}.jpg"] = b"img"
    store._gcs.objects[f"training-data/meta/user/2026/09/12/{entry_id}.json"] = b"{}"
    store._save_index([{"id": entry_id, "tile_code": "1m"}])

    assert store.delete_entry(entry_id) is True
    assert not any(entry_id in name for name in store._gcs.objects)
    index = json.loads(store._gcs.objects["training-data/index.json"].decode("utf-8"))
    assert index == []


def test_delete_entry_returns_false_when_nothing_matches(store):
    assert store.delete_entry("nonexistent") is False


def test_delete_entry_invalidates_cache_when_index_update_fails(store, monkeypatch):
    entry_id = "abc123"
    store._gcs.objects[f"training-data/images/user/{entry_id}.jpg"] = b"img"
    store._gcs_meta_cache = [{"id": "stale"}]
    store._cache_timestamp = __import__("time").monotonic()
    monkeypatch.setattr(store, "_load_index", lambda **_: (_ for _ in ()).throw(RuntimeError("boom")))

    assert store.delete_entry(entry_id) is True
    assert store._gcs_meta_cache is None


def test_delete_entry_returns_false_on_unexpected_error(store, monkeypatch):
    monkeypatch.setattr(store, "_bucket", lambda: (_ for _ in ()).throw(RuntimeError("boom")))
    assert store.delete_entry("abc123") is False


def test_invalidate_cache_clears_cached_index(store):
    store._save_index([{"id": "a"}])
    store.invalidate_cache()
    assert store._gcs_meta_cache is None
    assert store._cache_timestamp == 0.0


def test_get_daily_timeline_accumulates_counts_and_skips_missing_dates(store, monkeypatch):
    entries = [
        {"created_at": "2026-08-26T01:00:00+00:00"},
        {"created_at": "2026-08-26T02:00:00+00:00"},
        {"created_at": "2026-08-27T01:00:00+00:00"},
        {"created_at": ""},
    ]
    monkeypatch.setattr(store, "list_entries", lambda **_: entries)

    timeline = store.get_daily_timeline()

    assert timeline == [
        {"date": "2026-08-26", "count": 2, "cumulative_count": 2},
        {"date": "2026-08-27", "count": 1, "cumulative_count": 3},
    ]
