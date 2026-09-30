import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/main.dart';
import 'package:tsumoai_mobile/models/score_request.dart';
import 'package:tsumoai_mobile/models/score_result.dart';
import 'package:tsumoai_mobile/screens/history_screen.dart';
import 'package:tsumoai_mobile/screens/match_home_screen.dart';
import 'package:tsumoai_mobile/services/history_service.dart';
import 'package:tsumoai_mobile/models/history_entry.dart';
import 'package:tsumoai_mobile/widgets/analysis_result_panel.dart';
import 'package:tsumoai_mobile/widgets/score_result_panel.dart';
import 'package:tsumoai_mobile/widgets/tile_count_selector.dart';
import 'package:tsumoai_mobile/widgets/tile_image_picker.dart';

import 'test_utils/landscape_surface.dart';

class _EmptyHistoryService extends HistoryService {
  @override
  Future<List<HistoryEntry>> loadLocal() async => [];
}

const _narrowPortrait = Size(320, 568);
const _narrowPadding = EdgeInsets.only(bottom: 20);

ScoreResponse _scoreResponse(String winType) => ScoreResponse.fromJson({
  'score_id': winType,
  'status': 'ok',
  'result': {
    'han': 6,
    'fu': 30,
    'fu_breakdown': [
      {'name': '門前ロン', 'fu': 10},
      {'name': '嵌張待ち', 'fu': 2},
    ],
    'yaku': [
      {'name': '立直', 'han': 1},
      {'name': '一発', 'han': 1},
      {'name': '混一色', 'han': 3},
    ],
    'yakuman': [],
    'dora': {'dora': 1, 'aka_dora': 3, 'ura_dora': 1},
    'point_label': '跳満 12000点',
    'points': {
      'ron': winType == 'ron' ? 12000 : 0,
      'tsumo_dealer_pay': winType == 'tsumo' ? 6000 : 0,
      'tsumo_non_dealer_pay': winType == 'tsumo' ? 3000 : 0,
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

void main() {
  testWidgets('home fits a narrow portrait screen without stale copy', (
    tester,
  ) async {
    await pumpAtDeviceSize(
      tester,
      const TsumoAIApp(),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );
    await tester.pumpAndSettle();

    expect(find.text('待ち牌・有効牌'), findsOneWidget);
    expect(find.text('待ち牌・残り枚数'), findsNothing);
    expect(find.text('実際の対局進行に合わせて点数計算を行う'), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('home remains usable with enlarged text on a narrow screen', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(
      tester.platformDispatcher.clearTextScaleFactorTestValue,
    );

    await pumpAtDeviceSize(
      tester,
      const TsumoAIApp(),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );
    await tester.pumpAndSettle();

    expect(find.text('点数計算'), findsOneWidget);
    expect(find.text('実際の対局進行に合わせて点数計算を行う'), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('tile count choices stay visible on a narrow portrait screen', (
    tester,
  ) async {
    int? selected = 14;
    await pumpAtDeviceSize(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: TileCountSelector(
            selectedCount: selected,
            counts: const [13, 14, 15, 16, 17, 18],
            onChanged: (value) => setState(() => selected = value),
          ),
        ),
      ),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );
    await tester.pumpAndSettle();

    final labels = ['自動', '13', '14', '15', '16', '17', '18'];
    final verticalCenters = <double>[];
    for (final label in labels) {
      final finder = find.text(label);
      expect(finder, findsOneWidget);
      expect(
        tester.getRect(finder).right,
        lessThanOrEqualTo(_narrowPortrait.width),
      );
      verticalCenters.add(tester.getCenter(finder).dy);
    }
    expect(verticalCenters.toSet(), hasLength(1));
    expectNoOverflow(tester);

    await tester.tap(find.text('18'));
    await tester.pump();
    expect(selected, 18);
    expectNoOverflow(tester);
  });

  testWidgets('history filters wrap without horizontal clipping', (
    tester,
  ) async {
    await pumpAtDeviceSize(
      tester,
      HistoryScreen(service: _EmptyHistoryService()),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );
    await tester.pumpAndSettle();

    for (final label in ['すべて', '点数', '待ち', 'AI相談']) {
      expect(find.text(label), findsOneWidget);
    }
    expectNoOverflow(tester);
  });

  testWidgets('match home fits a narrow portrait screen', (tester) async {
    await pumpAtDeviceSize(
      tester,
      const MatchHomeScreen(
        cameras: [],
        autoClassify: false,
        showTrainingDataActions: false,
      ),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );
    await tester.pumpAndSettle();

    expect(find.text('和了者を選択'), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('match home remains usable with enlarged text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpAtDeviceSize(
      tester,
      const MatchHomeScreen(
        cameras: [],
        autoClassify: false,
        showTrainingDataActions: false,
      ),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );
    await tester.pumpAndSettle();

    expect(find.text('和了者を選択'), findsOneWidget);
    expect(find.text('対局終了'), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('settings remains usable with enlarged text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpAtDeviceSize(
      tester,
      const TsumoAIApp(),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );
    await tester.tap(find.byTooltip('設定'));
    await tester.pumpAndSettle();

    expect(find.text('利用履歴'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -360));
    await tester.pumpAndSettle();
    expect(find.text('プライバシーポリシー'), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('call advice and its detail dialog fit a narrow screen', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpAtDeviceSize(
      tester,
      Scaffold(
        body: ListView(
          children: const [
            AnalysisResultPanel(
              result: {
                'current_shanten': 2,
                'calls': [
                  {
                    'call_tile': '3m',
                    'call_type': 'chi',
                    'consumed_tiles': ['1m', '2m'],
                    'shanten_after_call': 1,
                    'recommendation': 'improves',
                    'possible_yaku': ['混一色', '一気通貫'],
                    'discards': [
                      {
                        'discard': 'E',
                        'total_remaining': 12,
                        'improving_tiles': [
                          {'tile': '4m', 'remaining': 4},
                          {'tile': '5m', 'remaining': 4},
                          {'tile': '6m', 'remaining': 4},
                        ],
                      },
                    ],
                  },
                ],
              },
            ),
          ],
        ),
      ),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );
    await tester.pumpAndSettle();
    expectNoOverflow(tester);

    await tester.tap(find.byKey(const ValueKey('analysis-call-candidate-0')));
    await tester.pumpAndSettle();

    expect(find.text('チーの詳細'), findsOneWidget);
    expect(find.text('混一色・一気通貫'), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('all tile choices fit the narrow correction dialog', (
    tester,
  ) async {
    String? selected;
    await pumpAtDeviceSize(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                selected = await TileImagePicker.show(context);
              },
              child: const Text('牌を選択'),
            ),
          ),
        ),
      ),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );

    await tester.tap(find.text('牌を選択'));
    await tester.pumpAndSettle();
    expectNoOverflow(tester);

    for (final tile in ['9m', '5mr', '9p', '5pr', '9s', '5sr', 'C']) {
      final finder = find.byKey(ValueKey('tile_picker_cell_$tile'));
      expect(finder, findsOneWidget);
      expect(tester.getRect(finder).right, lessThanOrEqualTo(320));
    }

    await tester.tap(find.byKey(const ValueKey('tile_picker_cell_5sr')));
    await tester.pumpAndSettle();
    expect(selected, '5sr');
  });

  testWidgets('score and chip details wrap on a narrow screen', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpAtDeviceSize(
      tester,
      Scaffold(
        body: ListView(
          children: [
            ScoreResultPanel(
              tsumoResponse: _scoreResponse('tsumo'),
              ronResponse: _scoreResponse('ron'),
              ruleSettings: const MahjongRuleSettings(chipsEnabled: true),
            ),
          ],
        ),
      ),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );
    await tester.pumpAndSettle();

    expect(find.text('ツモの場合'), findsOneWidget);
    expect(find.text('ロンの場合'), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('three discard candidates wrap on a narrow screen', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpAtDeviceSize(
      tester,
      Scaffold(
        body: ListView(
          children: const [
            AnalysisResultPanel(
              result: {
                'shanten': 2,
                'discards': [
                  {
                    'discard': '1m',
                    'shanten': 1,
                    'total_remaining': 24,
                    'improving_tiles': [
                      {'tile': '2m', 'remaining': 4},
                      {'tile': '3m', 'remaining': 4},
                    ],
                  },
                  {
                    'discard': '9p',
                    'shanten': 1,
                    'total_remaining': 20,
                    'improving_tiles': [
                      {'tile': '7p', 'remaining': 4},
                      {'tile': '8p', 'remaining': 4},
                    ],
                  },
                  {
                    'discard': 'C',
                    'shanten': 1,
                    'total_remaining': 16,
                    'improving_tiles': [
                      {'tile': 'E', 'remaining': 3},
                      {'tile': 'S', 'remaining': 3},
                    ],
                  },
                ],
              },
            ),
          ],
        ),
      ),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('analysis-discard-1m-0')), findsOneWidget);
    expectNoOverflow(tester);
  });
}
