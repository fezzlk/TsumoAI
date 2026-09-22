import 'score_request.dart';

enum TableSeat { starting, right, opposite, left }

class MatchSnapshot {
  const MatchSnapshot({
    required this.roundWind,
    required this.handNumber,
    required this.honba,
    required this.dealerSeat,
  });

  final String roundWind;
  final int handNumber;
  final int honba;
  final TableSeat dealerSeat;

  String get roundLabel => '${_windLabel(roundWind)}$handNumber局 $honba本場';

  String get dealerLabel => seatLabel(dealerSeat);

  String seatWind(TableSeat seat) {
    final offset = (seat.index - dealerSeat.index) % TableSeat.values.length;
    return const ['E', 'S', 'W', 'N'][offset];
  }

  ContextInput contextFor(TableSeat seat) => ContextInput(
    roundWind: roundWind,
    seatWind: seatWind(seat),
    isDealer: seat == dealerSeat,
    honba: honba,
  );

  MatchSnapshot dealerContinues() => MatchSnapshot(
    roundWind: roundWind,
    handNumber: handNumber,
    honba: honba + 1,
    dealerSeat: dealerSeat,
  );

  MatchSnapshot dealerChanges() {
    var nextWind = roundWind;
    var nextHand = handNumber + 1;
    if (nextHand > 4) {
      nextHand = 1;
      nextWind = _nextWind(roundWind);
    }
    return MatchSnapshot(
      roundWind: nextWind,
      handNumber: nextHand,
      honba: 0,
      dealerSeat: TableSeat.values[(dealerSeat.index + 1) % 4],
    );
  }

  static String seatLabel(TableSeat seat) => switch (seat) {
    TableSeat.starting => '起家・手前',
    TableSeat.right => '下家・右',
    TableSeat.opposite => '対面',
    TableSeat.left => '上家・左',
  };

  static String _windLabel(String wind) => switch (wind) {
    'E' => '東',
    'S' => '南',
    'W' => '西',
    'N' => '北',
    _ => wind,
  };

  static String _nextWind(String wind) => switch (wind) {
    'E' => 'S',
    'S' => 'W',
    'W' => 'N',
    'N' => 'E',
    _ => 'E',
  };
}

class MatchState {
  MatchState()
    : _current = const MatchSnapshot(
        roundWind: 'E',
        handNumber: 1,
        honba: 0,
        dealerSeat: TableSeat.starting,
      );

  MatchSnapshot _current;
  final List<MatchSnapshot> _history = [];

  MatchSnapshot get current => _current;
  bool get canUndo => _history.isNotEmpty;

  void recordWin(TableSeat winner) {
    _history.add(_current);
    _current = winner == _current.dealerSeat
        ? _current.dealerContinues()
        : _current.dealerChanges();
  }

  void recordDraw({required bool dealerContinues}) {
    _history.add(_current);
    _current = dealerContinues
        ? _current.dealerContinues()
        : _current.dealerChanges();
  }

  void undo() {
    if (_history.isEmpty) return;
    _current = _history.removeLast();
  }
}
