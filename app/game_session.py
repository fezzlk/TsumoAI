from __future__ import annotations

import copy
import random
import string
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Literal
from uuid import UUID, uuid4


WIND_LABELS = ["E", "S", "W", "N"]


@dataclass
class PlayerState:
    name: str
    points: int
    seat: int  # 0=East, 1=South, 2=West, 3=North (initial)


@dataclass
class RoundRecord:
    round_number: int
    round_wind: str
    dealer_seat: int
    honba: int
    result_type: Literal["ron", "tsumo", "draw", "chombo"]
    winner_seat: int | None = None
    loser_seat: int | None = None
    score_result: dict | None = None
    point_changes: dict[int, int] = field(default_factory=dict)
    riichi_seats: list[int] = field(default_factory=list)


@dataclass
class GameSnapshot:
    """Snapshot for undo support."""
    players_points: list[int]
    current_round: int
    current_honba: int
    current_kyotaku: int
    status: Literal["active", "finished"]


@dataclass
class GameSession:
    game_id: UUID
    players: list[PlayerState]
    rounds: list[RoundRecord] = field(default_factory=list)
    current_round: int = 0
    current_honba: int = 0
    current_kyotaku: int = 0
    status: Literal["active", "finished"] = "active"
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    game_type: Literal["east_only", "east_south"] = "east_only"
    room_code: str = ""
    _snapshots: list[GameSnapshot] = field(default_factory=list, repr=False)


def _generate_room_code() -> str:
    """Generate a 6-character alphanumeric room code."""
    return "".join(random.choices(string.ascii_uppercase + string.digits, k=6))


def _take_snapshot(session: GameSession) -> None:
    """Save current state before a mutation for undo support."""
    snap = GameSnapshot(
        players_points=[p.points for p in session.players],
        current_round=session.current_round,
        current_honba=session.current_honba,
        current_kyotaku=session.current_kyotaku,
        status=session.status,
    )
    session._snapshots.append(snap)


def undo_last(session: GameSession) -> RoundRecord | None:
    """Undo the last round. Returns the removed round record, or None if nothing to undo."""
    if not session.rounds or not session._snapshots:
        return None
    snap = session._snapshots.pop()
    removed = session.rounds.pop()
    # Restore state
    for i, p in enumerate(session.players):
        p.points = snap.players_points[i]
    session.current_round = snap.current_round
    session.current_honba = snap.current_honba
    session.current_kyotaku = snap.current_kyotaku
    session.status = snap.status
    return removed


def create_game(player_names: list[str], starting_points: int = 25000,
                game_type: Literal["east_only", "east_south"] = "east_only") -> GameSession:
    """Create a new 4-player mahjong game session."""
    if len(player_names) != 4:
        raise ValueError("Exactly 4 player names are required")
    players = [PlayerState(name=name, points=starting_points, seat=i)
               for i, name in enumerate(player_names)]
    return GameSession(
        game_id=uuid4(),
        players=players,
        game_type=game_type,
        room_code=_generate_room_code(),
    )


def get_dealer_seat(session: GameSession) -> int:
    """Get the current dealer seat (round 0 = seat 0, round 1 = seat 1, etc.)."""
    return session.current_round % 4


def get_round_wind(session: GameSession) -> str:
    """Get the current round wind."""
    wind_index = session.current_round // 4
    if wind_index >= len(WIND_LABELS):
        wind_index = len(WIND_LABELS) - 1
    return WIND_LABELS[wind_index]


def _base_points(han: int, fu: int) -> int:
    """Calculate base points from han and fu, mirroring hand_scoring logic."""
    if han >= 13:
        return 8000
    if han >= 11:
        return 6000
    if han >= 8:
        return 4000
    if han >= 6:
        return 3000
    if han == 5 or (han == 4 and fu >= 40) or (han == 3 and fu >= 70):
        return 2000
    return fu * (2 ** (han + 2))


def _calc_base(han: int, fu: int, yakuman_multiplier: int = 0) -> int:
    """Get effective base points considering yakuman."""
    if yakuman_multiplier > 0:
        return 8000 * yakuman_multiplier
    return _base_points(han, fu)


