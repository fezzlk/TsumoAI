import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/ai_chat_message.dart';
import 'package:tsumoai_mobile/models/question_template.dart';
import 'package:tsumoai_mobile/services/question_template_service.dart';
import 'package:tsumoai_mobile/widgets/ai_chat_sheet.dart';

class _MemoryTemplateService extends QuestionTemplateService {
  final List<QuestionTemplate> items = [];

  @override
  Future<List<QuestionTemplate>> loadLocal() async => [...items];

  @override
  Future<QuestionTemplate> saveSentMessage(String message) async {
    final now = DateTime.utc(2026, 10, 1);
    final item = QuestionTemplate(
      id: 'saved-${items.length}',
      name: QuestionTemplate.automaticName(message),
      body: message.trim(),
      createdAt: now,
      updatedAt: now,
    );
    items.add(item);
    return item;
  }
}

void main() {
  testWidgets('sends a contextual question and saves the sent text', (
    tester,
  ) async {
    final templates = _MemoryTemplateService();
    List<AIChatMessage> changed = [];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AIChatSheet(
            purpose: 'discard',
            tiles: const ['1m', '2m', '3m'],
            roundContext: const {'round_wind': 'E'},
            analysis: const {'discards': []},
            templateService: templates,
            onMessagesChanged: (messages) => changed = messages,
            sender:
                ({
                  required message,
                  required conversation,
                  required situationTags,
                }) async {
                  expect(message, '何を切る？');
                  expect(conversation, isEmpty);
                  return '東を切るのがおすすめです。';
                },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('何を切る？'));
    await tester.tap(find.byTooltip('送信'));
    await tester.pumpAndSettle();

    expect(find.text('東を切るのがおすすめです。'), findsOneWidget);
    expect(changed.map((item) => item.role), ['user', 'assistant']);

    await tester.tap(find.text('テンプレートとして保存'));
    await tester.pumpAndSettle();

    expect(templates.items.single.body, '何を切る？');
    expect(find.text('保存済み'), findsOneWidget);
  });

  testWidgets('failed send keeps the draft and removes the pending message', (
    tester,
  ) async {
    List<AIChatMessage> changed = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AIChatSheet(
            purpose: 'call_advice',
            tiles: const ['1m', '2m', '3m'],
            roundContext: const {},
            analysis: const {'calls': []},
            templateService: _MemoryTemplateService(),
            onMessagesChanged: (messages) => changed = messages,
            sender:
                ({
                  required message,
                  required conversation,
                  required situationTags,
                }) async => throw Exception('offline'),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('鳴くべき？'));
    await tester.tap(find.byTooltip('送信'));
    await tester.pumpAndSettle();

    expect(find.textContaining('回答を取得できませんでした'), findsOneWidget);
    expect(find.widgetWithText(TextField, '鳴くべき？'), findsOneWidget);
    expect(changed, isEmpty);
  });
}
