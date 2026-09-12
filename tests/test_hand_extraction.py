import json

import pytest
from PIL import Image

from app.hand_extraction import (
    RecognitionCancelledError,
    _call_model_for_slots,
    _coerce_slots,
    _fallback_result,
    _image_variants,
    _jpeg_bytes,
    _merge_slot_estimates,
    _normalize_candidates,
    _parse_payload,
    _slot_options,
    extract_hand_from_image,
    hand_shape_from_estimate_with_warnings,
)


def _tiny_jpeg_bytes() -> bytes:
    from io import BytesIO

    buf = BytesIO()
    Image.new("RGB", (16, 16), color="white").save(buf, format="JPEG")
    return buf.getvalue()


class _FakeResponsesOutput:
    def __init__(self, output_text: str | Exception):
        self._output_text = output_text

    def create(self, **kwargs):
        if isinstance(self._output_text, Exception):
            raise self._output_text
        response = type("Response", (), {"output_text": self._output_text})()
        return response


class _FakeChatCompletions:
    def __init__(self, content: str | Exception):
        self._content = content

    def create(self, **kwargs):
        if isinstance(self._content, Exception):
            raise self._content
        message = type("Message", (), {"content": self._content})()
        choice = type("Choice", (), {"message": message})()
        return type("Response", (), {"choices": [choice]})()


class _FakeOpenAIResponsesClient:
    """Fake client exposing the newer `responses.create` surface."""

    def __init__(self, output_text: str | Exception):
        self.responses = _FakeResponsesOutput(output_text)


class _FakeOpenAIChatClient:
    """Fake client exposing only the legacy `chat.completions.create` surface."""

    def __init__(self, content: str | Exception):
        self.chat = type("Chat", (), {"completions": _FakeChatCompletions(content)})()


def _slots_from_tiles(tiles: list[str]) -> list[dict]:
    return [
        {
            "index": idx,
            "top": tile,
            "candidates": [{"tile": tile, "confidence": 0.9}],
            "ambiguous": False,
        }
        for idx, tile in enumerate(tiles)
    ]


def test_hand_shape_from_estimate_returns_top_when_already_winning():
    tiles = ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "2p", "2p"]
    hand, warnings = hand_shape_from_estimate_with_warnings({"slots": _slots_from_tiles(tiles)})
    assert hand.closed_tiles == tiles
    assert hand.win_tile == "2p"
    assert warnings == []


def test_hand_shape_from_estimate_uses_candidates_to_make_winning_shape():
    top_tiles = ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "5mr", "5pr"]
    slots = _slots_from_tiles(top_tiles)
    slots[12]["candidates"].append({"tile": "2p", "confidence": 0.8})
    slots[13]["candidates"].append({"tile": "2p", "confidence": 0.8})
    slots[12]["ambiguous"] = True
    slots[13]["ambiguous"] = True

    hand, warnings = hand_shape_from_estimate_with_warnings({"slots": slots})
    assert hand.closed_tiles[-2:] == ["2p", "2p"]
    assert any("adjusted from top-1" in warning for warning in warnings)


def test_normalize_candidates_accepts_slots_as_stringified_json_objects():
    raw_slots = [
        '{"index":0,"top":"1m","candidates":[{"tile":"1m","confidence":0.9}],"ambiguous":false}',
        '{"index":1,"top":"2m","candidates":["2m"],"ambiguous":true}',
    ]
    slots = _normalize_candidates(raw_slots)
    assert slots[0]["top"] == "1m"
    assert slots[1]["top"] == "2m"
    assert slots[1]["candidates"][0]["tile"] == "2m"


def test_normalize_candidates_accepts_slots_dict():
    raw_slots = {
        "0": {"index": 0, "top": "1m", "candidates": [{"tile": "1m", "confidence": 0.9}], "ambiguous": False},
        "1": {"index": 1, "top": "2m", "candidates": [{"tile": "2m", "confidence": 0.8}], "ambiguous": True},
    }
    slots = _normalize_candidates(raw_slots)
    assert len(slots) == 2
    assert slots[0]["index"] == 0
    assert slots[1]["index"] == 1


