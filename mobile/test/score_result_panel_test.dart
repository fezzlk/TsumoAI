import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/score_result.dart';
import 'package:tsumoai_mobile/models/score_request.dart';
import 'package:tsumoai_mobile/widgets/score_result_panel.dart';

ScoreResponse response({
  required String winType,
  int akaDora = 0,
  int uraDora = 0,
  bool ippatsu = false,
  int honbaBonus = 0,
  int kyotakuBonus = 0,
}) => ScoreResponse.fromJson({
  'score_id': winType,
  'status': 'ok',
  'result': {
    'han': winType == 'tsumo' ? 3 : 2,
    'fu': 30,
    'fu_breakdown': [],
    'yaku': [
      {'name': winType == 'tsumo' ? '門前清自摸和' : '立直', 'han': 1},
      if (ippatsu) {'name': '一発', 'han': 1},
    ],
    'yakuman': [],
    'dora': {'dora': 0, 'aka_dora': akaDora, 'ura_dora': uraDora},
    'point_label': winType == 'tsumo' ? '満貫' : '2000点',
    'points': {
      'ron': winType == 'ron' ? 2000 : 0,
      'tsumo_dealer_pay': winType == 'tsumo' ? 2000 : 0,
      'tsumo_non_dealer_pay': winType == 'tsumo' ? 1000 : 0,
    },
    'payments': {
      'hand_points_received': 0,
      'hand_points_with_honba': 0,
      'honba_bonus': honbaBonus,
      'kyotaku_bonus': kyotakuBonus,
      'total_received':
          (winType == 'tsumo' ? 4000 : 2000) + honbaBonus + kyotakuBonus,
    },
    'explanation': [],
  },
  'warnings': [],
});

Widget subject({
  ScoreResponse? tsumo,
  ScoreResponse? ron,
  String? ronNote,
  MahjongRuleSettings settings = const MahjongRuleSettings(),
  bool isOpenHand = false,
}) => MaterialApp(
  home: Scaffold(
    backgroundColor: Colors.black,
    body: ScoreResultPanel(
      tsumoResponse: tsumo,
      ronResponse: ron,
      ronNote: ronNote,
      ruleSettings: settings,
      isOpenHand: isOpenHand,
    ),
  ),
);

void main() {
  testWidgets('shows tsumo and ron together without asking for a choice', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(
        tsumo: response(winType: 'tsumo'),
        ron: response(winType: 'ron'),
      ),
    );

    expect(find.text('ツモの場合'), findsOneWidget);
    expect(find.text('ロンの場合'), findsOneWidget);
    expect(find.text('満貫'), findsOneWidget);
    expect(find.text('1,000 / 2,000'), findsOneWidget);
    expect(find.text('子の支払い / 親の支払い'), findsOneWidget);
    expect(find.text('2,000'), findsOneWidget);
    expect(find.text('放銃者の支払い'), findsOneWidget);
  });

  testWidgets('keeps the valid side when the other side does not score', (
    tester,
  ) async {
    await tester.pumpWidget(subject(tsumo: response(winType: 'tsumo')));

    expect(find.text('満貫'), findsOneWidget);
    expect(find.text('この条件では和了として成立しません'), findsOneWidget);
  });

  testWidgets('a refused side says why (ロン with no 役)', (tester) async {
    await tester.pumpWidget(
      subject(
        tsumo: response(winType: 'tsumo'),
        ronNote: '役なしのため和了できません',
      ),
    );

    expect(find.text('満貫'), findsOneWidget);
    expect(find.text('役なしのため和了できません'), findsOneWidget);
    expect(find.text('この条件では和了として成立しません'), findsNothing);
  });

  testWidgets('adds each red tile and the all-star bonus to chips', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(
        tsumo: response(
          winType: 'tsumo',
          akaDora: 3,
          uraDora: 1,
          ippatsu: true,
        ),
        settings: const MahjongRuleSettings(chipsEnabled: true),
      ),
    );

    expect(find.text('チップ: 各7枚・合計21枚（7チップ点 / 素点7000点相当）'), findsOneWidget);
  });

  testWidgets('disables chips for an open hand when configured', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(
        ron: response(winType: 'ron', akaDora: 1),
        settings: const MahjongRuleSettings(
          chipsEnabled: true,
          openHandChipsEnabled: false,
        ),
        isOpenHand: true,
      ),
    );

    expect(find.text('チップ: なし（副露あり）'), findsOneWidget);
  });

  testWidgets('adds 本場 to what each payer hands over', (tester) async {
    await tester.pumpWidget(
      subject(
        tsumo: response(winType: 'tsumo', honbaBonus: 600),
        ron: response(winType: 'ron', honbaBonus: 600),
      ),
    );

    expect(find.text('1,200 / 2,200'), findsOneWidget);
    expect(find.text('子の支払い / 親の支払い（本場 +200込み）'), findsOneWidget);
    expect(find.text('2,600'), findsOneWidget);
    expect(find.text('放銃者の支払い（本場 +600込み）'), findsOneWidget);
  });

  testWidgets('splits 三人麻雀 tsumo 本場 across two payers', (tester) async {
    await tester.pumpWidget(
      subject(
        tsumo: response(winType: 'tsumo', honbaBonus: 200),
        settings: const MahjongRuleSettings(rules: RuleSet(variant: 'sanma')),
      ),
    );

    expect(find.text('1,100 / 2,100'), findsOneWidget);
    expect(find.text('子1人 / 親1人の支払い（本場 +100込み）'), findsOneWidget);
  });

  testWidgets('shows 供託 and the total the winner receives', (tester) async {
    await tester.pumpWidget(
      subject(
        ron: response(winType: 'ron', honbaBonus: 300, kyotakuBonus: 1000),
      ),
    );

    expect(find.text('2,300'), findsOneWidget);
    expect(find.text('供託 +1,000・受け取り合計 3,300'), findsOneWidget);
  });
}
