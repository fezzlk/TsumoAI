import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/main.dart';
import 'package:tsumoai_mobile/models/scan_purpose.dart';
import 'package:tsumoai_mobile/screens/scan_screen.dart';
import 'package:tsumoai_mobile/screens/history_screen.dart';
import 'package:tsumoai_mobile/services/history_service.dart';
import 'package:tsumoai_mobile/models/history_entry.dart';

class _FakeHistoryService extends HistoryService {
  @override
  Future<List<HistoryEntry>> loadLocal() async => [];
}

void main() {
  testWidgets('home exposes the primary scan purposes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TsumoAIApp());

    expect(find.text('点数計算'), findsOneWidget);
    expect(find.text('待ち確認'), findsOneWidget);
    expect(find.text('AI相談　何を切る？・鳴くべき？'), findsOneWidget);
    expect(find.text('ログインしていません'), findsOneWidget);
  });

  testWidgets('wait purpose opens scan with a 13-tile default', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TsumoAIApp());

    await tester.tap(find.text('待ち確認'));
    await tester.pumpAndSettle();

    final scan = tester.widget<ScanScreen>(find.byType(ScanScreen));
    expect(scan.purpose, ScanPurpose.wait);
    expect(scan.purpose.defaultTileCount, 13);
  });

  testWidgets('AI consultation distinguishes discard and call advice', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TsumoAIApp());

    await tester.tap(find.text('AI相談　何を切る？・鳴くべき？'));
    await tester.pumpAndSettle();
    expect(find.text('何を切る？'), findsOneWidget);
    expect(find.text('鳴くべき？'), findsOneWidget);
  });

  testWidgets('history is available without login', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HistoryScreen(service: _FakeHistoryService())),
    );
    await tester.pumpAndSettle();

    expect(find.text('端末内履歴'), findsOneWidget);
    expect(find.text('履歴はまだありません'), findsOneWidget);
    expect(find.text('ログイン'), findsOneWidget);
  });

  test('purpose defaults match the expected hand shape', () {
    expect(ScanPurpose.score.defaultTileCount, 14);
    expect(ScanPurpose.discard.defaultTileCount, 14);
    expect(ScanPurpose.wait.defaultTileCount, 13);
    expect(ScanPurpose.callAdvice.defaultTileCount, 13);
  });
}
