import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/score_request.dart';
import 'package:tsumoai_mobile/models/match_state.dart';
import 'package:tsumoai_mobile/screens/match_home_screen.dart';
import 'package:tsumoai_mobile/screens/north_count_screen.dart';
import 'package:tsumoai_mobile/screens/scan_screen.dart';
import 'package:tsumoai_mobile/widgets/game_state_panel.dart';
import 'package:tsumoai_mobile/widgets/north_count_counter.dart';

void main() {
  testWidgets(
    'dora card counter clamps 0 to 4 and does not modify indicators',
    (tester) async {
      int count = 0;
      final context = ContextInput(doraIndicators: ['1m']);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) => GameStatePanel(
                sanma: true,
                context_: context,
                onChanged: (_) =>
                    fail('North count must not change dora indicators'),
                northCount: count,
                onNorthCountChanged: (v) => setState(() => count = v),
              ),
            ),
          ),
        ),
      );
      final minus = find.byKey(const ValueKey('north-count-minus'));
      final plus = find.byKey(const ValueKey('north-count-plus'));
      expect(tester.widget<IconButton>(minus).onPressed, isNull);
      expect(
        tester.getTopLeft(plus).dy,
        greaterThan(tester.getTopLeft(find.text('表ドラ表示牌')).dy),
      );
      for (int i = 0; i < 4; i++) {
        await tester.tap(plus);
        await tester.pump();
      }
      expect(count, 4);
      expect(find.text('4枚'), findsOneWidget);
      expect(tester.widget<IconButton>(plus).onPressed, isNull);
      await tester.tap(minus);
      await tester.pump();
      expect(count, 3);
      expect(context.doraIndicators, ['1m']);
      expect(find.textContaining('写真'), findsNothing);
    },
  );

  testWidgets('four-player dora inputs have no north counter', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameStatePanel(
            context_: ContextInput(),
            onChanged: (_) {},
            northCount: 0,
            onNorthCountChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.byType(NorthCountCounter), findsNothing);
  });

  for (final count in [0, 1, 2, 3, 4]) {
    testWidgets('win count $count is returned explicitly', (tester) async {
      int? returned;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  returned = await Navigator.of(context).push<int>(
                    MaterialPageRoute(builder: (_) => const NorthCountScreen()),
                  );
                },
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      for (int i = 0; i <= 4; i++) {
        expect(find.byKey(ValueKey('north-count-choice-$i')), findsOneWidget);
      }
      await tester.ensureVisible(
        find.byKey(ValueKey('north-count-choice-$count')),
      );
      await tester.tap(find.byKey(ValueKey('north-count-choice-$count')));
      await tester.pumpAndSettle();
      expect(returned, count);
    });
  }

  testWidgets('back cancels match count selection without opening capture', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MatchHomeScreen(
          cameras: [],
          autoClassify: false,
          showTrainingDataActions: false,
          ruleSettings: MahjongRuleSettings(rules: RuleSet(variant: 'sanma')),
        ),
      ),
    );
    await tester.ensureVisible(find.text('点数計算'));
    await tester.tap(find.text('点数計算'));
    await tester.pumpAndSettle();
    expect(find.byType(NorthCountScreen), findsOneWidget);
    expect(find.byType(ScanScreen), findsNothing);
    await tester.tap(find.text('戻る'));
    await tester.pumpAndSettle();
    expect(find.byType(NorthCountScreen), findsNothing);
    expect(find.byType(ScanScreen), findsNothing);
    expect(find.byType(MatchHomeScreen), findsOneWidget);
  });

  testWidgets('selected match count is passed to the scan as a condition', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MatchHomeScreen(
          cameras: [],
          autoClassify: false,
          showTrainingDataActions: false,
          ruleSettings: MahjongRuleSettings(rules: RuleSet(variant: 'sanma')),
        ),
      ),
    );
    await tester.ensureVisible(find.text('点数計算'));
    await tester.tap(find.text('点数計算'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('north-count-choice-3')));
    await tester.pumpAndSettle();
    final scan = tester.widget<ScanScreen>(find.byType(ScanScreen));
    expect(scan.initialNorthCount, 3);
    expect(scan.ruleSettings.rules.variant, 'sanma');
  });

  testWidgets(
    'winner selection carries the chosen count without advancing the hand',
    (tester) async {
      final match = MatchState(variant: 'sanma');
      await tester.pumpWidget(
        MaterialApp(
          home: MatchHomeScreen(
            cameras: const [],
            autoClassify: false,
            showTrainingDataActions: false,
            matchState: match,
            ruleSettings: const MahjongRuleSettings(
              rules: RuleSet(variant: 'sanma'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('西'));
      await tester.pumpAndSettle();
      expect(find.byType(NorthCountScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('north-count-choice-2')));
      await tester.pumpAndSettle();
      final scan = tester.widget<ScanScreen>(find.byType(ScanScreen));
      expect(scan.initialNorthCount, 2);
      expect(scan.initialWinnerIndex, 2);
      expect(scan.initialContext!.seatWind, 'W');
      expect(scan.onScoreConfirmed, isNotNull);
      expect(match.current.handNumber, 1);
    },
  );

  testWidgets('count screen remains usable with narrow screen and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(1.4),
          ),
          child: const NorthCountScreen(),
        ),
      ),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('north-count-choice-4')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
