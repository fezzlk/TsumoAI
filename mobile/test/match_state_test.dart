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

  test('draw follows the selected dealer continuation rule', () {
    final match = MatchState();

    match.recordDraw(dealerContinues: true);
    expect(match.current.roundLabel, '東1局 1本場');

    match.recordDraw(dealerContinues: false);
    expect(match.current.roundLabel, '東2局 0本場');
  });
}
