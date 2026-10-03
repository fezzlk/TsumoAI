import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/ai_usage_status.dart';
import 'package:tsumoai_mobile/screens/ai_usage_screen.dart';

void main() {
  testWidgets('shows monthly AI usage and reset date', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AIUsageScreen(
          loader: () async => AIUsageStatus(
            period: '2026-10',
            plan: 'free',
            includedLimit: 3,
            includedUsed: 1,
            bonusRemaining: 0,
            remaining: 2,
            resetsAt: DateTime(2026, 11, 1),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('あと2回'), findsOneWidget);
    expect(find.text('1 / 3 回利用'), findsOneWidget);
    expect(find.text('11月1日'), findsOneWidget);
  });
}
