import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/widgets/analysis_result_panel.dart';

Widget subject(
  Map<String, dynamic> result, {
  ValueChanged<Map<String, dynamic>>? onAskAiAboutCall,
  ValueChanged<String>? onAskAiWithDiscardFocus,
}) => MaterialApp(
  home: Scaffold(
    backgroundColor: Colors.black,
    body: AnalysisResultPanel(
      result: result,
      onAskAiAboutCall: onAskAiAboutCall,
      onAskAiWithDiscardFocus: onAskAiWithDiscardFocus,
    ),
  ),
);

void main() {
  testWidgets(
    'same called tile and action share one row and preserve distinct shapes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic> variant(
        List<String> consumed,
        String status,
        String summary,
        int points,
      ) => {
        'call_tile': '3m',
        'call_type': 'chi',
        'consumed_tiles': consumed,
        'shanten_after_call': 0,
        'recommendation': 'improves',
        'outlook': {
          'status': status,
          'summary': summary,
          if (points > 0)
            'score_estimate': {
              'min_points': points,
              'max_points': points,
              'basis': '子のロン',
            },
        },
      };
      final losing = variant(['1m', '2m'], 'no_yaku', '123の形は役なし', 0);
      final winning = variant(['2m', '4m'], 'available', '234の形は役あり', 1000);
      final conditional = variant(
        ['4m', '5m'],
        'conditional',
        '345の形は条件付き',
        2000,
      );
      Map<String, dynamic>? selected;
      final result = {
        'current_shanten': 1,
        'calls': [
          losing,
          winning,
          conditional,
          {
            ...losing,
            'consumed_tiles': ['2m', '1m'],
          },
        ],
      };
      await tester.pumpWidget(
        subject(result, onAskAiAboutCall: (item) => selected = item),
      );

      expect(find.text('チー'), findsOneWidget);
      expect(find.text('使う手牌は3通り（詳細で比較）'), findsOneWidget);
      expect(find.text('234の形は役あり'), findsOneWidget);
      expect(find.text('推奨'), findsOneWidget);
      expect(find.text('見送り'), findsNothing);
      expect(find.text('打点の目安: 1000点（ロン）'), findsOneWidget);
      expect(
        result['calls'],
        hasLength(4),
      ); // Rendering never changes response/history data.

      await tester.tap(find.byKey(const ValueKey('analysis-call-candidate-0')));
      await tester.pumpAndSettle();
      expect(find.text('使う手牌を選択（3通り）'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(3));
      await tester.tap(find.byKey(const ValueKey('analysis-call-variant-1')));
      await tester.pumpAndSettle();
      expect(find.text('123の形は役なし'), findsOneWidget);
      expect(find.text('打点: 未算定'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('analysis-call-variant-2')));
      await tester.pumpAndSettle();
      expect(find.text('345の形は条件付き'), findsOneWidget);
      expect(find.text('条件成立時の参考打点: 2000点（ロン）'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('この候補をAIに質問'));
      await tester.pumpAndSettle();
      expect(selected, equals(conditional));
    },
  );

  testWidgets(
    'identical pon entries collapse but chi of same tile stays separate',
    (tester) async {
      final pon = {
        'call_tile': '3m',
        'call_type': 'pon',
        'consumed_tiles': ['3m', '3m'],
        'shanten_after_call': 1,
        'recommendation': 'keeps',
      };
      await tester.pumpWidget(
        subject({
          'current_shanten': 1,
          'calls': [
            pon,
            {...pon},
            {
              ...pon,
              'call_type': 'chi',
              'consumed_tiles': ['1m', '2m'],
            },
          ],
        }),
      );
      expect(find.text('ポン'), findsOneWidget);
      expect(find.text('チー'), findsOneWidget);
      expect(find.textContaining('通り（詳細で比較）'), findsNothing);
    },
  );

  testWidgets('tsumo-only outlook labels total and payment shares', (
    tester,
  ) async {
    final outlook = {
      'status': 'available',
      'summary': '役のある和了形あり',
      'warnings': ['ツモでのみ役が付く待ちがあります。'],
      'score_estimate': {
        'min_points': 2700,
        'max_points': 2700,
        'win_type': 'tsumo',
        'basis': '子のツモ合計',
      },
      'winning_tiles': [
        {
          'tile': '7s',
          'win_type': 'tsumo',
          'yaku': ['三暗刻'],
          'han': 2,
          'fu': 40,
          'tsumo_dealer_pay': 1300,
          'tsumo_non_dealer_pay': 700,
        },
      ],
    };
    await tester.pumpWidget(
      subject({
        'current_shanten': 1,
        'calls': [
          {
            'call_tile': '3m',
            'call_type': 'chi',
            'consumed_tiles': ['1m', '2m'],
            'shanten_after_call': 0,
            'recommendation': 'improves',
            'outlook': outlook,
          },
        ],
      }),
    );
    expect(find.text('打点の目安: 2700点（ツモ合計）'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('analysis-call-candidate-0')));
    await tester.pumpAndSettle();
    expect(find.text('ツモ: 三暗刻 2翻40符 / 子700・親1300点払い'), findsOneWidget);
    expect(find.textContaining(' / 0点'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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

    expect(find.text('テンパイ'), findsOneWidget);
    expect(find.text('待ち牌は2種類'), findsOneWidget);
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

  testWidgets('a tenpai discard result says so and keeps the candidates', (
    tester,
  ) async {
    Map<String, Object> option(String tile, int shanten) => {
      'discard': tile,
      'shanten': shanten,
      'total_remaining': 4,
      'improving_tiles': <Object>[],
    };
    await tester.pumpWidget(
      subject({
        'shanten': 0,
        'hand_shanten': 0,
        'discards': [option('9s', 0), option('E', 0), option('1m', 1)],
      }),
    );

    expect(find.text('テンパイ'), findsOneWidget);
    expect(find.textContaining('すでに聴牌しています'), findsOneWidget);
    expect(find.textContaining('九索・東を切ると聴牌'), findsOneWidget);
    expect(find.text('打牌候補 ベスト3'), findsOneWidget);
  });

  testWidgets('a complete hand is called 和了形', (tester) async {
    await tester.pumpWidget(
      subject({
        'shanten': 0,
        'hand_shanten': -1,
        'discards': [
          {'discard': '5p', 'shanten': 0, 'improving_tiles': <Object>[]},
        ],
      }),
    );

    expect(find.textContaining('和了形です'), findsOneWidget);
  });

  testWidgets('no tenpai notice before tenpai', (tester) async {
    await tester.pumpWidget(
      subject({
        'shanten': 1,
        'discards': [
          {'discard': '1m', 'shanten': 1, 'improving_tiles': <Object>[]},
        ],
      }),
    );

    expect(find.textContaining('聴牌しています'), findsNothing);
    expect(find.text('1シャンテン'), findsWidgets);
  });

  testWidgets('discard result shows only the tile-efficiency top three', (
    tester,
  ) async {
    Map<String, Object> option(String tile, int remaining) => {
      'discard': tile,
      'shanten': 1,
      'total_remaining': remaining,
      'improving_tiles': <Object>[],
    };
    await tester.pumpWidget(
      subject({
        'shanten': 1,
        'discards': [
          option('1m', 12),
          option('2m', 10),
          option('3m', 8),
          option('4m', 6),
        ],
      }),
    );

    expect(find.text('打牌候補 ベスト3'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byKey(const ValueKey('analysis-discard-4m-3')), findsNothing);
  });

  testWidgets(
    'discard focus opens AI consultation without relabeling results',
    (tester) async {
      String? selectedFocus;
      await tester.pumpWidget(
        subject({
          'shanten': 1,
          'discards': [
            {
              'discard': '1m',
              'shanten': 1,
              'total_remaining': 12,
              'improving_tiles': <Object>[],
            },
          ],
        }, onAskAiWithDiscardFocus: (focus) => selectedFocus = focus),
      );

      expect(find.text('打牌候補 ベスト3'), findsOneWidget);
      expect(find.text('別の判断基準でAIに相談'), findsOneWidget);
      await tester.tap(find.text('守備考慮'));

      expect(selectedFocus, '守備考慮');
    },
  );

  testWidgets('call result groups candidates and opens deterministic details', (
    tester,
  ) async {
    Map<String, dynamic>? selectedForAi;
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
      }, onAskAiAboutCall: (candidate) => selectedForAi = candidate),
    );

    expect(find.text('2 → 1シャンテン'), findsOneWidget);
    expect(find.text('推奨'), findsOneWidget);
    expect(find.text('条件付き'), findsOneWidget);
    expect(find.text('見送り'), findsOneWidget);
    expect(find.text('チー'), findsOneWidget);
    expect(find.byKey(const ValueKey('analysis-call-3m-0')), findsOneWidget);
    expect(
      find.text(
        'チーは上家から出た場合だけ可能です。役と打点は表示した条件での見通しです。フリテン・喰い替え・他家の捨て牌・守備は判定していません。',
      ),
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
    expect(find.text('この候補をAIに質問'), findsOneWidget);

    await tester.tap(find.text('この候補をAIに質問'));
    await tester.pumpAndSettle();

    expect(selectedForAi?['call_tile'], '3m');
    expect(find.text('チーの詳細'), findsNothing);
  });

  testWidgets(
    'yakuless improvement is not recommended and explains lost tanyao',
    (tester) async {
      await tester.pumpWidget(
        subject({
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
                'warnings': ['副露に1・9・字牌が固定されるため、タンヤオは成立しません。'],
              },
            },
          ],
        }),
      );
      expect(find.text('見送り'), findsOneWidget);
      expect(find.text('推奨'), findsNothing);
      expect(find.text('今の待ちでは役なし。'), findsOneWidget);
      expect(find.textContaining('タンヤオは成立しません'), findsOneWidget);
      expect(find.text('打点: 未算定'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('今の待ちでは役なし。')).dy,
        lessThan(tester.getTopLeft(find.text('1 → 0シャンテン')).dy),
      );
    },
  );

  testWidgets(
    'prospective sanshoku shows conditional points and requirements',
    (tester) async {
      final outlook = {
        'status': 'conditional',
        'summary': '役を作る条件あり',
        'yaku': [
          {'name': '三色同順', 'han': 1, 'condition': '3色で123をそろえる。鳴くと2翻→1翻。'},
        ],
        'score_estimate': {
          'min_points': 1000,
          'max_points': 1300,
          'basis': '子のロン・30〜40符・ドラなしの参考値',
        },
      };
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
              'outlook': outlook,
            },
          ],
        }),
      );
      expect(find.text('条件付き'), findsOneWidget);
      expect(find.text('推奨'), findsNothing);
      expect(find.text('狙える役: 三色同順 1翻'), findsOneWidget);
      expect(find.text('条件成立時の参考打点: 1000〜1300点（ロン）'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('analysis-call-candidate-0')));
      await tester.pumpAndSettle();
      expect(find.textContaining('3色で123をそろえる'), findsOneWidget);
      expect(find.text('子のロン・30〜40符・ドラなしの参考値'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'discard details distinguish winning and yakuless waits on narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final outlook = {
        'status': 'available',
        'summary': '役のある和了形あり',
        'score_estimate': {
          'min_points': 1000,
          'max_points': 1000,
          'basis': '子のロン・ドラ込み',
        },
      };
      await tester.pumpWidget(
        subject({
          'current_shanten': 1,
          'calls': [
            {
              'call_tile': '3m',
              'call_type': 'chi',
              'consumed_tiles': ['1m', '2m'],
              'shanten_after_call': 0,
              'recommendation': 'improves',
              'outlook': outlook,
              'discards': [
                {
                  'discard': 'E',
                  'total_remaining': 7,
                  'call_outlook': {
                    ...outlook,
                    'winning_tiles': [
                      {
                        'tile': '3s',
                        'yaku': ['三色同順'],
                        'han': 1,
                        'fu': 30,
                        'ron_points': 1000,
                      },
                    ],
                    'no_yaku_tiles': ['6s'],
                  },
                },
              ],
            },
          ],
        }),
      );
      await tester.tap(find.byKey(const ValueKey('analysis-call-candidate-0')));
      await tester.pumpAndSettle();
      expect(find.text('役が付く待ち'), findsOneWidget);
      expect(find.text('ロン: 三色同順 1翻30符 / 1000点'), findsOneWidget);
      expect(find.text('この待ちは役なし'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