def test_merge_slot_estimates_prefers_consensus_tile():
    slots_a = [
        {"index": 0, "top": "4s", "candidates": [{"tile": "4s", "confidence": 0.9}], "ambiguous": False},
        {"index": 1, "top": "5s", "candidates": [{"tile": "5s", "confidence": 0.9}], "ambiguous": False},
    ]
    slots_b = [
        {"index": 0, "top": "4s", "candidates": [{"tile": "4s", "confidence": 0.8}], "ambiguous": True},
        {"index": 1, "top": "5s", "candidates": [{"tile": "5s", "confidence": 0.8}], "ambiguous": False},
    ]
    slots_c = [
        {"index": 0, "top": "1p", "candidates": [{"tile": "1p", "confidence": 0.9}], "ambiguous": False},
        {"index": 1, "top": "2p", "candidates": [{"tile": "2p", "confidence": 0.9}], "ambiguous": False},
    ]
    merged = _merge_slot_estimates([(slots_a, 1.0), (slots_b, 0.95), (slots_c, 0.7)])
    assert merged[0]["top"] == "4s"
    assert merged[1]["top"] == "5s"
    assert merged[0]["ambiguous"] is True


def test_normalize_candidates_uses_candidate_when_top_is_invalid():
    raw_slots = [
        {"index": 0, "top": "", "candidates": [{"tile": "1m", "confidence": 0.8}], "ambiguous": True},
        {"index": 1, "top": "2m", "candidates": [], "ambiguous": False},
    ]
    slots = _normalize_candidates(raw_slots)
    assert slots[0]["top"] == "1m"
    assert slots[1]["top"] == "2m"


def test_fallback_result_can_omit_missing_api_key_warning():
    result = _fallback_result(extra_warnings=["x"], include_missing_api_key_warning=False)
    assert "OPENAI_API_KEY is not set; fallback result is used." not in result["warnings"]
    assert "x" in result["warnings"]


def test_slot_options_allows_candidate_to_beat_low_confidence_top():
    slot = {
        "index": 0,
        "top": "1p",
        "top_confidence": 0.1,
        "candidates": [
            {"tile": "1p", "confidence": 0.1},
            {"tile": "4s", "confidence": 0.9},
        ],
        "ambiguous": True,
    }
    ranked = sorted(_slot_options(slot), key=lambda x: x["confidence"], reverse=True)
    assert ranked[0]["tile"] == "4s"


def test_fallback_result_includes_missing_api_key_warning_by_default():
    result = _fallback_result()
    assert "OPENAI_API_KEY is not set; fallback result is used." in result["warnings"]


def test_coerce_slots_parses_json_string():
    assert _coerce_slots('[{"index": 0, "top": "1m"}]') == [{"index": 0, "top": "1m"}]


def test_coerce_slots_rejects_unsupported_type():
    with pytest.raises(ValueError):
        _coerce_slots(123)


def test_normalize_candidates_wraps_single_candidate_dict():
    raw_slots = [{"index": 0, "top": "1m", "candidates": {"tile": "1m", "confidence": 0.9}, "ambiguous": False}]
    slots = _normalize_candidates(raw_slots)
    assert slots[0]["candidates"] == [{"tile": "1m", "confidence": 0.9}]


def test_normalize_candidates_skips_slot_with_no_valid_top_or_candidates():
    raw_slots = [
        {"index": 0, "top": "", "candidates": [{"tile": "not-a-tile", "confidence": 0.9}], "ambiguous": True},
        {"index": 1, "top": "2m", "candidates": [], "ambiguous": False},
    ]
    slots = _normalize_candidates(raw_slots)
    assert [slot["index"] for slot in slots] == [1]


