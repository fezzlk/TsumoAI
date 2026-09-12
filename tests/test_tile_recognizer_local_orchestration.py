"""Tests for the recognize_tiles_local orchestration (model loading, per-tile
classification loop, confidence gating). These use a fake TFLite interpreter
injected directly into the module's global state, so no real tflite_runtime
or tensorflow install is required and no API cost is incurred -- the real
segmentation pipeline (on a real eval photo) still runs unmodified."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest

import app.tile_recognizer_local as trl

BASE_DIR = Path(__file__).resolve().parents[1]
CASE_001_IMAGE = BASE_DIR / "data" / "eval_images_cropped" / "case-001.jpg"


@pytest.fixture(autouse=True)
def _reset_module_globals():
    """The interpreter/labels are cached as module globals; snapshot and
    restore them so tests never leak fake state into each other."""
    saved_interpreter = trl._interpreter
    saved_labels = list(trl._labels)
    yield
    trl._interpreter = saved_interpreter
    trl._labels = saved_labels


class _FakeInterpreter:
    """Duck-types the subset of the tflite.Interpreter API this module uses.
    `next_label_index` controls what `_classify_tile` will decode next."""

    def __init__(self, num_labels: int):
        self.next_label_index = 0
        self.next_confidence = 0.95
        self._num_labels = num_labels

    def get_input_details(self):
        return [{"shape": [1, 224, 224, 3], "index": 0}]

    def get_output_details(self):
        return [{"index": 0}]

    def set_tensor(self, index, data):
        pass

    def invoke(self):
        pass

    def get_tensor(self, index):
        output = np.zeros(self._num_labels, dtype=np.float32)
        output[self.next_label_index] = self.next_confidence
        return np.array([output])


def test_load_model_raises_when_tflite_file_missing(monkeypatch):
    trl._interpreter = None
    monkeypatch.setattr(trl, "_TFLITE_PATH", BASE_DIR / "does" / "not" / "exist.tflite")
    with pytest.raises(FileNotFoundError):
        trl._load_model()


def test_classify_tile_maps_argmax_output_to_label_and_confidence():
    fake = _FakeInterpreter(num_labels=3)
    fake.next_label_index = 1
    fake.next_confidence = 0.83
    trl._interpreter = fake
    trl._labels = ["dots-1", "dots-2", "dots-3"]

    label, confidence = trl._classify_tile(np.zeros((50, 50, 3), dtype=np.uint8))

    assert label == "dots-2"
    assert confidence == pytest.approx(0.83)


def test_classify_tile_returns_unknown_for_out_of_range_index():
    fake = _FakeInterpreter(num_labels=3)
    fake.next_label_index = 2
    trl._interpreter = fake
    trl._labels = []  # no labels loaded -> idx is always out of range

    label, _confidence = trl._classify_tile(np.zeros((50, 50, 3), dtype=np.uint8))
    assert label == "unknown"


def test_recognize_tiles_local_returns_none_when_model_unavailable():
    """On this dev machine neither tflite_runtime nor tensorflow is
    installed, so the real _load_model() call genuinely fails -- this
    exercises the real fallback path, not a mock."""
    trl._interpreter = None
    result = trl.recognize_tiles_local(b"irrelevant, load_model fails first")
    assert result is None


def test_recognize_tiles_local_returns_none_on_unreadable_image(monkeypatch):
    trl._interpreter = _FakeInterpreter(num_labels=34)
    trl._labels = list(trl._LABEL_TO_TILE.keys())
    result = trl.recognize_tiles_local(b"not a real image")
    assert result is None


def test_recognize_tiles_local_end_to_end_on_real_photo_with_fake_classifier():
    if not CASE_001_IMAGE.exists():
        pytest.skip("eval fixture not present in this environment")

    labels = list(trl._LABEL_TO_TILE.keys())
    fake = _FakeInterpreter(num_labels=len(labels))
    fake.next_label_index = labels.index("characters-1")
    fake.next_confidence = 0.9
    trl._interpreter = fake
    trl._labels = labels

    result = trl.recognize_tiles_local(CASE_001_IMAGE.read_bytes())

    assert result is not None
    assert result["model_name"] == "tflite-mobilenetv2"
    assert result["tiles_count"] in (13, 14)
    assert len(result["slots"]) == result["tiles_count"]
    for i, slot in enumerate(result["slots"]):
        assert slot["index"] == i
        assert slot["top"] == "1m"
        assert slot["ambiguous"] is False
        assert "bbox" in slot and "observation_id" in slot


def test_recognize_tiles_local_returns_none_when_average_confidence_too_low():
    if not CASE_001_IMAGE.exists():
        pytest.skip("eval fixture not present in this environment")

    labels = list(trl._LABEL_TO_TILE.keys())
    fake = _FakeInterpreter(num_labels=len(labels))
    fake.next_label_index = labels.index("characters-1")
    fake.next_confidence = 0.1  # below the 0.5 average-confidence gate
    trl._interpreter = fake
    trl._labels = labels

    result = trl.recognize_tiles_local(CASE_001_IMAGE.read_bytes())
    assert result is None


def test_recognize_tiles_local_returns_none_when_segmentation_finds_wrong_tile_count():
    """A blank image has no tile-like blobs at all -> segmentation finds 0, not 13/14."""
    import io

    from PIL import Image

    trl._interpreter = _FakeInterpreter(num_labels=34)
    trl._labels = list(trl._LABEL_TO_TILE.keys())

    buf = io.BytesIO()
    Image.new("RGB", (200, 100), color=(20, 90, 40)).save(buf, format="JPEG")

    result = trl.recognize_tiles_local(buf.getvalue())
    assert result is None


def test_recognize_tiles_local_returns_none_when_labels_dont_map_to_valid_count():
    if not CASE_001_IMAGE.exists():
        pytest.skip("eval fixture not present in this environment")

    fake = _FakeInterpreter(num_labels=1)
    trl._interpreter = fake
    trl._labels = ["unmapped-label"]  # not present in _LABEL_TO_TILE -> every slot dropped

    result = trl.recognize_tiles_local(CASE_001_IMAGE.read_bytes())
    assert result is None
