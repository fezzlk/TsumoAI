import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/history_entry.dart';
import 'package:tsumoai_mobile/models/match_state.dart';
import 'package:tsumoai_mobile/models/score_request.dart';
import 'package:tsumoai_mobile/screens/history_screen.dart';
import 'package:tsumoai_mobile/screens/match_home_screen.dart';
import 'package:tsumoai_mobile/services/history_service.dart';
import 'package:tsumoai_mobile/services/tile_assets.dart';
import 'package:tsumoai_mobile/widgets/tile_image_picker.dart';
import 'package:tsumoai_mobile/widgets/game_state_panel.dart';

class MixedHistory extends HistoryService {
  @override
  Future<List<HistoryEntry>> loadLocal() async => [
    for (final (variant, purpose, title) in [
      ('sanma', 'score', '三麻点数'),
      ('yonma', 'score', '四麻点数'),
      ('sanma', 'call_advice', '三麻鳴き'),
    ])
      HistoryEntry(
        variant: variant,
        id: '$variant-$purpose',
        createdAt: DateTime.utc(2026, 10, 13),
        updatedAt: DateTime.utc(2026, 10, 13),
        purpose: purpose,
        title: title,
        summary: '記録',
        details: const {},
      ),
  ];
}

void main() {
  test('sanma seats and rounds survive repeat, dora and undo', () {
    final match = MatchState(variant: 'sanma');
    expect(match.current.activeSeats, [
      TableSeat.starting,
      TableSeat.right,
      TableSeat.left,
    ]);
    expect(match.current.seatWind(TableSeat.left), 'W');
    match.setDoraIndicators(['1m']);
    match.recordWin(TableSeat.starting);
    expect(match.current.variant, 'sanma');
    match.undo();
    expect(match.current.doraIndicators, ['1m']);
    match.recordWin(TableSeat.right);
    match.recordWin(TableSeat.left);
    expect(match.current.roundLabel, '東3局 0本場');
    match.recordWin(TableSeat.starting);
    expect(match.current.roundLabel, '南1局 0本場');
    match.undo();
    expect(match.current.variant, 'sanma');
  });

  test('history migration and copy preserve mode', () {
    final entry = HistoryEntry(
      variant: 'sanma',
      id: 'id',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      purpose: 'score',
      title: '点数',
      summary: '記録',
      details: const {},
    );
    expect(
      HistoryEntry.fromJson(entry.toJson()).copyWith(accountUid: 'u').variant,
      'sanma',
    );
    final legacy = entry.toJson()..remove('variant');
    expect(HistoryEntry.fromJson(legacy).variantLabel, '4人麻雀');
    expect(const RuleSet().variant, 'yonma');
    expect(
      RuleSet.fromJson(const {
        'variant': 'sanma',
      }).copyWith(akaAri: false).variant,
      'sanma',
    );
  });

  test('sanma dora wraps both ways', () {
    expect(doraTileFromIndicator('1m', sanma: true), '9m');
    expect(doraIndicatorFromTile('9m', sanma: true), '1m');
    expect(doraTileFromIndicator('9m', sanma: true), '1m');
    expect(doraIndicatorFromTile('1m', sanma: true), '9m');
  });

  testWidgets('mixed history combines variant and purpose filters', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HistoryScreen(service: MixedHistory())),
    );
    await tester.pumpAndSettle();
    expect(find.text('三麻点数'), findsOneWidget);
    expect(find.text('四麻点数'), findsOneWidget);
    final filter = find.byKey(const ValueKey('history-variant-filter'));
    await tester.tap(find.descendant(of: filter, matching: find.text('3人麻雀')));
    await tester.pumpAndSettle();
    expect(find.text('四麻点数'), findsNothing);
    expect(find.text('三麻鳴き'), findsOneWidget);
    await tester.tap(find.text('点数'));
    await tester.pumpAndSettle();
    expect(find.text('三麻点数'), findsOneWidget);
    expect(find.text('三麻鳴き'), findsNothing);
    await tester.tap(find.text('鳴き'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: filter, matching: find.text('4人麻雀')));
    await tester.pumpAndSettle();
    expect(find.text('条件に一致する履歴はありません'), findsOneWidget);
    await tester.tap(find.text('絞り込みを解除'));
    await tester.pumpAndSettle();
    expect(find.text('四麻点数'), findsOneWidget);
    expect(find.text('三麻鳴き'), findsOneWidget);
  });

  testWidgets('sanma match does not offer opposite seat', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MatchHomeScreen(
          cameras: const [],
          autoClassify: false,
          showTrainingDataActions: false,
          ruleSettings: const MahjongRuleSettings(
            rules: RuleSet(variant: 'sanma'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('対面'), findsNothing);
    expect(find.text('3人麻雀'), findsOneWidget);
  });

  testWidgets('sanma picker removes unavailable manzu', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: TileImagePicker(sanma: true, onTileSelected: (_) {}),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('tile_picker_cell_1m')), findsOneWidget);
    expect(find.byKey(const ValueKey('tile_picker_cell_9m')), findsOneWidget);
    expect(find.byKey(const ValueKey('tile_picker_cell_2m')), findsNothing);
    expect(find.byKey(const ValueKey('tile_picker_cell_5mr')), findsNothing);
  });

  testWidgets('sanma seat selector has no north', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameStatePanel(
            sanma: true,
            context_: ContextInput(),
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('wind-selector-自風')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('自風-N')), findsNothing);
    expect(find.byKey(const ValueKey('自風-W')), findsOneWidget);
  });
}
