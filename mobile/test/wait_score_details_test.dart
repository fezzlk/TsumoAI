import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/widgets/analysis_result_panel.dart';

Map<String, dynamic> score({
  bool tsumo = false,
  bool yakuman = false,
  bool bonuses = false,
}) => {
  'han': yakuman
      ? 13
      : bonuses
      ? 3
      : 1,
  'fu': yakuman
      ? 0
      : bonuses
      ? 40
      : 30,
  'point_label': yakuman ? '役満' : '通常',
  'yaku': yakuman
      ? []
      : [
          {'name': '三色同順', 'han': 1},
          if (bonuses) {'name': 'ドラ', 'han': 1},
          if (bonuses) {'name': '赤ドラ', 'han': 1},
        ],
  'yakuman': yakuman ? ['大三元'] : [],
  'dora': {'dora': bonuses ? 1 : 0, 'aka_dora': bonuses ? 1 : 0, 'ura_dora': 0},
  'points': tsumo
      ? {'ron': 0, 'tsumo_dealer_pay': 500, 'tsumo_non_dealer_pay': 300}
      : {
          'ron': yakuman
              ? 32000
              : bonuses
              ? 5200
              : 1000,
        },
  'payments': {
    'hand_points_received': yakuman
        ? 32000
        : bonuses
        ? 5200
        : tsumo
        ? 1100
        : 1000,
    'honba_bonus': bonuses ? 600 : 0,
    'kyotaku_bonus': bonuses ? 1000 : 0,
    'total_received': bonuses
        ? 6800
        : yakuman
        ? 32000
        : tsumo
        ? 1100
        : 1000,
  },
};

Widget panel(List<Map<String, dynamic>> waits, {int shanten = 0}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AnalysisResultPanel(
            result: {
              'shanten': shanten,
              'score_conditions': ['リーチなし'],
              'improving_tiles': waits,
            },
          ),
        ),
      ),
    );

void main() {
  testWidgets('each wait shows its own ron and tsumo yaku and points', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      panel([
        {
          'tile': '3s',
          'remaining': 4,
          'ron_score': score(),
          'tsumo_score': score(tsumo: true),
        },
        {
          'tile': '6s',
          'remaining': 4,
          'ron_score': null,
          'tsumo_score': null,
          'ron_score_error': 'No yaku: dora-only hands cannot win',
          'tsumo_score_error': 'No yaku: dora-only hands cannot win',
        },
      ]),
    );
    expect(find.text('ロン 1000点'), findsOneWidget);
    expect(find.text('ツモ 1100点（合計）'), findsOneWidget);
    expect(find.text('子 300点・親 500点払い'), findsOneWidget);
    expect(find.text('役: 三色同順 1翻'), findsNWidgets(2));
    expect(find.text('1翻 30符'), findsNWidgets(2));
    expect(find.text('ロン: 役なし（この条件では和了できません）'), findsOneWidget);
    expect(find.text('ツモ: 役なし（この条件では和了できません）'), findsOneWidget);
    expect(find.text('どれかの牌で和了できます'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dora and table bonuses are separate from yaku and hand points', (
    tester,
  ) async {
    await tester.pumpWidget(
      panel([
        {
          'tile': '3s',
          'remaining': 4,
          'ron_score': score(bonuses: true),
          'tsumo_score': null,
        },
      ]),
    );
    expect(find.text('ロン 5200点'), findsOneWidget);
    expect(find.text('3翻 40符'), findsOneWidget);
    expect(find.text('役: 三色同順 1翻'), findsOneWidget);
    expect(find.text('ドラ1・赤ドラ1'), findsOneWidget);
    expect(find.text('本場 +600点・供託 +1000点・受取合計 6800点'), findsOneWidget);
  });

  testWidgets('tsumo can have yaku even when ron has none', (tester) async {
    final tsumo = score(tsumo: true)
      ..['yaku'] = [
        {'name': '門前清自摸和', 'han': 1},
      ];
    await tester.pumpWidget(
      panel([
        {
          'tile': '6p',
          'remaining': 4,
          'ron_score': null,
          'ron_score_error': 'No yaku: dora-only hands cannot win',
          'tsumo_score': tsumo,
        },
      ]),
    );
    expect(find.text('ロン: 役なし（この条件では和了できません）'), findsOneWidget);
    expect(find.text('役: 門前清自摸和 1翻'), findsOneWidget);
    expect(find.text('ツモ 1100点（合計）'), findsOneWidget);
  });

  testWidgets('yakuman does not show zero fu or an empty yaku label', (
    tester,
  ) async {
    await tester.pumpWidget(
      panel([
        {
          'tile': 'C',
          'remaining': 1,
          'ron_score': score(yakuman: true),
          'tsumo_score': null,
        },
      ]),
    );
    expect(find.text('役: 大三元'), findsOneWidget);
    expect(find.text('役満'), findsOneWidget);
    expect(find.text('ロン 32000点'), findsOneWidget);
    expect(find.textContaining('0符'), findsNothing);
  });

  testWidgets('unknown score failures are not shown as no yaku or raw errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      panel([
        {
          'tile': '3s',
          'remaining': 4,
          'ron_score': null,
          'ron_score_error': 'internal engine error',
          'tsumo_score': null,
        },
      ]),
    );
    expect(find.text('ロン: 役・打点を判定できませんでした'), findsOneWidget);
    expect(find.text('ツモ: 役・打点は未算定'), findsOneWidget);
    expect(find.textContaining('役なし'), findsNothing);
    expect(find.textContaining('internal engine error'), findsNothing);
  });

  testWidgets(
    'legacy saved results show the available score without inventing the other one',
    (tester) async {
      await tester.pumpWidget(
        panel([
          {'tile': '3s', 'remaining': 4, 'score': score()},
        ]),
      );
      expect(find.text('ロン 1000点'), findsOneWidget);
      expect(find.textContaining('再解析するとロン・ツモ両方'), findsOneWidget);
      expect(find.textContaining('ツモ 1100'), findsNothing);
    },
  );

  testWidgets('non-tenpai cards stay focused on improving tiles', (
    tester,
  ) async {
    await tester.pumpWidget(
      panel([
        {'tile': '3s', 'remaining': 4, 'ron_score': score()},
      ], shanten: 1),
    );
    expect(find.text('有効牌は1種類'), findsOneWidget);
    expect(find.text('ロン 1000点'), findsNothing);
  });
}
