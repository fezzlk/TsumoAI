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

    expect(find.byType(TileGlyph), findsOneWidget);
    expect(tester.widget<TileGlyph>(find.byType(TileGlyph)).tileCode, '4m');

    await tester.tap(find.text('表ドラ表示牌'));
    await tester.pump();

    expect(find.text('表ドラ牌'), findsOneWidget);
    expect(tester.widget<TileGlyph>(find.byType(TileGlyph)).tileCode, '5m');
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

    expect(find.text('東2局\n0本場'), findsOneWidget);
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

    await tester.tap(find.text('対局終了'));
    await tester.pumpAndSettle();

    expect(find.text('対局を終了しますか？'), findsOneWidget);
    expect(find.textContaining('局の進行状況はリセットされます'), findsOneWidget);
    expect(ended, isFalse);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(ended, isFalse);

    await tester.tap(find.text('対局終了'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('対局を終了'));
    await tester.pumpAndSettle();

    expect(ended, isTrue);
  });
}
