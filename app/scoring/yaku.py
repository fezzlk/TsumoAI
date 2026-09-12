from __future__ import annotations

from dataclasses import dataclass

from app.schemas import ContextInput, HandInput, YakuItem


@dataclass(frozen=True)
class YakuEvaluation:
    items: tuple[YakuItem, ...]
    han: int


def evaluate_context_yaku(hand: HandInput, context: ContextInput) -> YakuEvaluation:
    """Evaluate event/context yaku that do not depend on hand decomposition."""
    items: list[YakuItem] = []
    if context.double_riichi:
        items.append(YakuItem(name="ダブル立直", han=2))
    elif context.riichi:
        items.append(YakuItem(name="立直", han=1))
    if context.ippatsu:
        items.append(YakuItem(name="一発", han=1))
    if context.haitei:
        items.append(YakuItem(name="海底摸月", han=1))
    if context.houtei:
        items.append(YakuItem(name="河底撈魚", han=1))
    if context.rinshan and any(meld.type in {"kan", "ankan", "kakan"} for meld in hand.melds):
        items.append(YakuItem(name="嶺上開花", han=1))
    if context.chankan:
        items.append(YakuItem(name="槍槓", han=1))
    if context.win_type == "tsumo" and not any(meld.open for meld in hand.melds):
        items.append(YakuItem(name="門前清自摸和", han=1))
    return YakuEvaluation(items=tuple(items), han=sum(item.han for item in items))
