import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/official_ai_chat_template.dart';
import 'package:tsumoai_mobile/screens/ai_chat_template_admin_screen.dart';
import 'package:tsumoai_mobile/services/official_ai_chat_template_service.dart';

class _MemoryOfficialService extends OfficialAIChatTemplateService {
  var config = OfficialAIChatTemplateConfig(
    version: 2,
    items: OfficialAIChatTemplateService.defaults().items.take(3).toList(),
  );
  var publishes = 0;

  @override
  Future<OfficialAIChatTemplateConfig> load({bool refresh = true}) async =>
      config;

  @override
  Future<OfficialAIChatTemplateConfig> publish(
    List<OfficialAIChatTemplate> items,
  ) async {
    publishes++;
    config = OfficialAIChatTemplateConfig(
      version: config.version + 1,
      items: items,
    );
    return config;
  }
}

void main() {
  testWidgets('admin can disable a template on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _MemoryOfficialService();

    await tester.pumpWidget(
      MaterialApp(home: AIChatTemplateAdminScreen(service: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('公開バージョン 2'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(service.publishes, 1);
    expect(find.text('公開バージョン 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