def test_hand_shape_from_estimate_rejects_empty_slots():
    with pytest.raises(ValueError):
        hand_shape_from_estimate_with_warnings({"slots": []})


def test_parse_payload_strips_markdown_code_fence():
    assert _parse_payload('```json\n{"tiles_count": 14}\n```') == {"tiles_count": 14}


def test_parse_payload_extracts_json_object_from_surrounding_text():
    assert _parse_payload('Here you go: {"tiles_count": 14} -- done') == {"tiles_count": 14}


def test_parse_payload_raises_on_unparseable_text():
    with pytest.raises(json.JSONDecodeError):
        _parse_payload("not json at all")


def test_parse_payload_rejects_non_object_json():
    with pytest.raises(ValueError):
        _parse_payload("[1, 2, 3]")


def test_jpeg_bytes_produces_valid_jpeg():
    image = Image.new("RGB", (8, 8), color="red")
    data = _jpeg_bytes(image)
    assert data[:2] == b"\xff\xd8"  # JPEG magic bytes


def test_image_variants_produces_three_weighted_variants():
    variants = _image_variants(_tiny_jpeg_bytes())
    assert [name for name, _, _ in variants] == ["orig", "autocontrast", "contrast_sharp"]
    assert [weight for _, _, weight in variants] == [1.0, 0.95, 0.9]
    for _, data, _ in variants:
        assert data[:2] == b"\xff\xd8"


def test_call_model_for_slots_uses_responses_api_when_available():
    client = _FakeOpenAIResponsesClient('{"tiles_count": 14, "slots": []}')
    payload = _call_model_for_slots(client, _tiny_jpeg_bytes())
    assert payload == {"tiles_count": 14, "slots": []}


def test_call_model_for_slots_falls_back_to_chat_completions():
    client = _FakeOpenAIChatClient('{"tiles_count": 14, "slots": []}')
    assert not hasattr(client, "responses")
    payload = _call_model_for_slots(client, _tiny_jpeg_bytes())
    assert payload == {"tiles_count": 14, "slots": []}


def _mock_no_local_recognizer(monkeypatch):
    monkeypatch.setattr("app.tile_recognizer_local.recognize_tiles_local", lambda image_bytes: None)


def test_extract_hand_prefers_local_recognizer_and_skips_api(monkeypatch):
    local_result = {"tiles_count": 14, "slots": [], "warnings": []}
    monkeypatch.setattr("app.tile_recognizer_local.recognize_tiles_local", lambda image_bytes: local_result)

    def fail_if_called(*args, **kwargs):
        raise AssertionError("OpenAI client must not be constructed when local recognizer succeeds")

    monkeypatch.setattr("app.hand_extraction.OpenAI", fail_if_called)
    monkeypatch.setattr("app.hand_extraction.settings.openai_api_key", "sk-test")

    result = extract_hand_from_image(_tiny_jpeg_bytes())
    assert result is local_result


def test_extract_hand_returns_fallback_when_local_fails_and_no_api_key(monkeypatch):
    def raise_local(image_bytes):
        raise RuntimeError("local model missing")

    monkeypatch.setattr("app.tile_recognizer_local.recognize_tiles_local", raise_local)
    monkeypatch.setattr("app.hand_extraction.settings.openai_api_key", None)

    result = extract_hand_from_image(_tiny_jpeg_bytes())
    assert "OPENAI_API_KEY is not set; fallback result is used." in result["warnings"]


def test_extract_hand_single_pass_success(monkeypatch):
    _mock_no_local_recognizer(monkeypatch)
    monkeypatch.setattr("app.hand_extraction.settings.openai_api_key", "sk-test")
    monkeypatch.setattr("app.hand_extraction.settings.recognize_ensemble_passes", 1)

    tiles = ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "2p", "2p"]
    slots = [{"index": i, "top": t, "candidates": [{"tile": t, "confidence": 0.9}], "ambiguous": False} for i, t in enumerate(tiles)]
    payload = json.dumps({"tiles_count": 14, "slots": slots, "warnings": []})
    monkeypatch.setattr("app.hand_extraction.OpenAI", lambda api_key: _FakeOpenAIResponsesClient(payload))

    result = extract_hand_from_image(_tiny_jpeg_bytes())
    assert result["tiles_count"] == 14
    assert [slot["top"] for slot in result["slots"]] == tiles
    assert not any("Ensemble merge" in w for w in result["warnings"])


