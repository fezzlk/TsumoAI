"""Translate visual tile observations into explicit mahjong fact candidates."""

from app.interpretation.interpreter import interpret_observations, request_from_hand_estimate

__all__ = ["interpret_observations", "request_from_hand_estimate"]
