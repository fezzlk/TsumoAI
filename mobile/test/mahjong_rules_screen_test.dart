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
    await tester.tap(find.widgetWithText(SwitchListTile, 'チップ'));
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

    await tester.tap(find.widgetWithText(SwitchListTile, '赤牌'));
    await tester.pump();

    expect(settings.rules.akaAri, isFalse);
  });
}
