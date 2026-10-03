// Renders the main screens to PNG files for before/after visual review.
//
// Skipped unless a directory is given; it is not a regression test:
//   flutter test test/screenshots/capture_test.dart \
//     --dart-define=SCREENSHOT_DIR=/absolute/output/dir
//
// Japanese text is drawn with macOS's Hiragino Sans GB (no font is added to
// the repository), so this only runs on macOS. ScanScreen needs a camera and
// is captured through its panels instead.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/main.dart';
import 'package:tsumoai_mobile/models/ai_chat_message.dart';
import 'package:tsumoai_mobile/models/ai_usage_status.dart';
import 'package:tsumoai_mobile/models/history_entry.dart';
import 'package:tsumoai_mobile/models/official_ai_chat_template.dart';
import 'package:tsumoai_mobile/models/question_template.dart';
import 'package:tsumoai_mobile/models/scan_purpose.dart';
import 'package:tsumoai_mobile/models/score_request.dart';
import 'package:tsumoai_mobile/models/score_result.dart';
import 'package:tsumoai_mobile/screens/ai_usage_screen.dart';
import 'package:tsumoai_mobile/screens/help_screen.dart';
import 'package:tsumoai_mobile/screens/history_screen.dart';
import 'package:tsumoai_mobile/screens/mahjong_rules_screen.dart';
import 'package:tsumoai_mobile/screens/match_home_screen.dart';
import 'package:tsumoai_mobile/screens/settings_screen.dart';
import 'package:tsumoai_mobile/services/history_service.dart';
import 'package:tsumoai_mobile/services/official_ai_chat_template_service.dart';
import 'package:tsumoai_mobile/services/question_template_service.dart';
import 'package:tsumoai_mobile/widgets/ai_chat_sheet.dart';
import 'package:tsumoai_mobile/widgets/analysis_result_panel.dart';
import 'package:tsumoai_mobile/widgets/purpose_switch_dialogs.dart';
import 'package:tsumoai_mobile/widgets/score_result_panel.dart';

import 'screenshot_theme.dart';

const _outputDir = String.fromEnvironment('SCREENSHOT_DIR');
const _phone = Size(402, 874);
const _narrow = Size(320, 568);

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final bytes = await File(path).readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  const japanese = '/System/Library/Fonts/Hiragino Sans GB.ttc';
  // Material's default text family on the test platform.
  await load('Roboto', japanese);
  await load(
    'MaterialIcons',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts/'
        'MaterialIcons-Regular.otf',
  );
}

Future<void> _capture(
  WidgetTester tester,
  String name,
  Widget screen, {
  Size size = _phone,
  bool wrap = true,
  Future<void> Function(WidgetTester tester)? interact,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  tester.view.padding = FakeViewPadding(
    top: 20 * tester.view.devicePixelRatio,
    bottom: 20 * tester.view.devicePixelRatio,
  );
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('screenshot'),
      child: wrap
          ? MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: screenshotTheme(),
              home: screen,
            )
          : screen,
    ),
  );
  await tester.pumpAndSettle();
  if (interact != null) {
    await interact(tester);
    await tester.pumpAndSettle();
  }

  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('screenshot')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final label = size == _phone ? '' : '_${size.width.toInt()}';
    await File(
      '$_outputDir/$name$label.png',
    ).writeAsBytes(png!.buffer.asUint8List());
  });
}

class _SampleHistoryService extends HistoryService {
  @override
  Future<List<HistoryEntry>> loadLocal() async {
    final now = DateTime.now().toUtc();
    HistoryEntry entry(
      int minutesAgo,
      String purpose,
      String title,
      String summary, [
      String? round,
    ]) => HistoryEntry(
      id: '$purpose-$minutesAgo',
      createdAt: now.subtract(Duration(minutes: minutesAgo)),
      updatedAt: now.subtract(Duration(minutes: minutesAgo)),
      purpose: purpose,
      title: title,
      summary: summary,
      roundLabel: round,
      details: const {},
    );
    return [
      entry(20, 'score', '点数計算', 'ツモ 2,000 / 3,900', '東2局・子'),
      entry(90, 'call_advice', '鳴き判断', '白はポン推奨・候補5種類'),
      entry(1500, 'wait', '待ち確認', '二筒・五筒'),
      entry(1560, 'discard', '何切る', '第一候補 五筒'),
      entry(1700, 'score', '点数計算', 'ロン 7,700'),
    ];
  }
}

class _MemoryTemplateService extends QuestionTemplateService {
  @override
  Future<List<QuestionTemplate>> loadLocal() async => [];
}

class _OfficialTemplates extends OfficialAIChatTemplateService {
  @override
  Future<OfficialAIChatTemplateConfig> load({bool refresh = true}) async =>
      OfficialAIChatTemplateService.defaults();
}

AIUsageStatus _usage() => AIUsageStatus(
  period: '2026-10',
  plan: 'free',
  includedLimit: 3,
  includedUsed: 1,
  bonusRemaining: 0,
  remaining: 2,
  resetsAt: DateTime(2026, 11, 1),
);

