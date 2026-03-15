import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/main.dart';

void main() {
  testWidgets('App builds smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TsumoAIApp());
    expect(find.text('TsumoAI'), findsOneWidget);
  });
}
