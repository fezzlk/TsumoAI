"""Recognition boundary regressions using only synthetic images and fake models."""

from __future__ import annotations

import asyncio
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from io import BytesIO
from threading import Event
from types import ModuleType, SimpleNamespace
from uuid import uuid4

import httpx
import numpy as np
import pytest
from fastapi import UploadFile
from PIL import Image, ImageOps

from app import main
from app import tile_recognizer_local as recognizer


def _image_bytes(orientation: int = 1) -> bytes:
    image = Image.new("RGB", (80, 40), "white")
    image.paste("red", (0, 0, 40, 20))
    image.paste("blue", (40, 20, 80, 40))
    exif = Image.Exif()
    exif[274] = orientation
    output = BytesIO()
    image.save(output, "JPEG", quality=95, exif=exif)
    return output.getvalue()


def _estimate() -> dict:
    tiles = ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "2p", "2p"]
    return {
        "tiles_count": len(tiles),
        "slots": [
            {"index": index, "top": tile, "candidates": [{"tile": tile, "confidence": 0.9}], "ambiguous": False}
            for index, tile in enumerate(tiles)
        ],
        "warnings": [],
    }


@pytest.fixture(autouse=True)
def _isolate_state(monkeypatch):
    main._recognition_rate_windows.clear()
    monkeypatch.setattr(recognizer, "_interpreter", None)
    monkeypatch.setattr(recognizer, "_labels", [])
    yield
    main._recognition_rate_windows.clear()


@pytest.mark.parametrize(
    "route,stage",
    [
        (route, stage)
        for route in ("recognize", "recognize-only", "recognize-and-score")
        for stage in ("conversion", "extraction")
    ] + [("recognize-only/jobs", "conversion"), ("recognize-and-score", "interpretation")],
)
def test_health_remains_responsive_during_recognition(monkeypatch, route, stage):
    """A health request must complete while recognition work is still blocked."""
    started, finished, release = Event(), Event(), Event()
    original_convert = main._to_recognition_image_bytes
    original_interpret = main.hand_shape_from_estimate_with_warnings

    def block():
        started.set()
        release.wait(timeout=2)
        finished.set()

    def convert(*args):
        if stage == "conversion":
            block()
        return original_convert(*args)

    def extract(_image_bytes):
        if stage == "extraction":
            block()
        return _estimate()

    def interpret(estimate):
        if stage == "interpretation":
            block()
        return original_interpret(estimate)

    monkeypatch.setattr(main, "_to_recognition_image_bytes", convert)
    monkeypatch.setattr(main, "extract_hand_from_image", extract)
    monkeypatch.setattr(main, "hand_shape_from_estimate_with_warnings", interpret)
    monkeypatch.setattr(main.recognition_jobs, "create_job", lambda **kwargs: SimpleNamespace(
        id=uuid4(), status="pending", cancel_requested=False,
    ))

    async def run():
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=main.app), base_url="http://test") as client:
            request = asyncio.create_task(client.post(
                f"/api/v1/{route}",
                files={"image": ("hand.jpg", _image_bytes(), "image/jpeg")},
                data={
                    "context_json": json.dumps({
                        "win_type": "ron", "is_dealer": False, "round_wind": "E", "seat_wind": "S",
                        "riichi": False, "ippatsu": False, "haitei": False, "houtei": False,
                        "rinshan": False, "chankan": False,
                    }),
                    "rules_json": "{}",
                },
            ))
            try:
                async def wait_until_started():
                    while not started.is_set():
                        await asyncio.sleep(0.005)

                await asyncio.wait_for(wait_until_started(), timeout=3)
                health = await asyncio.wait_for(client.get("/health"), timeout=1)
                assert health.status_code == 200
                assert not finished.is_set(), "recognition blocked the event loop until it finished"
            finally:
                release.set()
                response = await request
            assert response.status_code == 200, response.text

    asyncio.run(run())


@pytest.mark.parametrize("orientation", range(1, 9))
def test_conversion_applies_exif_orientation_to_pixels_and_dimensions(orientation):
    source = _image_bytes(orientation)
    upload = UploadFile(filename="hand.jpg", file=BytesIO(source))
    width, height, converted = main._to_recognition_image_bytes(upload, source)

    with Image.open(BytesIO(source)) as original:
        expected = ImageOps.exif_transpose(original).convert("RGB")
    with Image.open(BytesIO(converted)) as actual:
        assert (width, height) == expected.size == actual.size
        assert actual.getexif().get(274) in (None, 1)
        pixel_error = np.abs(np.asarray(actual, dtype=float) - np.asarray(expected, dtype=float))
        assert pixel_error.mean() < 5


@pytest.mark.parametrize("route", ["recognize", "recognize-only", "recognize-only/jobs"])
def test_recognition_routes_keep_dimensions_and_bboxes_in_oriented_coordinates(monkeypatch, route):
    seen = {}
    monkeypatch.setattr(recognizer, "_load_model", lambda: None)
    monkeypatch.setattr(recognizer, "_classify_tile", lambda image: ("characters-1", 0.9))

    def segment(rgb):
        seen["shape"] = rgb.shape
        height, width, _ = rgb.shape
        return [(0, height, 0, width)] * 13

    monkeypatch.setattr(recognizer, "_segment_tile_boxes", segment)
    monkeypatch.setattr(main, "extract_hand_from_image", recognizer.recognize_tiles_local)

    def create_job(**kwargs):
        seen["job"] = kwargs
        seen["payload"] = recognizer.recognize_tiles_local(kwargs["image_bytes"])
        return SimpleNamespace(id=uuid4(), status="pending", cancel_requested=False)

    monkeypatch.setattr(main.recognition_jobs, "create_job", create_job)

    async def run():
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=main.app), base_url="http://test") as client:
            response = await client.post(
                f"/api/v1/{route}", files={"image": ("hand.jpg", _image_bytes(6), "image/jpeg")},
            )
        assert response.status_code == 200, response.text
        assert seen["shape"] == (80, 40, 3)
        if route.endswith("jobs"):
            dimensions = seen["job"]
            estimate = seen["payload"]
        else:
            dimensions = response.json()["image"]
            estimate = response.json()["hand_estimate"]
        assert (dimensions["width"], dimensions["height"]) == (40, 80)
        assert estimate["slots"][0]["bbox"] == {"left": 0, "top": 0, "right": 40, "bottom": 80}

    asyncio.run(run())


