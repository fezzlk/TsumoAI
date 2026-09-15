"""Exercise the deployed Linux ABI and actual model, not a fake interpreter."""

import sys

import numpy as np
import pytest

from app import tile_recognizer_local as recognizer


@pytest.mark.skipif(sys.platform != "linux", reason="Production TFLite wheels target Linux")
def test_shipped_model_loads_and_runs_on_linux(monkeypatch):
    monkeypatch.setattr(recognizer, "_interpreter", None)
    monkeypatch.setattr(recognizer, "_labels", [])

    label, confidence = recognizer._classify_tile(np.zeros((224, 224, 3), dtype=np.uint8))

    assert label in recognizer._labels
    assert np.isfinite(confidence)
    assert 0 <= confidence <= 1
