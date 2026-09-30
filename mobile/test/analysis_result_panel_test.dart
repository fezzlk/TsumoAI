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

  testWidgets('call result groups candidates and opens deterministic details', (
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
            'possible_yaku': ['役牌 白'],
            'discards': [
              {
                'discard': 'E',
                'total_remaining': 4,
                'improving_tiles': [
                  {'tile': '6m', 'remaining': 4},
                ],
              },
            ],
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
      }),
    );

    expect(find.text('シャンテン数: 2'), findsOneWidget);
    expect(find.text('推奨'), findsOneWidget);
    expect(find.text('条件付き'), findsOneWidget);
    expect(find.text('見送り'), findsOneWidget);
    expect(find.text('チー'), findsOneWidget);
    expect(find.byKey(const ValueKey('analysis-call-3m-0')), findsOneWidget);
    expect(
      find.text('チーは上家から出た場合だけ可能です。役・守備・点数状況は含まない牌効率上の候補です。'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('analysis-call-candidate-0')));
    await tester.pumpAndSettle();

    expect(find.text('チーの詳細'), findsOneWidget);
    expect(find.text('向聴数: 2 → 1'), findsOneWidget);
    expect(find.text('鳴いた後に切る候補'), findsOneWidget);
    expect(find.text('受け入れ 4枚'), findsOneWidget);
    expect(find.text('成立可能役'), findsOneWidget);
    expect(find.text('役牌 白'), findsOneWidget);
    expect(find.text('上家から出た場合だけチーできます。'), findsOneWidget);
  });
}
