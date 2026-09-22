import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/widgets/analysis_result_panel.dart';

Widget subject(Map<String, dynamic> result) => MaterialApp(
  home: Scaffold(
    backgroundColor: Colors.black,
    body: AnalysisResultPanel(result: result),
  ),
);

void main() {
  testWidgets('tenpai result renders waits as tile illustrations', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject({
        'shanten': 0,
        'improving_tiles': [
          {'tile': '2p', 'remaining': 3},
          {'tile': '5p', 'remaining': 2},
        ],
      }),
    );

    expect(find.text('シャンテン数: 0'), findsOneWidget);
    expect(find.text('待ち牌'), findsOneWidget);
    expect(find.byKey(const ValueKey('analysis-wait-2p-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('analysis-wait-5p-1')), findsOneWidget);
    expect(find.text('残り3枚'), findsOneWidget);
  });

  testWidgets(
    'discard result renders discard and improving tile illustrations',
    (tester) async {
      await tester.pumpWidget(
        subject({
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
          ],
        }),
      );

      expect(
        find.byKey(const ValueKey('analysis-discard-C-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('analysis-discard-0-wait-2p-0')),
        findsOneWidget,
      );
      expect(find.text('0シャンテン'), findsOneWidget);
      expect(find.text('有効牌 5枚'), findsOneWidget);
    },
  );

  testWidgets('call result renders possible tile and consumed tiles', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject({
        'current_shanten': 2,
        'calls': [
          {
            'call_tile': '3m',
            'call_type': 'chi',
            'consumed_tiles': ['1m', '2m'],
            'shanten_after_call': 1,
            'recommendation': 'improves',
            'discards': [
              {'discard': 'E'},
            ],
          },
        ],
      }),
    );

    expect(find.text('鳴ける可能性'), findsOneWidget);
    expect(find.text('チー'), findsOneWidget);
    expect(find.text('シャンテン数が進む'), findsOneWidget);
    expect(find.byKey(const ValueKey('analysis-call-3m-0')), findsOneWidget);
    expect(find.text('鳴いた後の候補: E'), findsOneWidget);
  });
}
