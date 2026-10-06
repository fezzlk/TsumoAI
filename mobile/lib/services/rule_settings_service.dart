import 'dart:async';
import 'dart:convert';
import 'local_document.dart';

import 'package:dio/dio.dart';

import '../config.dart';
import '../models/score_request.dart';
import 'auth_service.dart';

class RuleSettingsService {
  RuleSettingsService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              sendTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ),
          );

  static const _fileName = 'mahjong_rule_settings.json';
  final Dio _dio;

  Future<LocalDocument> _file() async {
    final directory = await getApplicationSupportDirectory();
    return LocalDocument('${directory.path}/$_fileName');
  }

  Future<_StoredRuleSettings> _loadRecord() async {
    try {
      final file = await _file();
      if (!await file.exists()) return _StoredRuleSettings.defaults();
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return _StoredRuleSettings.defaults();
      return _StoredRuleSettings.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return _StoredRuleSettings.defaults();
    }
  }

  Future<MahjongRuleSettings> loadLocal() async =>
      (await _loadRecord()).settings;

  Future<void> _write(_StoredRuleSettings record) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(record.toJson()), flush: true);
  }

  Future<void> save(MahjongRuleSettings settings) async {
    final user = AuthService.currentUser;
    final record = _StoredRuleSettings(
      settings: settings,
      updatedAt: DateTime.now().toUtc(),
      accountUid: user?.uid,
      pendingSync: user != null,
    );
    await _write(record);
    if (user != null) unawaited(_upload(record));
  }

  Future<MahjongRuleSettings> synchronize() async {
    final local = await _loadRecord();
    final user = AuthService.currentUser;
    if (user == null) return local.settings;

    if (local.pendingSync && local.accountUid == user.uid) {
      try {
        return (await _upload(local)).settings;
      } catch (_) {
        return local.settings;
      }
    }

    try {
      final token = await AuthService.idToken();
      final response = await _dio.get(
        '${AppConfig.apiBaseUrl}/api/v1/settings/mahjong-rules',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final remote = _StoredRuleSettings(
        settings: MahjongRuleSettings.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        ),
        updatedAt: DateTime.parse(response.data['updated_at'] as String),
        accountUid: user.uid,
        pendingSync: false,
      );
      await _write(remote);
      return remote.settings;
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) return local.settings;
      try {
        return (await _upload(
          _StoredRuleSettings(
            settings: local.settings,
            updatedAt: local.updatedAt,
            accountUid: user.uid,
            pendingSync: true,
          ),
        )).settings;
      } catch (_) {
        return local.settings;
      }
    } catch (_) {
      return local.settings;
    }
  }

  Future<_StoredRuleSettings> _upload(_StoredRuleSettings record) async {
    final user = AuthService.currentUser;
    if (user == null) return record;
    final token = await AuthService.idToken();
    final response = await _dio.put(
      '${AppConfig.apiBaseUrl}/api/v1/settings/mahjong-rules',
      data: record.settings.toJson(),
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final stored = _StoredRuleSettings(
      settings: MahjongRuleSettings.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      ),
      updatedAt: DateTime.parse(response.data['updated_at'] as String),
      accountUid: user.uid,
      pendingSync: false,
    );
    await _write(stored);
    return stored;
  }
}

class _StoredRuleSettings {
  const _StoredRuleSettings({
    required this.settings,
    required this.updatedAt,
    required this.accountUid,
    required this.pendingSync,
  });

  final MahjongRuleSettings settings;
  final DateTime updatedAt;
  final String? accountUid;
  final bool pendingSync;

  factory _StoredRuleSettings.defaults() => _StoredRuleSettings(
    settings: const MahjongRuleSettings(),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    accountUid: null,
    pendingSync: false,
  );

  factory _StoredRuleSettings.fromJson(Map<String, dynamic> json) =>
      _StoredRuleSettings(
        settings: MahjongRuleSettings.fromJson(
          Map<String, dynamic>.from(json['settings'] as Map? ?? const {}),
        ),
        updatedAt:
            DateTime.tryParse(json['updated_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        accountUid: json['account_uid'] as String?,
        pendingSync: json['pending_sync'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
    'settings': settings.toJson(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'account_uid': accountUid,
    'pending_sync': pendingSync,
  };
}
