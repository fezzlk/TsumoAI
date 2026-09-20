import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:tsumoai_mobile/main.dart';
import 'package:tsumoai_mobile/screens/scan_screen.dart';

void main() {
  testWidgets('App builds smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TsumoAIApp());
    expect(find.text('TsumoAI'), findsOneWidget);
  });

  testWidgets('home scan settings persist after returning from scan', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TsumoAIApp());

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(
      tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>).first,
      ).selected,
      {'E'},
    );

    await tester.tap(find.text('南'));
    await tester.tap(find.byType(Switch));
    await tester.pump();

    await tester.tap(find.text('牌スキャン'));
    await tester.pumpAndSettle();
    final scan = tester.widget<ScanScreen>(find.byType(ScanScreen));
    expect(scan.autoClassify, isTrue);
    expect(scan.initialRoundWind, 'S');

    scan.onRoundWindChanged?.call('W');
    await tester.pump();
    Navigator.of(tester.element(find.byType(ScanScreen))).pop();
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(
      tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>).first,
      ).selected,
      {'W'},
    );
  });
}
