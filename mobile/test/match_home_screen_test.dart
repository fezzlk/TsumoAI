import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/screens/match_home_screen.dart';
import 'package:tsumoai_mobile/models/match_state.dart';
import 'package:tsumoai_mobile/widgets/tile_glyph.dart';

void main() {
  testWidgets('table dora can be entered and toggled to the dora tile', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MatchHomeScreen(
          cameras: [],
          autoClassify: false,
          showTrainingDataActions: false,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tile_picker_cell_4m')));
    await tester.pumpAndSettle();

    // In the dora panel and in the carried-over summary.
    expect(find.byType(TileGlyph), findsNWidgets(2));
    expect(
      tester.widget<TileGlyph>(find.byType(TileGlyph).first).tileCode,
      '4m',
    );

    await tester.tap(find.text('ドラ牌'));
    await tester.pump();

    expect(
      tester.widget<TileGlyph>(find.byType(TileGlyph).first).tileCode,
      '5m',
    );
  });

  testWidgets('match home exposes all four quick checks', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MatchHomeScreen(
          cameras: [],
          autoClassify: false,
          showTrainingDataActions: false,
        ),
      ),
    );

    for (final label in ['点数計算', '待ち確認', '何を切る？', '鳴き判断']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('match home keeps an injected match state', (tester) async {
    final match = MatchState()..recordWin(TableSeat.right);

    await tester.pumpWidget(
      MaterialApp(
        home: MatchHomeScreen(
          cameras: const [],
          autoClassify: true,
          showTrainingDataActions: false,
          matchState: match,
        ),
      ),
    );

    expect(find.text('0本場'), findsOneWidget);
    expect(find.text('東二局'), findsOneWidget);
  });

  testWidgets('match state is cleared only after end confirmation', (
    tester,
  ) async {
    var ended = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MatchHomeScreen(
          cameras: const [],
          autoClassify: false,
          showTrainingDataActions: false,
          onMatchEnded: () => ended = true,
        ),
      ),
    );

    await tester.ensureVisible(find.byKey(const ValueKey('end-match-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('end-match-button')));
    await tester.pumpAndSettle();

    expect(find.text('対局を終了しますか？'), findsOneWidget);
    expect(find.text('終了した局'), findsOneWidget);
    expect(find.text('計算済み'), findsNothing);
    expect(find.text('0局'), findsOneWidget);
    expect(find.textContaining('局の進行状況はリセットされます'), findsOneWidget);
    expect(ended, isFalse);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(ended, isFalse);

    await tester.ensureVisible(find.byKey(const ValueKey('end-match-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('end-match-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('対局を続ける'));
    await tester.pumpAndSettle();
    expect(ended, isFalse);

    await tester.ensureVisible(find.byKey(const ValueKey('end-match-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('end-match-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('対局を終了').last);
    await tester.pumpAndSettle();

    expect(ended, isTrue);
  });

  testWidgets('seat winds rotate counter-clockwise with the dealer', (
    tester,
  ) async {
    Future<void> pump(MatchState match) => tester.pumpWidget(
      MaterialApp(
        home: MatchHomeScreen(
          cameras: const [],
          autoClassify: false,
          showTrainingDataActions: false,
          matchState: match,
        ),
      ),
    );

    // 東1局: 下=東(起家・親), 右=南, 上=西, 左=北.
    await pump(MatchState());
    for (final label in ['東（起家・親）', '南（起家の右隣）', '西（起家の対面）', '北（起家の左隣）']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }

    // 東2局 (dealer moved right): 右=東(親), 上=南, 左=西, 下=北(起家).
    await tester.pumpWidget(const SizedBox());
    await pump(MatchState()..recordWin(TableSeat.right));
    await tester.pumpAndSettle();
    for (final label in ['東（起家の右隣・親）', '南（起家の対面）', '西（起家の左隣）', '北（起家）']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
  });
}
