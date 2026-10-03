import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/score_request.dart';
import 'package:tsumoai_mobile/screens/mahjong_rules_screen.dart';

void main() {
  testWidgets('chip details appear only when chips are enabled', (tester) async {
    var settings = const MahjongRuleSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: MahjongRulesScreen(
          settings: settings,
          onChanged: (value) => settings = value,
        ),
      ),
    );

    expect(find.text('副露ありでも有効'), findsNothing);
    final chips = find.widgetWithText(SwitchListTile, 'チップ');
    await tester.ensureVisible(chips);
    await tester.pumpAndSettle();
    await tester.tap(chips);
    await tester.pump();

    expect(settings.chipsEnabled, isTrue);
    expect(find.text('副露ありでも有効'), findsOneWidget);
  });

  testWidgets('calculation rule changes are returned immediately', (
    tester,
  ) async {
    var settings = const MahjongRuleSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: MahjongRulesScreen(
          settings: settings,
          onChanged: (value) => settings = value,
        ),
      ),
    );

    // 赤牌 defaults to あり; its なし is the first なし on the screen.
    await tester.tap(find.text('なし').first);
    await tester.pump();

    expect(settings.rules.akaAri, isFalse);
  });
}
