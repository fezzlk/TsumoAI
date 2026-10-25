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

class _HistoryWithScores extends HistoryService {
  _HistoryWithScores(this.tsumo, this.ron);

  final Map<String, Object> tsumo;
  final Map<String, Object> ron;

  @override
  Future<List<HistoryEntry>> loadLocal() async => [
    HistoryEntry(
      id: '0b8a2f4e-2b7e-4d55-9a57-3c1f0d2e6a11',
      createdAt: DateTime.utc(2026, 10, 25, 1, 2),
      updatedAt: DateTime.utc(2026, 10, 25, 1, 2),
      purpose: 'score',
      title: '点数計算',
      summary: 'ツモ: 2翻30符 / ロン: 2翻30符',
      details: {
        'tiles': const ['1m'],
        'context': const {'round_wind': 'E', 'seat_wind': 'S'},
        'tsumo': tsumo,
        'ron': ron,
      },
    ),
  ];
}

Future<void> _openScore(
  WidgetTester tester,
  Map<String, Object> tsumo,
  Map<String, Object> ron,
) async {
  await tester.pumpWidget(
    MaterialApp(home: HistoryScreen(service: _HistoryWithScores(tsumo, ron))),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('点数計算'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('score history shows payments including 本場 and 供託', (
    tester,
  ) async {
    await _openScore(
      tester,
      const {
        'han': 2,
        'fu': 30,
        'point_label': '2000点',
        'tsumo_dealer_pay': 1000,
        'tsumo_non_dealer_pay': 500,
        'honba_per_payer': 200,
        'kyotaku_bonus': 0,
        'total_received': 2600,
      },
      const {
        'han': 2,
        'fu': 30,
        'point_label': '2000点',
        'ron': 2000,
        'honba_per_payer': 600,
        'kyotaku_bonus': 1000,
        'total_received': 3600,
      },
    );

    expect(find.text('700 / 1,200（本場 +200込み）'), findsOneWidget);
    expect(find.text('2,600（本場 +600込み）'), findsOneWidget);
    expect(find.text('供託 +1,000・受け取り合計 3,600'), findsOneWidget);
  });

  testWidgets('older score history without 本場 shows hand points', (
    tester,
  ) async {
    await _openScore(
      tester,
      const {
        'han': 2,
        'fu': 30,
        'point_label': '2000点',
        'tsumo_dealer_pay': 700,
        'tsumo_non_dealer_pay': 700,
      },
      const {'han': 2, 'fu': 30, 'point_label': '2000点', 'ron': 2000},
    );

    expect(find.text('700 オール'), findsOneWidget);
    expect(find.text('2,000'), findsOneWidget);
  });

  testWidgets(
    'history categories stay at the bottom and entries open details',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: HistoryScreen(service: _HistoryWithCallAdvice())),
      );
      await tester.pumpAndSettle();

      // Category tabs sit at the bottom of the screen.
      final tabTop = tester.getTopLeft(find.text('すべて').last).dy;
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
