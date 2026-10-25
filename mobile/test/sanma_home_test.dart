import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:tsumoai_mobile/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:tsumoai_mobile/main.dart';
import 'package:tsumoai_mobile/models/match_state.dart';
import 'package:tsumoai_mobile/models/score_request.dart';
import 'package:tsumoai_mobile/services/app_preferences.dart';
import 'package:tsumoai_mobile/screens/history_screen.dart';
import 'sanma_test.dart' show MixedHistory;

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

const previewDir = String.fromEnvironment('SANMA_PREVIEW_DIR');
Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (previewDir.isEmpty) return;
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 500)),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '$previewDir/${previewDir.split('/').last.substring(0, 14)}_$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

HomeScreen home(
  String variant, {
  bool active = false,
  ValueChanged<String>? onChanged,
}) => HomeScreen(
  cameras: const [],
  autoClassify: true,
  roundWind: 'E',
  showTrainingDataActions: false,
  ruleSettings: MahjongRuleSettings(rules: RuleSet(variant: variant)),
  matchState: MatchState(variant: variant),
  matchActive: active,
  variant: variant,
  onVariantChanged: onChanged,
  onAutoClassifyChanged: (_) {},
  onRoundWindChanged: (_) {},
  onShowTrainingDataActionsChanged: (_) {},
  onRuleSettingsChanged: (_) {},
  onAuthenticationChanged: () async {},
  onMatchStarted: () {},
  onMatchReturned: () {},
  onMatchEnded: () {},
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (previewDir.isEmpty) return;
    for (final (family, path) in [
      ('Roboto', '/System/Library/Fonts/Hiragino Sans GB.ttc'),
      (
        'MaterialIcons',
        '/usr/local/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    ]) {
      final bytes = await File(path).readAsBytes();
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
  test(
    'variant persists without overwriting simultaneous preferences',
    () async {
      final directory = await Directory.systemTemp.createTemp('tsumo-variant-');
      final original = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(directory.path);
      try {
        expect(await AppPreferences.mahjongVariant(), 'yonma');
        await Future.wait([
          AppPreferences.setMahjongVariant('sanma'),
          AppPreferences.setShowTrainingDataActions(true),
          AppPreferences.setScanDiagnosticsEnabled(true),
        ]);
        expect(await AppPreferences.mahjongVariant(), 'sanma');
        expect(await AppPreferences.showTrainingDataActions(), isTrue);
        expect(await AppPreferences.scanDiagnosticsEnabled(), isTrue);
      } finally {
        PathProviderPlatform.instance = original;
        await directory.delete(recursive: true);
      }
    },
  );
  testWidgets('TOP defaults to four and switches below start button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    String selected = 'yonma';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: StatefulBuilder(
          builder: (context, setState) => RepaintBoundary(
            key: key,
            child: home(
              selected,
              onChanged: (v) => setState(() => selected = v),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final switchFinder = find.byKey(const ValueKey('mahjong-variant-switch'));
    expect(tester.widget<SegmentedButton<String>>(switchFinder).selected, {
      'yonma',
    });
    expect(
      tester.getTopLeft(switchFinder).dy,
      greaterThan(tester.getBottomLeft(find.text('対局を始める')).dy),
    );
    await tester.ensureVisible(switchFinder);
    await tester.tap(find.text('3人麻雀'));
    await tester.pumpAndSettle();
    expect(selected, 'sanma');
    expect(
      tester
          .widget<HomeScreen>(find.byType(HomeScreen))
          .ruleSettings
          .rules
          .variant,
      'sanma',
    );
    await capture(tester, key, 'top_sanma');
  });
  testWidgets('TOP switch is locked during active match', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: home(
          'sanma',
          active: true,
          onChanged: (_) => fail('Active match cannot change variant'),
        ),
      ),
    );
    final button = tester.widget<SegmentedButton<String>>(
      find.byKey(const ValueKey('mahjong-variant-switch')),
    );
    expect(button.onSelectionChanged, isNull);
    expect(button.selected, {'sanma'});
    expect(find.text('対局中は変更できません'), findsOneWidget);
  });
  testWidgets('mixed history displays mode badges', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: RepaintBoundary(
          key: key,
          child: HistoryScreen(service: MixedHistory()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3人麻雀'), findsNWidgets(3));
    expect(find.text('4人麻雀'), findsNWidgets(2));
    await capture(tester, key, 'history_mixed');
  });
}
