"""Deterministic standard three/four-player tile rules."""
from dataclasses import dataclass

from app.domain.tiles import tile_to_index


@dataclass(frozen=True)
class ResolvedRules:
    variant: str = "yonma"

    @property
    def player_count(self) -> int:
        return 3 if self.variant == "sanma" else 4

    @property
    def tile_supply(self) -> tuple[int, ...]:
        return tuple(0 if self.variant == "sanma" and 1 <= i <= 7 else 4 for i in range(34))

    def allows_tile(self, tile: str) -> bool:
        return self.tile_supply[tile_to_index(tile)] > 0

    @property
    def chi_allowed(self) -> bool:
        return self.variant == "yonma"
