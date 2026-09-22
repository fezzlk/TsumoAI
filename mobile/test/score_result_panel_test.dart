import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/score_result.dart';
import 'package:tsumoai_mobile/widgets/score_result_panel.dart';

ScoreResponse response({required String winType}) => ScoreResponse.fromJson({
  'score_id': winType,
  'status': 'ok',
  'result': {
    'han': winType == 'tsumo' ? 3 : 2,
    'fu': 30,
    'fu_breakdown': [],
    'yaku': [
      {'name': winType == 'tsumo' ? '門前清自摸和' : '立直', 'han': 1},
    ],
    'yakuman': [],
    'dora': {'dora': 0, 'aka_dora': 0, 'ura_dora': 0},
    'point_label': winType == 'tsumo' ? '満貫' : '2000点',
    'points': {
      'ron': winType == 'ron' ? 2000 : 0,
      'tsumo_dealer_pay': winType == 'tsumo' ? 2000 : 0,
      'tsumo_non_dealer_pay': winType == 'tsumo' ? 1000 : 0,
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

Widget subject({ScoreResponse? tsumo, ScoreResponse? ron}) => MaterialApp(
  home: Scaffold(
    backgroundColor: Colors.black,
    body: ScoreResultPanel(tsumoResponse: tsumo, ronResponse: ron),
  ),
);

void main() {
  testWidgets('shows tsumo and ron together without asking for a choice', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(tsumo: response(winType: 'tsumo'), ron: response(winType: 'ron')),
    );

    expect(find.text('ツモの場合'), findsOneWidget);
    expect(find.text('ロンの場合'), findsOneWidget);
    expect(find.text('満貫'), findsOneWidget);
    expect(find.text('2000点'), findsOneWidget);
    expect(find.text('ツモ: 1000 / 2000点'), findsOneWidget);
    expect(find.text('ロン: 2000点'), findsOneWidget);
  });

  testWidgets('keeps the valid side when the other side does not score', (
    tester,
  ) async {
    await tester.pumpWidget(subject(tsumo: response(winType: 'tsumo')));

    expect(find.text('満貫'), findsOneWidget);
    expect(find.text('この条件では和了として成立しません'), findsOneWidget);
  });
}