def test_extract_hand_multi_pass_applies_ensemble_merge(monkeypatch):
    _mock_no_local_recognizer(monkeypatch)
    monkeypatch.setattr("app.hand_extraction.settings.openai_api_key", "sk-test")
    monkeypatch.setattr("app.hand_extraction.settings.recognize_ensemble_passes", 3)

    tiles = ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "2p", "2p"]
    slots = [{"index": i, "top": t, "candidates": [{"tile": t, "confidence": 0.9}], "ambiguous": False} for i, t in enumerate(tiles)]
    payload = json.dumps({"tiles_count": 14, "slots": slots, "warnings": []})
    monkeypatch.setattr("app.hand_extraction.OpenAI", lambda api_key: _FakeOpenAIResponsesClient(payload))

    result = extract_hand_from_image(_tiny_jpeg_bytes())
    assert any("Ensemble merge applied across 3" in w for w in result["warnings"])


def test_extract_hand_all_passes_failing_returns_fallback(monkeypatch):
    _mock_no_local_recognizer(monkeypatch)
    monkeypatch.setattr("app.hand_extraction.settings.openai_api_key", "sk-test")
    monkeypatch.setattr("app.hand_extraction.settings.recognize_ensemble_passes", 3)
    monkeypatch.setattr("app.hand_extraction.OpenAI", lambda api_key: _FakeOpenAIResponsesClient(RuntimeError("boom")))

    result = extract_hand_from_image(_tiny_jpeg_bytes())
    assert any("All recognition passes failed; fallback was used." in w for w in result["warnings"])
    assert "OPENAI_API_KEY is not set; fallback result is used." not in result["warnings"]


class _SequencedResponses:
    def __init__(self, outputs: list[str]):
        self._outputs = list(outputs)

    def create(self, **kwargs):
        output_text = self._outputs.pop(0)
        return type("Response", (), {"output_text": output_text})()


class _SequencedClient:
    def __init__(self, outputs: list[str]):
        self.responses = _SequencedResponses(outputs)


def test_extract_hand_majority_vote_on_tiles_count(monkeypatch):
    _mock_no_local_recognizer(monkeypatch)
    monkeypatch.setattr("app.hand_extraction.settings.openai_api_key", "sk-test")
    monkeypatch.setattr("app.hand_extraction.settings.recognize_ensemble_passes", 3)

    tiles = ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "2p", "2p"]
    slots = [{"index": i, "top": t, "candidates": [{"tile": t, "confidence": 0.9}], "ambiguous": False} for i, t in enumerate(tiles)]
    payloads = [
        json.dumps({"tiles_count": 14, "slots": slots, "warnings": []}),
        json.dumps({"tiles_count": 14, "slots": slots, "warnings": []}),
        json.dumps({"tiles_count": 13, "slots": slots, "warnings": []}),
    ]
    monkeypatch.setattr("app.hand_extraction.OpenAI", lambda api_key: _SequencedClient(payloads))

    result = extract_hand_from_image(_tiny_jpeg_bytes())
    assert result["tiles_count"] == 14


def test_extract_hand_stops_on_cancellation(monkeypatch):
    _mock_no_local_recognizer(monkeypatch)
    monkeypatch.setattr("app.hand_extraction.settings.openai_api_key", "sk-test")
    monkeypatch.setattr("app.hand_extraction.settings.recognize_ensemble_passes", 3)
    monkeypatch.setattr("app.hand_extraction.OpenAI", lambda api_key: _FakeOpenAIResponsesClient('{"tiles_count": 14, "slots": []}'))

    with pytest.raises(RecognitionCancelledError):
        extract_hand_from_image(_tiny_jpeg_bytes(), should_cancel=lambda: True)


