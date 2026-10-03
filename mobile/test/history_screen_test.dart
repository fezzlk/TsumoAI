import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/history_entry.dart';
import 'package:tsumoai_mobile/screens/history_screen.dart';
import 'package:tsumoai_mobile/services/history_service.dart';

class _HistoryWithCallAdvice extends HistoryService {
  @override
  Future<List<HistoryEntry>> loadLocal() async => [
    HistoryEntry(
      id: 'f326bb37-6e89-46db-a95b-fb763ac8936a',
      createdAt: DateTime.utc(2026, 9, 30, 1, 2),
      updatedAt: DateTime.utc(2026, 9, 30, 1, 2),
      purpose: 'call_advice',
      title: '鳴き判断',
      summary: '鳴き候補 1件',
      roundLabel: '東2局 1本場',
      details: const {
        'tiles': ['1m', '2m', '4m'],
        'context': {'round_wind': 'E', 'seat_wind': 'S'},
        'result': {
          'current_shanten': 2,
          'calls': [
            {
              'call_tile': '3m',
              'call_type': 'chi',
              'consumed_tiles': ['1m', '2m'],
              'shanten_after_call': 1,
              'recommendation': 'improves',
              'possible_yaku': <String>[],
              'discards': <Map<String, Object>>[],
            },
          ],
        },
      },
    ),
  ];
}

void main() {
  testWidgets(
    'history categories stay at the bottom and entries open details',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: HistoryScreen(service: _HistoryWithCallAdvice())),
      );
      await tester.pumpAndSettle();

      // Category tabs sit at the bottom of the screen.
      final tabTop = tester.getTopLeft(find.text('すべて')).dy;
      expect(tabTop, greaterThan(tester.getTopLeft(find.text('鳴き判断')).dy));
      expect(find.text('鳴き判断'), findsOneWidget);

      await tester.tap(find.text('鳴き判断'));
      await tester.pumpAndSettle();

      expect(find.byType(HistoryDetailScreen), findsOneWidget);
      expect(find.text('東2局 1本場'), findsOneWidget);
      expect(find.text('場風 東'), findsOneWidget);
      expect(find.text('自風 南'), findsOneWidget);
      expect(find.byKey(const ValueKey('history-tile-0')), findsOneWidget);
      expect(find.text('2 → 1シャンテン'), findsOneWidget);
      expect(find.text('推奨'), findsOneWidget);
    },
  );
}
