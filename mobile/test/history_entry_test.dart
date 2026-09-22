import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/history_entry.dart';

void main() {
  test('history entry round-trips through JSON', () {
    final entry = HistoryEntry(
      id: 'f326bb37-6e89-46db-a95b-fb763ac8936a',
      createdAt: DateTime.utc(2026, 9, 22),
      updatedAt: DateTime.utc(2026, 9, 22, 0, 0, 1),
      purpose: 'score',
      title: '点数計算',
      summary: '3翻40符 5200点',
      roundLabel: '東2局 1本場',
      details: const {'han': 3, 'fu': 40},
    );

    final decoded = HistoryEntry.fromJson(entry.toJson());

    expect(decoded.id, entry.id);
    expect(decoded.summary, '3翻40符 5200点');
    expect(decoded.roundLabel, '東2局 1本場');
    expect(decoded.details, {'han': 3, 'fu': 40});
  });
}
