import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/screens/match_home_screen.dart';
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
}
