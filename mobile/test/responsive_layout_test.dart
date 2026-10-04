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
import 'package:tsumoai_mobile/widgets/game_state_panel.dart';
import 'package:tsumoai_mobile/widgets/score_result_panel.dart';
import 'package:tsumoai_mobile/widgets/tile_count_selector.dart';
import 'package:tsumoai_mobile/widgets/tile_image_picker.dart';
import 'package:tsumoai_mobile/widgets/purpose_switch_dialogs.dart';
import 'package:tsumoai_mobile/widgets/section_list.dart';
import 'package:tsumoai_mobile/models/scan_purpose.dart';

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

    expect(find.text('待ち牌を確認'), findsOneWidget);
    expect(find.textContaining('残り枚数'), findsNothing);
    expect(find.text('実際の対局進行に合わせて\n点数計算を行う'), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('home remains usable with enlarged text on a narrow screen', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpAtDeviceSize(
      tester,
      const TsumoAIApp(),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );
    await tester.pumpAndSettle();

    expect(find.text('点数計算'), findsOneWidget);
    expect(find.text('実際の対局進行に合わせて\n点数計算を行う'), findsOneWidget);
    expectNoOverflow(tester);
  });

  testWidgets('home header keeps login and settings on screen', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpAtDeviceSize(
      tester,
      const TsumoAIApp(),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );
    await tester.pumpAndSettle();

    for (final finder in [find.text('ログイン'), find.byTooltip('設定')]) {
      expect(finder, findsOneWidget);
      expect(tester.getRect(finder).right, lessThanOrEqualTo(320));
    }
    // 使い方 lives in Settings only (decided 2026-09-26).
    expect(find.byTooltip('使い方'), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('tile count choices: frequent ones visible, 17/18 by scroll', (
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

    // 17 and 18 are rare (decided 2026-09-26): they may sit past the edge.
    final verticalCenters = <double>{};
    for (final label in ['自動', '13', '14', '15']) {
      final finder = find.text(label);
      expect(finder, findsOneWidget);
      expect(
        tester.getRect(finder).right,
        lessThanOrEqualTo(_narrowPortrait.width),
      );
      verticalCenters.add(tester.getCenter(finder).dy);
    }
    expect(verticalCenters, hasLength(1));
    expectNoOverflow(tester);

    await tester.ensureVisible(find.text('18'));
    await tester.pumpAndSettle();
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

    for (final label in ['すべて', '点数', '待ち', '何切る', '鳴き']) {
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

    expect(find.text('和了した人の座席をタップ'), findsOneWidget);
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

    expect(find.text('和了した人の座席をタップ'), findsOneWidget);
    expect(find.byKey(const ValueKey('end-match-button')), findsOneWidget);
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
    for (final label in ['利用規約', 'プライバシーポリシー', '問い合わせ']) {
      final tile = tester.widget<SectionTile>(
        find.widgetWithText(SectionTile, label),
      );
      expect(tile.onTap, isNotNull, reason: '$label must not be a dead end');
    }
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

  testWidgets('score and chip details wrap on a narrow screen', (tester) async {
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

  testWidgets('round and seat winds use one-tap dialogs on a narrow screen', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var value = ContextInput(roundWind: 'E', seatWind: 'S');

    await pumpAtDeviceSize(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: GameStatePanel(
            context_: value,
            onChanged: (next) => setState(() => value = next),
          ),
        ),
      ),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );
    await tester.pumpAndSettle();
    expectNoOverflow(tester);

    await tester.tap(find.byKey(const ValueKey('wind-selector-場風')));
    await tester.pumpAndSettle();
    expect(find.text('場風を選択'), findsOneWidget);
    expect(find.text('確定'), findsNothing);
    expectNoOverflow(tester);

    await tester.tap(find.byKey(const ValueKey('場風-W')));
    await tester.pumpAndSettle();
    expect(value.roundWind, 'W');
    expect(find.text('西'), findsOneWidget);
  });
  testWidgets('switch-purpose dialog fits a narrow screen with enlarged text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    ScanPurpose? selected;
    await pumpAtDeviceSize(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                selected = await showPurposeSwitchDialog(
                  context,
                  current: ScanPurpose.score,
                );
              },
              child: const Text('別の確認へ'),
            ),
          ),
        ),
      ),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );

    await tester.tap(find.text('別の確認へ'));
    await tester.pumpAndSettle();
    expectNoOverflow(tester);

    expect(find.byKey(const ValueKey('switch-purpose-score')), findsNothing);
    expect(find.text('同じ牌で確認します'), findsOneWidget);
    expect(find.text('外す牌を1枚選びます'), findsNWidgets(2));
    for (final purpose in [
      ScanPurpose.wait,
      ScanPurpose.discard,
      ScanPurpose.callAdvice,
    ]) {
      final rect = tester.getRect(
        find.byKey(ValueKey('switch-purpose-${purpose.name}')),
      );
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.right, lessThanOrEqualTo(320));
    }

    await tester.tap(find.byKey(const ValueKey('switch-purpose-wait')));
    await tester.pumpAndSettle();
    expect(selected, ScanPurpose.wait);
  });

  testWidgets('switch-purpose dialog from 13 tiles offers adding a tile', (
    tester,
  ) async {
    await pumpAtDeviceSize(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () =>
                  showPurposeSwitchDialog(context, current: ScanPurpose.wait),
              child: const Text('別の確認へ'),
            ),
          ),
        ),
      ),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );

    await tester.tap(find.text('別の確認へ'));
    await tester.pumpAndSettle();
    expect(find.text('同じ牌で確認します'), findsOneWidget);
    expect(find.text('ツモ牌を1枚追加します'), findsNWidgets(2));
  });

  testWidgets('tile removal dialog shows all 14 tiles on a narrow screen', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const tiles = [
      '1m', '2m', '3m', '4p', '5pr', '6p', '7s', '8s', '9s', 'E', 'E', 'E', //
      'C', 'C',
    ];
    int? removed;
    await pumpAtDeviceSize(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                removed = await showTileRemovalDialog(
                  context,
                  target: ScanPurpose.wait,
                  candidates: [
                    for (var index = 0; index < tiles.length; index++)
                      (index, tiles[index]),
                  ],
                  highlightedIndex: 13,
                );
              },
              child: const Text('外す'),
            ),
          ),
        ),
      ),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );

    await tester.tap(find.text('外す'));
    await tester.pumpAndSettle();
    expectNoOverflow(tester);
    expect(find.textContaining('待ち確認は13枚で行います'), findsOneWidget);

    for (var index = 0; index < tiles.length; index++) {
      final finder = find.byKey(ValueKey('remove-tile-$index'));
      expect(finder, findsOneWidget);
      expect(tester.getRect(finder).right, lessThanOrEqualTo(320));
    }

    await tester.ensureVisible(find.byKey(const ValueKey('remove-tile-13')));
    await tester.tap(find.byKey(const ValueKey('remove-tile-13')));
    await tester.pumpAndSettle();
    expect(removed, 13);
  });

  testWidgets('tile picker can explain why a tile is being added', (
    tester,
  ) async {
    await pumpAtDeviceSize(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () =>
                  TileImagePicker.show(context, title: '追加するツモ牌を選択'),
              child: const Text('追加'),
            ),
          ),
        ),
      ),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );

    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();
    expectNoOverflow(tester);
    expect(find.text('追加するツモ牌を選択'), findsOneWidget);
  });
}
