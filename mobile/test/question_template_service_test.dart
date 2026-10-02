import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/services/question_template_service.dart';

void main() {
  test('reports a corrupt local template file without throwing', () async {
    final directory = await Directory.systemTemp.createTemp(
      'question-template-',
    );
    addTearDown(() => directory.delete(recursive: true));
    await File(
      '${directory.path}/question_templates.json',
    ).writeAsString('{not-json');
    final service = QuestionTemplateService(
      directoryProvider: () async => directory,
    );

    final templates = await service.loadLocal();

    expect(templates, isEmpty);
    expect(service.lastLoadFailed, isTrue);
  });
}
