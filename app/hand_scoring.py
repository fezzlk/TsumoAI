"""Backward-compatible scoring facade.

New code may import ``app.scoring.calculator.score_hand_shape`` directly.
"""

from app.scoring.calculator import score_hand_shape

__all__ = ["score_hand_shape"]
