import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:tsumoai_mobile/main.dart';
import 'package:tsumoai_mobile/models/score_request.dart';
import 'package:tsumoai_mobile/screens/settings_screen.dart';
import 'package:tsumoai_mobile/screens/mahjong_rules_screen.dart';
import 'package:tsumoai_mobile/services/rule_settings_service.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Future<void> chooseRule(WidgetTester tester, String title, String value) async {
  final row = find
      .ancestor(of: find.text(title), matching: find.byType(Row))
      .first;
  final choice = find.descendant(of: row, matching: find.text(value));
  await tester.ensureVisible(choice);
  await tester.tap(choice);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'reopening rules in the same settings screen preserves earlier edits',
    (tester) async {
      var saved = const MahjongRuleSettings();
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            autoClassify: true,
            onAutoClassifyChanged: (_) {},
            showTrainingDataActions: false,
            onShowTrainingDataActionsChanged: (_) {},
            ruleSettings: saved,
            onRuleSettingsChanged: (value) => saved = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('麻雀ルール'));
      await tester.pumpAndSettle();
      await chooseRule(tester, '赤牌', 'なし');
      expect(saved.rules.akaAri, isFalse);
      Navigator.of(tester.element(find.byType(MahjongRulesScreen))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('麻雀ルール'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MahjongRulesScreen>(find.byType(MahjongRulesScreen))
            .settings
            .rules
            .akaAri,
        isFalse,
      );
      await chooseRule(tester, '喰いタン', 'なし');
      expect(saved.rules.kuitanAri, isFalse);
      expect(saved.rules.akaAri, isFalse);
    },
  );

  testWidgets(
    'latest preferences are edited while the active four-player match remains fixed',
    (tester) async {
      final previous = PathProviderPlatform.instance;
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('tsumo-rules-regression-'),
      );
      PathProviderPlatform.instance = _Paths(directory!.path);
      try {
        await tester.pumpWidget(const TsumoAIApp());
        await tester.pumpAndSettle();
        tester.widget<HomeScreen>(find.byType(HomeScreen)).onMatchStarted();
        await tester.pumpAndSettle();
        final before = tester.widget<HomeScreen>(find.byType(HomeScreen));
        final saved = await tester.runAsync(() async {
          before.onRuleSettingsChanged(
            const MahjongRuleSettings(rules: RuleSet(kuitanAri: false)),
          );
          for (var i = 0; i < 30; i++) {
            final value = await RuleSettingsService().loadLocal();
            if (!value.rules.kuitanAri) return value;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          throw StateError('Updated preferences were not saved');
        });
        expect(saved!.rules.kuitanAri, isFalse);
        await tester.pumpAndSettle();
        final active = tester.widget<HomeScreen>(find.byType(HomeScreen));
        expect(active.ruleSettings.rules.kuitanAri, isFalse);
        expect(active.matchRuleSettings!.rules.kuitanAri, isTrue);
        await tester.tap(find.byTooltip('設定'));
        await tester.pumpAndSettle();
        final settings = tester.widget<SettingsScreen>(
          find.byType(SettingsScreen),
        );
        expect(settings.ruleSettings.rules.kuitanAri, isFalse);
        final changed = await tester.runAsync(() async {
          settings.onRuleSettingsChanged(
            settings.ruleSettings.copyWith(chipsEnabled: true),
          );
          for (var i = 0; i < 30; i++) {
            final value = await RuleSettingsService().loadLocal();
            if (value.chipsEnabled) return value;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          throw StateError('Second preference change was not saved');
        });
        expect(changed!.rules.kuitanAri, isFalse);
        Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
        await tester.pumpAndSettle();
        final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
        expect(home.matchRuleSettings!.rules.kuitanAri, isTrue);
        home.onMatchEnded();
        await tester.pumpAndSettle();
        tester.widget<HomeScreen>(find.byType(HomeScreen)).onMatchStarted();
        await tester.pumpAndSettle();
        final restarted = tester.widget<HomeScreen>(find.byType(HomeScreen));
        expect(restarted.matchRuleSettings!.rules.kuitanAri, isFalse);
        expect(restarted.matchRuleSettings!.chipsEnabled, isTrue);
      } finally {
        await tester.pumpWidget(const SizedBox());
        PathProviderPlatform.instance = previous;
        await tester.runAsync(() => directory.delete(recursive: true));
      }
    },
  );
}