ScoreResponse _score(String winType) => ScoreResponse.fromJson({
  'score_id': winType,
  'status': 'ok',
  'result': {
    'han': winType == 'tsumo' ? 3 : 2,
    'fu': 30,
    'fu_breakdown': [],
    'yaku': [
      {'name': winType == 'tsumo' ? '門前清自摸和' : '立直', 'han': 1},
      {'name': '平和', 'han': 1},
    ],
    'yakuman': [],
    'dora': {'dora': 1, 'aka_dora': 0, 'ura_dora': 0},
    'point_label': winType == 'tsumo' ? '満貫' : '3900点',
    'points': {
      'ron': winType == 'ron' ? 3900 : 0,
      'tsumo_dealer_pay': winType == 'tsumo' ? 4000 : 0,
      'tsumo_non_dealer_pay': winType == 'tsumo' ? 2000 : 0,
    },
    'payments': {
      'hand_points_received': 0,
      'hand_points_with_honba': 0,
      'honba_bonus': 0,
      'kyotaku_bonus': 0,
      'total_received': 0,
    },
    'explanation': [],
  },
  'warnings': [],
});

Widget _panelHost(Widget panel) => Scaffold(
  backgroundColor: screenshotResultBackground(),
  body: SafeArea(child: SingleChildScrollView(child: panel)),
);

void main() {
  final skip = _outputDir.isEmpty || !Platform.isMacOS;

  setUpAll(() async {
    if (!skip) await _loadFonts();
  });

  testWidgets('capture main screens', skip: skip, (tester) async {
    await _capture(tester, '01_home', const TsumoAIApp(), wrap: false);
    await _capture(
      tester,
      '01_home',
      const TsumoAIApp(),
      wrap: false,
      size: _narrow,
    );
    await _capture(
      tester,
      '02_match_home',
      const MatchHomeScreen(
        cameras: [],
        autoClassify: false,
        showTrainingDataActions: false,
      ),
    );
    await _capture(
      tester,
      '03_settings',
      SettingsScreen(
        autoClassify: true,
        onAutoClassifyChanged: (_) {},
        showTrainingDataActions: false,
        onShowTrainingDataActionsChanged: (_) {},
        ruleSettings: const MahjongRuleSettings(),
        onRuleSettingsChanged: (_) {},
      ),
    );
    await _capture(
      tester,
      '04_history',
      HistoryScreen(service: _SampleHistoryService()),
    );
    await _capture(tester, '04b_help', HelpScreen(onContact: () {}));
    await _capture(
      tester,
      '04c_rules',
      MahjongRulesScreen(
        settings: const MahjongRuleSettings(),
        onChanged: (_) {},
      ),
    );
    await _capture(
      tester,
      '05_ai_usage',
      AIUsageScreen(loader: () async => _usage()),
    );
    await _capture(
      tester,
      '06_ai_chat',
      Scaffold(
        body: SafeArea(
          child: AIChatSheet(
            purpose: 'discard',
            tiles: const ['1m', '2m', '3m'],
            roundContext: const {},
            analysis: const {'discards': []},
            initialMessages: const [
              AIChatMessage(role: 'user', content: '親リーチの状況です。何を切る？'),
              AIChatMessage(
                role: 'assistant',
                content: '安全牌の東を切り、受け入れを残しながら守備を優先するのがおすすめです。',
              ),
            ],
            templateService: _MemoryTemplateService(),
            officialTemplateService: _OfficialTemplates(),
            isSignedIn: () => true,
            usageLoader: () async => _usage(),
            sender:
                ({
                  required message,
                  required conversation,
                  required situationTags,
                }) async => '回答',
          ),
        ),
      ),
    );
    await _capture(
      tester,
      '07_score_result',
      _panelHost(
        ScoreResultPanel(
          tsumoResponse: _score('tsumo'),
          ronResponse: _score('ron'),
          ruleSettings: const MahjongRuleSettings(),
          isOpenHand: false,
        ),
      ),
    );
    await _capture(
      tester,
      '08_wait_result',
      _panelHost(
        const AnalysisResultPanel(
          result: {
            'shanten': 0,
            'improving_tiles': [
              {'tile': '2p', 'remaining': 3},
              {'tile': '5p', 'remaining': 2},
            ],
          },
        ),
      ),
    );
    await _capture(
      tester,
      '09_discard_result',
      _panelHost(
        AnalysisResultPanel(
          result: const {
            'shanten': 1,
            'discards': [
              {
                'discard': 'C',
                'shanten': 0,
                'total_remaining': 5,
                'improving_tiles': [
                  {'tile': '2p', 'remaining': 3},
                  {'tile': '5p', 'remaining': 2},
                ],
              },
              {
                'discard': '9s',
                'shanten': 1,
                'total_remaining': 12,
                'improving_tiles': [
                  {'tile': '3m', 'remaining': 4},
                ],
              },
            ],
          },
          onAskAiWithDiscardFocus: (_) {},
        ),
      ),
    );
    await _capture(
      tester,
      '10_call_result',
      _panelHost(
        AnalysisResultPanel(
          result: const {
            'current_shanten': 2,
            'calls': [
              {
                'call_tile': '3m',
                'call_type': 'chi',
                'consumed_tiles': ['1m', '2m'],
                'shanten_after_call': 1,
                'recommendation': 'improves',
                'possible_yaku': ['役牌 白'],
              },
              {
                'call_tile': '5m',
                'call_type': 'pon',
                'consumed_tiles': ['5m', '5m'],
                'shanten_after_call': 2,
                'recommendation': 'keeps',
              },
              {
                'call_tile': 'E',
                'call_type': 'pon',
                'consumed_tiles': ['E', 'E'],
                'shanten_after_call': 3,
                'recommendation': 'worsens',
              },
            ],
          },
          onAskAiAboutCall: (_) {},
        ),
      ),
    );
    await _capture(
      tester,
      '11_purpose_switch_dialog',
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () =>
                  showPurposeSwitchDialog(context, current: ScanPurpose.score),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      interact: (tester) => tester.tap(find.text('open')),
    );
  });
}
