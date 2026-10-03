import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/ai_chat_message.dart';
import 'package:tsumoai_mobile/models/ai_usage_status.dart';
import 'package:tsumoai_mobile/models/question_template.dart';
import 'package:tsumoai_mobile/models/official_ai_chat_template.dart';
import 'package:tsumoai_mobile/services/api_client.dart';
import 'package:tsumoai_mobile/services/question_template_service.dart';
import 'package:tsumoai_mobile/services/official_ai_chat_template_service.dart';
import 'package:tsumoai_mobile/widgets/ai_chat_sheet.dart';

class _MemoryTemplateService extends QuestionTemplateService {
  final List<QuestionTemplate> items = [];
  var synchronizations = 0;

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

  @override
  Future<List<QuestionTemplate>> synchronize() async {
    synchronizations++;
    final synced = [
      for (final item in items) item.copyWith(pendingSync: false),
    ];
    items
      ..clear()
      ..addAll(synced);
    return synced;
  }
}

class _OfficialTemplates extends OfficialAIChatTemplateService {
  @override
  Future<OfficialAIChatTemplateConfig> load({bool refresh = true}) async =>
      OfficialAIChatTemplateService.defaults();
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
            officialTemplateService: _OfficialTemplates(),
            isSignedIn: () => true,
            onMessagesChanged: (messages) => changed = messages,
            sender:
                ({
                  required message,
                  required conversation,
                  required situationTags,
                }) async {
                  expect(message, '親リーチの状況です。何を切る？');
                  expect(conversation, isEmpty);
                  expect(situationTags, ['親リーチ']);
                  return '東を切るのがおすすめです。';
                },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('親リーチ'));
    await tester.tap(find.text('何を切る？'));
    await tester.tap(find.byTooltip('送信'));
    await tester.pumpAndSettle();

    expect(find.text('東を切るのがおすすめです。'), findsOneWidget);
    expect(changed.map((item) => item.role), ['user', 'assistant']);

    await tester.tap(find.text('テンプレートとして保存'));
    await tester.pumpAndSettle();

    expect(templates.items.single.body, '親リーチの状況です。何を切る？');
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
            officialTemplateService: _OfficialTemplates(),
            isSignedIn: () => true,
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

  testWidgets('shows pending template sync and retries in place', (
    tester,
  ) async {
    final templates = _MemoryTemplateService();
    final now = DateTime.utc(2026, 10, 1);
    templates.items.add(
      QuestionTemplate(
        id: 'pending',
        name: '未同期',
        body: '質問',
        createdAt: now,
        updatedAt: now,
        accountUid: 'user',
        pendingSync: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AIChatSheet(
            purpose: 'discard',
            tiles: const ['1m'],
            roundContext: const {},
            analysis: const {},
            templateService: templates,
            officialTemplateService: _OfficialTemplates(),
            isSignedIn: () => true,
            sender:
                ({
                  required message,
                  required conversation,
                  required situationTags,
                }) async => '回答',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('未同期のテンプレートがあります'), findsOneWidget);
    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();

    expect(templates.synchronizations, 1);
    expect(find.text('未同期のテンプレートがあります'), findsNothing);
  });

  testWidgets('keeps conversation visible and disables input at the limit', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AIChatSheet(
            purpose: 'discard',
            tiles: const ['1m'],
            roundContext: const {},
            analysis: const {},
            initialMessages: const [
              AIChatMessage(role: 'assistant', content: '前回の回答'),
            ],
            templateService: _MemoryTemplateService(),
            officialTemplateService: _OfficialTemplates(),
            isSignedIn: () => true,
            usageLoader: () async => AIUsageStatus(
              period: '2026-10',
              plan: 'free',
              includedLimit: 3,
              includedUsed: 3,
              bonusRemaining: 0,
              remaining: 0,
              resetsAt: DateTime(2026, 11, 1),
            ),
            sender:
                ({
                  required message,
                  required conversation,
                  required situationTags,
                }) async => throw StateError('must not send'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('前回の回答'), findsOneWidget);
    expect(find.textContaining('今月のAI相談枠を使い切りました'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).enabled,
      isFalse,
    );
    final sendButton = find.byKey(const ValueKey('ai-chat-send'));
    expect(tester.widget<FilledButton>(sendButton).onPressed, isNull);
  });

  testWidgets('opens with a selected judgment focus and editable draft', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AIChatSheet(
            purpose: 'discard',
            tiles: const ['1m'],
            roundContext: const {},
            analysis: const {'discards': []},
            initialSituationTags: const ['守備考慮'],
            initialDraft: '守備考慮で何を切る？',
            templateService: _MemoryTemplateService(),
            officialTemplateService: _OfficialTemplates(),
            isSignedIn: () => true,
            sender:
                ({
                  required message,
                  required conversation,
                  required situationTags,
                }) async => '回答',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('守備考慮'), findsOneWidget);
    final input = tester.widget<TextField>(find.byType(TextField).last);
    expect(input.controller?.text, '守備考慮で何を切る？');
  });

  testWidgets('signed-out users are asked to log in before sending', (
    tester,
  ) async {
    var signIns = 0;
    var sends = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AIChatSheet(
            purpose: 'discard',
            tiles: const ['1m'],
            roundContext: const {},
            analysis: const {},
            initialMessages: const [
              AIChatMessage(role: 'assistant', content: '前回の回答'),
            ],
            templateService: _MemoryTemplateService(),
            officialTemplateService: _OfficialTemplates(),
            isSignedIn: () => false,
            signIn: () async => signIns++,
            sender:
                ({
                  required message,
                  required conversation,
                  required situationTags,
                }) async {
                  sends++;
                  return '回答';
                },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('前回の回答'), findsOneWidget);
    expect(find.textContaining('AI相談はログインすると利用できます'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).enabled,
      isFalse,
    );

    await tester.tap(find.text('Googleでログイン'));
    await tester.pumpAndSettle();

    expect(signIns, 1);
    expect(find.textContaining('AI相談はログインすると利用できます'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).enabled,
      isTrue,
    );
    expect(sends, 0);
  });

  testWidgets('limits the question to the length the server accepts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AIChatSheet(
            purpose: 'discard',
            tiles: const ['1m'],
            roundContext: const {},
            analysis: const {},
            templateService: _MemoryTemplateService(),
            officialTemplateService: _OfficialTemplates(),
            isSignedIn: () => true,
            sender:
                ({
                  required message,
                  required conversation,
                  required situationTags,
                }) async => '回答',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField).last).maxLength,
      ApiClient.aiMessageMaxLength,
    );
  });
}
