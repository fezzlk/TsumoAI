import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/match_state.dart';

void main() {
  test('starts at east one with the starting seat as dealer', () {
    final match = MatchState();

    expect(match.current.roundLabel, '東1局 0本場');
    expect(match.current.dealerSeat, TableSeat.starting);
    expect(match.current.seatWind(TableSeat.starting), 'E');
    expect(match.current.seatWind(TableSeat.right), 'S');
  });

  test('dealer win repeats the hand and increments honba', () {
    final match = MatchState();

    match.recordWin(TableSeat.starting);

    expect(match.current.roundLabel, '東1局 1本場');
    expect(match.current.dealerSeat, TableSeat.starting);
  });

  test('non-dealer win advances hand and dealer', () {
    final match = MatchState();

    match.recordWin(TableSeat.right);

    expect(match.current.roundLabel, '東2局 0本場');
    expect(match.current.dealerSeat, TableSeat.right);
  });

  test('east four advances to south one and supports undo', () {
    final match = MatchState();
    match.recordWin(TableSeat.right);
    match.recordWin(TableSeat.opposite);
    match.recordWin(TableSeat.left);
    expect(match.current.roundLabel, '東4局 0本場');

    match.recordWin(TableSeat.starting);
    expect(match.current.roundLabel, '南1局 0本場');

    match.undo();
    expect(match.current.roundLabel, '東4局 0本場');
  });

  test('a draw adds 本場 whether the dealer continues or passes', () {
    final match = MatchState();

    match.recordDraw(dealerContinues: true);
    expect(match.current.roundLabel, '東1局 1本場');

    match.recordDraw(dealerContinues: false);
    expect(match.current.roundLabel, '東2局 2本場');
    expect(match.current.dealerSeat, TableSeat.right);

    // A non-dealer win then clears 本場.
    match.recordWin(TableSeat.opposite);
    expect(match.current.roundLabel, '東3局 0本場');
  });

  test('dora is shared in the current hand, cleared next hand, and restored', () {
    final match = MatchState();
    match.setDoraIndicators(['4m']);

    expect(match.current.contextFor(TableSeat.right).doraIndicators, ['4m']);

    match.recordWin(TableSeat.starting);
    expect(match.current.doraIndicators, isEmpty);

    match.undo();
    expect(match.current.doraIndicators, ['4m']);
  });
}
