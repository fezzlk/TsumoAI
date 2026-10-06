@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/services/local_document.dart';
import 'package:tsumoai_mobile/config.dart';
import 'package:tsumoai_mobile/services/history_service.dart';
import 'package:tsumoai_mobile/services/question_template_service.dart';
import 'package:tsumoai_mobile/services/rule_settings_service.dart';
import 'package:tsumoai_mobile/services/app_preferences.dart';
import 'package:tsumoai_mobile/models/history_entry.dart';
import 'package:web/web.dart' as web;

void main() {
  tearDown(() => web.window.localStorage.clear());
  test('anonymous history survives service recreation', () async {
    final now = DateTime.now().toUtc();
    await HistoryService().save(
      HistoryEntry(
        id: HistoryService.createId(),
        createdAt: now,
        updatedAt: now,
        purpose: 'score',
        title: 'Web確認',
        summary: '1000点',
        details: const {},
      ),
    );
    expect((await HistoryService().loadLocal()).single.title, 'Web確認');
    expect(
      (await HistoryService(
        currentUidProvider: () => 'another-account',
      ).loadLocal()).single.title,
      'Web確認',
    );
  });
  test('documents persist across store instances', () async {
    final directory = await getApplicationSupportDirectory();
    final path = '${directory.path}/test.json';
    await LocalDocument(path).writeAsString('{"value":42}');
    expect(await LocalDocument(path).exists(), isTrue);
    expect(await LocalDocument(path).readAsString(), '{"value":42}');
  });
  test('web uses its serving origin unless an API override is selected', () {
    AppConfig.setEnvironment(Environment.production);
    expect(AppConfig.apiBaseUrl, Uri.base.origin);
    AppConfig.setApiBaseUrl('https://example.invalid/');
    expect(AppConfig.apiBaseUrl, 'https://example.invalid');
    AppConfig.setEnvironment(Environment.production);
  });
  test(
    'preferences and rule defaults do not require a native filesystem',
    () async {
      await AppPreferences.setShowTrainingDataActions(true);
      expect(await AppPreferences.showTrainingDataActions(), isTrue);
      expect(await RuleSettingsService().loadLocal(), isNotNull);
      expect(await QuestionTemplateService().loadLocal(), isEmpty);
    },
  );
}
