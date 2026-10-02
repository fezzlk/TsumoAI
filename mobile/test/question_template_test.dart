import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/question_template.dart';

void main() {
  test('sent message is saved with an automatic name', () {
    final now = DateTime.utc(2026, 9, 29);
    final items = QuestionTemplateCollection.saveMessage(
      items: const [],
      id: 'template-1',
      message: '  親リーチ中なら\n何を切る？  ',
      now: now,
    );

    expect(items.single.name, '親リーチ中なら 何を切る？');
    expect(items.single.body, '親リーチ中なら\n何を切る？');
  });

  test('same sent message is not duplicated', () {
    final now = DateTime.utc(2026, 9, 29);
    final initial = QuestionTemplateCollection.saveMessage(
      items: const [],
      id: 'template-1',
      message: '何を切る？',
      now: now,
    );
    final duplicate = QuestionTemplateCollection.saveMessage(
      items: initial,
      id: 'template-2',
      message: '  何を切る？  ',
      now: now,
    );

    expect(duplicate, same(initial));
    expect(duplicate, hasLength(1));
  });

  test('personal templates are limited to 20 active items', () {
    final now = DateTime.utc(2026, 9, 29);
    final items = List.generate(
      20,
      (index) => QuestionTemplate(
        id: '$index',
        name: '質問$index',
        body: '質問本文$index',
        createdAt: now,
        updatedAt: now,
      ),
    );

    expect(
      () => QuestionTemplateCollection.saveMessage(
        items: items,
        id: 'over-limit',
        message: '追加質問',
        now: now,
      ),
      throwsStateError,
    );
  });

  test('bodies the server would reject are refused before saving', () {
    final now = DateTime.utc(2026, 9, 29);
    final atLimit = '牌' * QuestionTemplate.maxBodyLength;

    expect(
      QuestionTemplateCollection.saveMessage(
        items: const [],
        id: 'at-limit',
        message: atLimit,
        now: now,
      ).single.body,
      atLimit,
    );
    expect(
      () => QuestionTemplateCollection.saveMessage(
        items: const [],
        id: 'too-long',
        message: '$atLimit牌',
        now: now,
      ),
      throwsA(isA<QuestionTemplateTooLongException>()),
    );
    expect(
      () => QuestionTemplate.validateLengths(
        name: '名' * (QuestionTemplate.maxNameLength + 1),
        body: '質問',
      ),
      throwsA(isA<QuestionTemplateTooLongException>()),
    );
  });
}