def _fake_runtime(monkeypatch, tmp_path, factory):
    model = tmp_path / "model.tflite"
    labels = tmp_path / "labels.txt"
    model.write_bytes(b"test model")
    labels.write_text("dark\nlight\n")
    monkeypatch.setattr(recognizer, "_TFLITE_PATH", model)
    monkeypatch.setattr(recognizer, "_LABELS_PATH", labels)
    runtime = ModuleType("tflite_runtime")
    runtime.interpreter = ModuleType("tflite_runtime.interpreter")
    runtime.interpreter.Interpreter = factory
    monkeypatch.setitem(sys.modules, "tflite_runtime", runtime)
    monkeypatch.setitem(sys.modules, "tflite_runtime.interpreter", runtime.interpreter)


def test_parallel_load_waits_for_complete_initialization(monkeypatch, tmp_path):
    allocating, release, second_entered, second_finished = Event(), Event(), Event(), Event()
    created = []

    class Interpreter:
        def __init__(self, **kwargs):
            created.append(self)
            self.ready = False

        def allocate_tensors(self):
            allocating.set()
            assert release.wait(timeout=3)
            self.ready = True

    _fake_runtime(monkeypatch, tmp_path, Interpreter)

    def second_load():
        second_entered.set()
        recognizer._load_model()
        second_finished.set()
        assert recognizer._interpreter.ready
        assert recognizer._labels == ["dark", "light"]

    with ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(recognizer._load_model)
        try:
            assert allocating.wait(timeout=2)
            second = pool.submit(second_load)
            assert second_entered.wait(timeout=2)
            assert not second_finished.wait(timeout=0.1), "load returned with an uninitialized interpreter"
            assert recognizer._interpreter is None, "interpreter was published before allocation completed"
        finally:
            release.set()
        first.result(timeout=2)
        second.result(timeout=2)
    assert len(created) == 1


@pytest.mark.parametrize("failure_stage", ["allocation", "labels"])
def test_failed_initialization_leaves_no_cached_interpreter_and_can_retry(monkeypatch, tmp_path, failure_stage):
    created = []

    class Interpreter:
        def __init__(self, **kwargs):
            created.append(self)

        def allocate_tensors(self):
            if failure_stage == "allocation" and len(created) == 1:
                raise RuntimeError("allocation failed")

    _fake_runtime(monkeypatch, tmp_path, Interpreter)
    real_labels = recognizer._LABELS_PATH
    if failure_stage == "labels":
        monkeypatch.setattr(recognizer, "_LABELS_PATH", SimpleNamespace(
            exists=lambda: True,
            read_text=lambda: (_ for _ in ()).throw(OSError("label read failed")),
        ))

    with pytest.raises((RuntimeError, OSError)):
        recognizer._load_model()
    assert recognizer._interpreter is None
    assert recognizer._labels == []
    monkeypatch.setattr(recognizer, "_LABELS_PATH", real_labels)
    recognizer._load_model()
    assert recognizer._interpreter is created[1]
    assert recognizer._labels == ["dark", "light"]


def test_parallel_classification_does_not_mix_inputs_or_outputs(monkeypatch):
    first_invoking, release, second_entered, overwritten = Event(), Event(), Event(), Event()

    class Interpreter:
        def get_input_details(self):
            return [{"shape": [1, 8, 8, 3], "index": 0}]

        def get_output_details(self):
            return [{"index": 1}]

        def set_tensor(self, index, data):
            if first_invoking.is_set() and not release.is_set():
                overwritten.set()
            self.label_index = int(data.mean() > 0)

        def invoke(self):
            if not first_invoking.is_set():
                first_invoking.set()
                assert release.wait(timeout=3)

        def get_tensor(self, index):
            output = np.zeros((1, 2), dtype=np.float32)
            output[0, self.label_index] = 0.9
            return output

    monkeypatch.setattr(recognizer, "_interpreter", Interpreter())
    monkeypatch.setattr(recognizer, "_labels", ["dark", "light"])

    def classify_light():
        second_entered.set()
        return recognizer._classify_tile(np.full((8, 8, 3), 255, dtype=np.uint8))

    with ThreadPoolExecutor(max_workers=2) as pool:
        dark = pool.submit(recognizer._classify_tile, np.zeros((8, 8, 3), dtype=np.uint8))
        try:
            assert first_invoking.wait(timeout=2)
            light = pool.submit(classify_light)
            assert second_entered.wait(timeout=2)
            assert not overwritten.wait(timeout=0.1), "another request overwrote an in-flight input"
        finally:
            release.set()
        assert dark.result(timeout=2)[0] == "dark"
        assert light.result(timeout=2)[0] == "light"