def test_extract_hand_stops_on_cancellation_between_passes(monkeypatch):
    _mock_no_local_recognizer(monkeypatch)
    monkeypatch.setattr("app.hand_extraction.settings.openai_api_key", "sk-test")
    monkeypatch.setattr("app.hand_extraction.settings.recognize_ensemble_passes", 3)
    monkeypatch.setattr("app.hand_extraction.OpenAI", lambda api_key: _FakeOpenAIResponsesClient('{"tiles_count": 14, "slots": []}'))

    calls = {"n": 0}

    def cancel_after_first_pass():
        calls["n"] += 1
        return calls["n"] > 1

    with pytest.raises(RecognitionCancelledError):
        extract_hand_from_image(_tiny_jpeg_bytes(), should_cancel=cancel_after_first_pass)


def test_extract_hand_records_per_pass_failure_and_model_warnings(monkeypatch):
    _mock_no_local_recognizer(monkeypatch)
    monkeypatch.setattr("app.hand_extraction.settings.openai_api_key", "sk-test")
    monkeypatch.setattr("app.hand_extraction.settings.recognize_ensemble_passes", 3)

    tiles = ["1m", "2m", "3m", "4p", "5p", "6p", "7s", "8s", "9s", "E", "E", "E", "2p", "2p"]
    slots = [{"index": i, "top": t, "candidates": [{"tile": t, "confidence": 0.9}], "ambiguous": False} for i, t in enumerate(tiles)]
    payloads = [
        json.dumps({"tiles_count": 14, "slots": [], "warnings": []}),  # empty slots -> per-pass failure
        json.dumps({"tiles_count": 14, "slots": slots, "warnings": ["low contrast"]}),
        json.dumps({"tiles_count": 14, "slots": slots, "warnings": []}),
    ]
    monkeypatch.setattr("app.hand_extraction.OpenAI", lambda api_key: _SequencedClient(payloads))

    result = extract_hand_from_image(_tiny_jpeg_bytes())
    assert any("recognition failed" in w and "slots is empty" in w for w in result["warnings"])
    assert any("low contrast" in w for w in result["warnings"])


def test_normalize_candidates_wraps_bare_string_slot():
    slots = _normalize_candidates(["1m"])
    assert slots == [{"index": 0, "top": "1m", "candidates": [], "ambiguous": True, "top_confidence": 0.0}]


def test_normalize_candidates_rejects_non_dict_non_string_slot():
    with pytest.raises(ValueError):
        _normalize_candidates([123])


def test_normalize_candidates_wraps_candidates_given_as_bare_string():
    raw_slots = [{"index": 0, "top": "1m", "candidates": "1m", "ambiguous": False}]
    slots = _normalize_candidates(raw_slots)
    assert slots[0]["candidates"] == [{"tile": "1m", "confidence": 0.0}]


def test_normalize_candidates_skips_non_dict_non_string_candidate():
    raw_slots = [{"index": 0, "top": "1m", "candidates": [123, {"tile": "1m", "confidence": 0.9}], "ambiguous": False}]
    slots = _normalize_candidates(raw_slots)
    assert slots[0]["candidates"] == [{"tile": "1m", "confidence": 0.9}]


def test_hand_shape_from_estimate_falls_back_to_top1_when_no_winning_combination():
    tiles = ["1m", "4m", "7m", "1p", "4p", "7p", "1s", "4s", "7s", "E", "S", "W", "N", "P"]
    slots = _slots_from_tiles(tiles)
    hand, warnings = hand_shape_from_estimate_with_warnings({"slots": slots})
    assert hand.closed_tiles == tiles
    assert any("Could not derive a guaranteed winning hand" in w for w in warnings)