def _ceil100(value: int) -> int:
    """Ceiling to nearest 100."""
    return ((value + 99) // 100) * 100


def _calc_ron_payment(base: int, is_dealer: bool) -> int:
    """Calculate total ron payment (before honba)."""
    multiplier = 6 if is_dealer else 4
    return _ceil100(base * multiplier)


def _calc_tsumo_payments(base: int, is_dealer_winner: bool) -> tuple[int, int]:
    """Calculate tsumo payments: (dealer_pay, non_dealer_pay).

    If dealer wins: each non-dealer pays ceil(base*2).
    If non-dealer wins: dealer pays ceil(base*2), non-dealers pay ceil(base).
    Returns (dealer_pay, non_dealer_pay) from the perspective of payers.
    """
    if is_dealer_winner:
        each = _ceil100(base * 2)
        return each, each  # dealer_pay unused; all pay same
    dealer_pay = _ceil100(base * 2)
    non_dealer_pay = _ceil100(base)
    return dealer_pay, non_dealer_pay


def _apply_riichi(session: GameSession, riichi_seats: list[int],
                  point_changes: dict[int, int]) -> None:
    """Deduct riichi costs and add to kyotaku."""
    for seat in riichi_seats:
        point_changes[seat] = point_changes.get(seat, 0) - 1000
        session.current_kyotaku += 1


def apply_ron(session: GameSession, winner_seat: int, loser_seat: int,
              han: int, fu: int, yakuman_multiplier: int = 0,
              riichi_seats: list[int] | None = None) -> RoundRecord:
    """Apply a ron win and record the round."""
    if session.status != "active":
        raise ValueError("Game is not active")
    if winner_seat == loser_seat:
        raise ValueError("Winner and loser cannot be the same player")
    if not (0 <= winner_seat <= 3 and 0 <= loser_seat <= 3):
        raise ValueError("Invalid seat number")

    _take_snapshot(session)

    riichi_seats = riichi_seats or []
    point_changes: dict[int, int] = {i: 0 for i in range(4)}

    # Apply riichi deductions first
    _apply_riichi(session, riichi_seats, point_changes)

    dealer_seat = get_dealer_seat(session)
    is_dealer = winner_seat == dealer_seat
    base = _calc_base(han, fu, yakuman_multiplier)
    payment = _calc_ron_payment(base, is_dealer)

    # Honba bonus
    honba_bonus = session.current_honba * 300

    # Loser pays, winner receives
    total_payment = payment + honba_bonus
    point_changes[loser_seat] -= total_payment
    point_changes[winner_seat] += total_payment

    # Winner collects kyotaku
    kyotaku_bonus = session.current_kyotaku * 1000
    point_changes[winner_seat] += kyotaku_bonus

    # Apply point changes
    for seat, change in point_changes.items():
        session.players[seat].points += change

    round_record = RoundRecord(
        round_number=session.current_round,
        round_wind=get_round_wind(session),
        dealer_seat=dealer_seat,
        honba=session.current_honba,
        result_type="ron",
        winner_seat=winner_seat,
        loser_seat=loser_seat,
        score_result={"han": han, "fu": fu, "yakuman_multiplier": yakuman_multiplier},
        point_changes=dict(point_changes),
        riichi_seats=list(riichi_seats),
    )
    session.rounds.append(round_record)

    # Reset kyotaku after win
    session.current_kyotaku = 0

    # Advance round
    dealer_won = winner_seat == dealer_seat
    advance_round(session, dealer_won)

    return round_record


def apply_tsumo(session: GameSession, winner_seat: int,
                han: int, fu: int, yakuman_multiplier: int = 0,
                riichi_seats: list[int] | None = None) -> RoundRecord:
    """Apply a tsumo win and record the round."""
    if session.status != "active":
        raise ValueError("Game is not active")
    if not (0 <= winner_seat <= 3):
        raise ValueError("Invalid seat number")

    _take_snapshot(session)

    riichi_seats = riichi_seats or []
    point_changes: dict[int, int] = {i: 0 for i in range(4)}

    # Apply riichi deductions first
    _apply_riichi(session, riichi_seats, point_changes)

    dealer_seat = get_dealer_seat(session)
    is_dealer_winner = winner_seat == dealer_seat
    base = _calc_base(han, fu, yakuman_multiplier)
    dealer_pay, non_dealer_pay = _calc_tsumo_payments(base, is_dealer_winner)

    # Honba bonus: honba * 100 per payer
    honba_per_player = session.current_honba * 100

    total_received = 0
    for seat in range(4):
        if seat == winner_seat:
            continue
        if is_dealer_winner:
            # All non-dealers pay equal
            pay = non_dealer_pay + honba_per_player
        else:
            if seat == dealer_seat:
                pay = dealer_pay + honba_per_player
            else:
                pay = non_dealer_pay + honba_per_player
        point_changes[seat] -= pay
        total_received += pay

    point_changes[winner_seat] += total_received

    # Winner collects kyotaku
    kyotaku_bonus = session.current_kyotaku * 1000
    point_changes[winner_seat] += kyotaku_bonus

    # Apply point changes
    for seat, change in point_changes.items():
        session.players[seat].points += change

    round_record = RoundRecord(
        round_number=session.current_round,
        round_wind=get_round_wind(session),
        dealer_seat=dealer_seat,
        honba=session.current_honba,
        result_type="tsumo",
        winner_seat=winner_seat,
        score_result={"han": han, "fu": fu, "yakuman_multiplier": yakuman_multiplier},
        point_changes=dict(point_changes),
        riichi_seats=list(riichi_seats),
    )
    session.rounds.append(round_record)

    # Reset kyotaku after win
    session.current_kyotaku = 0

    # Advance round
    dealer_won = winner_seat == dealer_seat
    advance_round(session, dealer_won)

    return round_record


def apply_draw(session: GameSession, tenpai_seats: list[int] | None = None,
               riichi_seats: list[int] | None = None) -> RoundRecord:
    """Apply a draw (流局) and record the round."""
    if session.status != "active":
        raise ValueError("Game is not active")

    _take_snapshot(session)

    tenpai_seats = tenpai_seats or []
    riichi_seats = riichi_seats or []
    point_changes: dict[int, int] = {i: 0 for i in range(4)}

    # Apply riichi deductions
    _apply_riichi(session, riichi_seats, point_changes)

    # Tenpai/noten payments
    num_tenpai = len(tenpai_seats)
    noten_seats = [s for s in range(4) if s not in tenpai_seats]

    if 1 <= num_tenpai <= 3:
        total_pool = 3000
        tenpai_receive = total_pool // num_tenpai
        noten_pay = total_pool // len(noten_seats)
        for seat in tenpai_seats:
            point_changes[seat] += tenpai_receive
        for seat in noten_seats:
            point_changes[seat] -= noten_pay

    # Apply point changes
    for seat, change in point_changes.items():
        session.players[seat].points += change

    dealer_seat = get_dealer_seat(session)

    round_record = RoundRecord(
        round_number=session.current_round,
        round_wind=get_round_wind(session),
        dealer_seat=dealer_seat,
        honba=session.current_honba,
        result_type="draw",
        point_changes=dict(point_changes),
        riichi_seats=list(riichi_seats),
    )
    session.rounds.append(round_record)

    # Kyotaku stays on table after draw (riichi sticks remain)

    # Dealer tenpai means dealer retains
    dealer_tenpai = dealer_seat in tenpai_seats
    advance_round(session, dealer_won=dealer_tenpai)

    return round_record


def advance_round(session: GameSession, dealer_won: bool) -> None:
    """Advance to next round after a result.

    If dealer won (or tenpai in draw), dealer stays and honba increments.
    Otherwise, dealer rotates and honba resets (for wins) or increments (for draws).
    """
    if dealer_won:
        # Dealer retains, honba increments
        session.current_honba += 1
    else:
        # Dealer rotates
        session.current_round += 1
        # For non-dealer win, honba resets to 0
        # For draw with dealer noten, honba increments
        last_round = session.rounds[-1] if session.rounds else None
        if last_round and last_round.result_type == "draw":
            session.current_honba += 1
        else:
            session.current_honba = 0

        # Check game end
        max_rounds = 4 if session.game_type == "east_only" else 8
        if session.current_round >= max_rounds:
            session.status = "finished"
