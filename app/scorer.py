from __future__ import annotations

from app.hand_scoring import score_hand_shape
from app.schemas import ContextInput, HandInput, RuleSet, ScoreResult


def score_hand(hand: HandInput, context: ContextInput, rules: RuleSet) -> ScoreResult:
    """Backward-compatible wrapper. Use app.hand_scoring instead."""
    return score_hand_shape(hand, context, rules)
