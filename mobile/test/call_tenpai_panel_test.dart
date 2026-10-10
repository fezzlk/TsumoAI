import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/widgets/analysis_result_panel.dart';

Widget panel(Map<String, dynamic> result) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(child: AnalysisResultPanel(result: result)),
  ),
);

void main() {
  testWidgets(
    'current winning tiles are shown as ron and yakuless waits stay visible',
    (tester) async {
      await tester.pumpWidget(
        panel({
          'current_shanten': 0,
          'current_waits': [
            {
              'tile': '3s',
              'remaining': 3,
              'ron_status': 'available',
              'yaku': ['三色同順'],
            },
            {'tile': '6s', 'remaining': 4, 'ron_status': 'no_yaku', 'yaku': []},
          ],
          'calls': [],
        }),
      );
      expect(find.text('現在はテンパイ'), findsOneWidget);
      expect(find.text('ロン可能'), findsOneWidget);
      expect(find.text('役なし（ロン不可）'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('call-current-wait-3s')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('call-current-wait-6s')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hatsu pon that adds yaku while keeping tenpai is recommended', (
    tester,
  ) async {
    await tester.pumpWidget(
      panel({
        'current_shanten': 0,
        'current_waits': [
          {'tile': '2p', 'remaining': 4, 'ron_status': 'no_yaku'},
        ],
        'calls': [
          {
            'call_tile': 'F',
            'call_type': 'pon',
            'consumed_tiles': ['F', 'F'],
            'shanten_after_call': 0,
            'recommendation': 'keeps',
            'tenpai_effect': 'adds_yaku',
            'outlook': {'status': 'available', 'summary': '役牌 發で和了可能'},
          },
        ],
      }),
    );
    expect(find.text('推奨'), findsOneWidget);
    expect(find.text('テンパイ維持'), findsOneWidget);
    expect(find.textContaining('役なしの待ちからロンできる待ち'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a yakuless call shows nearby yaku and the required hand change',
    (tester) async {
      await tester.pumpWidget(
        panel({
          'current_shanten': 1,
          'calls': [
            {
              'call_tile': '1m',
              'call_type': 'chi',
              'consumed_tiles': ['2m', '3m'],
              'shanten_after_call': 0,
              'recommendation': 'improves',
              'outlook': {
                'status': 'no_yaku',
                'summary': '今の待ちでは役なし。',
                'nearby_yaku': [
                  {'name': '役牌 發', 'han': 1, 'condition': '發をポンし、別の雀頭を作ります。'},
                ],
              },
            },
          ],
        }),
      );
      expect(find.text('見送り'), findsOneWidget);
      expect(find.text('手変わりで狙う近い役（未成立）'), findsOneWidget);
      expect(find.textContaining('發をポンし、別の雀頭を作ります'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
