import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/official_ai_chat_template.dart';
import 'auth_service.dart';

class OfficialAIChatTemplateService {
  OfficialAIChatTemplateService({
    Dio? dio,
    Future<Directory> Function()? directoryProvider,
  }) : _dio = dio ?? Dio(),
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const _fileName = 'official_ai_chat_templates.json';
  final Dio _dio;
  final Future<Directory> Function() _directoryProvider;

  Future<File> _file() async =>
      File('${(await _directoryProvider()).path}/$_fileName');

  Future<OfficialAIChatTemplateConfig> load({bool refresh = true}) async {
    final cached = await _loadCached();
    if (!refresh) return cached;
    try {
      final response = await _dio.get(
        '${AppConfig.apiBaseUrl}/api/v1/ai-chat/templates',
      );
      final remote = OfficialAIChatTemplateConfig.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
      if (remote.items.isEmpty) return cached;
      await _write(remote);
      return remote;
    } catch (_) {
      return cached;
    }
  }

  Future<OfficialAIChatTemplateConfig> publish(
    List<OfficialAIChatTemplate> items,
  ) async {
    final token = await AuthService.idToken(interactive: true);
    final response = await _dio.put(
      '${AppConfig.apiBaseUrl}/api/v1/ai-chat/templates',
      data: {
        'items': items.map((item) => item.toJson()).toList(growable: false),
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final config = OfficialAIChatTemplateConfig.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
    await _write(config);
    return config;
  }

  Future<OfficialAIChatTemplateConfig> _loadCached() async {
    try {
      final file = await _file();
      if (!await file.exists()) return defaults();
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return defaults();
      final config = OfficialAIChatTemplateConfig.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      return config.items.isEmpty ? defaults() : config;
    } catch (_) {
      return defaults();
    }
  }

  Future<void> _write(OfficialAIChatTemplateConfig config) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(config.toJson()), flush: true);
  }

  static OfficialAIChatTemplateConfig defaults() =>
      OfficialAIChatTemplateConfig(
        version: 1,
        items: [
          for (var i = 0; i < _defaultSituations.length; i++)
            OfficialAIChatTemplate(
              id: 'situation-$i',
              kind: 'situation',
              purpose: 'all',
              label: _defaultSituations[i],
              body: _defaultSituations[i],
              enabled: true,
              sortOrder: i,
            ),
          for (var i = 0; i < _defaultDiscardQuestions.length; i++)
            OfficialAIChatTemplate(
              id: 'question-discard-$i',
              kind: 'question',
              purpose: 'discard',
              label: _defaultDiscardQuestions[i],
              body: _defaultDiscardQuestions[i],
              enabled: true,
              sortOrder: i,
            ),
          for (var i = 0; i < _defaultCallQuestions.length; i++)
            OfficialAIChatTemplate(
              id: 'question-call-$i',
              kind: 'question',
              purpose: 'call_advice',
              label: _defaultCallQuestions[i],
              body: _defaultCallQuestions[i],
              enabled: true,
              sortOrder: i,
            ),
        ],
      );

  static const _defaultSituations = [
    '親リーチ',
    'オーラス',
    'トップ目',
    'ラス目',
    '守備優先',
    '打点優先',
    'ドラを残す',
    '着順UP',
  ];
  static const _defaultDiscardQuestions = ['何を切る？', '押す？降りる？', '理由を詳しく'];
  static const _defaultCallQuestions = ['鳴くべき？', '見送るべき？', '判断が変わる条件は？'];
}
