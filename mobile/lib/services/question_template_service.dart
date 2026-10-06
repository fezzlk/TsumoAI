import 'dart:async';
import 'dart:convert';
import 'local_document.dart';

import 'package:dio/dio.dart';

import '../config.dart';
import '../models/question_template.dart';
import 'auth_service.dart';
import 'history_service.dart';

class QuestionTemplateService {
  QuestionTemplateService({
    Dio? dio,
    Future<Directory> Function()? directoryProvider,
  }) : _dio = dio ?? Dio(),
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const _fileName = 'question_templates.json';
  final Dio _dio;
  final Future<Directory> Function() _directoryProvider;
  bool _lastLoadFailed = false;

  bool get lastLoadFailed => _lastLoadFailed;

  Future<LocalDocument> _file() async {
    final directory = await _directoryProvider();
    return LocalDocument('${directory.path}/$_fileName');
  }

  Future<List<QuestionTemplate>> _loadAll() async {
    _lastLoadFailed = false;
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        _lastLoadFailed = true;
        return [];
      }
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                QuestionTemplate.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (_) {
      _lastLoadFailed = true;
      return [];
    }
  }

  Future<void> _writeAll(Iterable<QuestionTemplate> items) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(items.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  Future<List<QuestionTemplate>> loadLocal() async {
    final uid = AuthService.currentUser?.uid;
    final items = await _loadAll();
    final visible = items.where(
      (item) => !item.deleted && _isVisible(item, uid),
    );
    return _sorted(visible);
  }

  Future<QuestionTemplate> saveSentMessage(String message) async {
    final all = await _loadAll();
    final uid = AuthService.currentUser?.uid;
    final visible = all.where((item) => _isVisible(item, uid));
    final before = visible.toList();
    final now = DateTime.now().toUtc();
    final after = QuestionTemplateCollection.saveMessage(
      items: before,
      id: HistoryService.createId(),
      message: message,
      now: now,
      accountUid: uid,
    );
    if (identical(before, after)) {
      return before.firstWhere(
        (item) => !item.deleted && item.body == message.trim(),
      );
    }
    final saved = after.first;
    await _writeAll([saved, ...all.where((item) => item.id != saved.id)]);
    if (uid != null) unawaited(_upload(saved));
    return saved;
  }

  Future<QuestionTemplate> update({
    required String id,
    required String name,
    required String body,
  }) async {
    final all = await _loadAll();
    final uid = AuthService.currentUser?.uid;
    final index = all.indexWhere(
      (item) => item.id == id && _isVisible(item, uid),
    );
    if (index == -1) throw StateError('Question template not found');
    final normalizedName = name.trim();
    final normalizedBody = body.trim();
    if (normalizedName.isEmpty || normalizedBody.isEmpty) {
      throw ArgumentError('Name and body must not be empty');
    }
    QuestionTemplate.validateLengths(
      name: normalizedName,
      body: normalizedBody,
    );
    if (all.any(
      (item) =>
          item.id != id &&
          !item.deleted &&
          item.body == normalizedBody &&
          _isVisible(item, uid),
    )) {
      throw StateError('Question template already exists');
    }
    final updated = all[index].copyWith(
      name: normalizedName,
      body: normalizedBody,
      updatedAt: DateTime.now().toUtc(),
      accountUid: uid ?? all[index].accountUid,
      pendingSync: uid != null || all[index].accountUid != null,
      deleted: false,
    );
    all[index] = updated;
    await _writeAll(all);
    if (uid != null) unawaited(_upload(updated));
    return updated;
  }

  Future<void> delete(String id) async {
    final all = await _loadAll();
    final uid = AuthService.currentUser?.uid;
    final index = all.indexWhere(
      (item) => item.id == id && _isVisible(item, uid),
    );
    if (index == -1) return;
    if (all[index].accountUid == null) {
      all.removeAt(index);
      await _writeAll(all);
      return;
    }
    all[index] = all[index].copyWith(
      updatedAt: DateTime.now().toUtc(),
      pendingSync: true,
      deleted: true,
    );
    await _writeAll(all);
    if (uid == all[index].accountUid) unawaited(_deleteRemote(all[index]));
  }

  Future<List<QuestionTemplate>> synchronize() async {
    final user = AuthService.currentUser;
    if (user == null) return loadLocal();
    var all = await _loadAll();
    final claimed = <QuestionTemplate>[
      for (final item in all)
        if (item.accountUid == null)
          item.copyWith(accountUid: user.uid, pendingSync: true)
        else
          item,
    ];
    all = claimed;
    await _writeAll(all);

    final pendingItems = all
        .where((item) => item.accountUid == user.uid && item.pendingSync)
        .toList();
    for (final item in pendingItems) {
      try {
        if (item.deleted) {
          await _deleteRemote(item);
          all.removeWhere((candidate) => candidate.id == item.id);
        } else {
          final uploaded = await _upload(item);
          final index = all.indexWhere((candidate) => candidate.id == item.id);
          if (index != -1) all[index] = uploaded;
        }
      } catch (_) {
        // Keep the pending mutation for the next synchronization.
      }
    }

    try {
      final token = await AuthService.idToken();
      final response = await _dio.get(
        '${AppConfig.apiBaseUrl}/api/v1/question-templates',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final remote = (response.data['items'] as List<dynamic>? ?? const [])
          .map(
            (item) => QuestionTemplate.fromJson(
              Map<String, dynamic>.from(item as Map),
            ).copyWith(accountUid: user.uid, pendingSync: false),
          )
          .toList();
      final merged = <String, QuestionTemplate>{
        for (final item in all)
          if (item.accountUid != user.uid || item.pendingSync) item.id: item,
      };
      for (final item in remote) {
        final local = merged[item.id];
        if (local == null ||
            (!local.pendingSync && item.updatedAt.isAfter(local.updatedAt))) {
          merged[item.id] = item;
        }
      }
      all = merged.values.toList();
      await _writeAll(all);
    } catch (_) {
      await _writeAll(all);
    }
    return loadLocal();
  }

  Future<QuestionTemplate> _upload(QuestionTemplate item) async {
    final token = await AuthService.idToken();
    final response = await _dio.put(
      '${AppConfig.apiBaseUrl}/api/v1/question-templates/${item.id}',
      data: {
        'name': item.name,
        'body': item.body,
        'created_at': item.createdAt.toUtc().toIso8601String(),
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return QuestionTemplate.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    ).copyWith(accountUid: AuthService.currentUser?.uid, pendingSync: false);
  }

  Future<void> _deleteRemote(QuestionTemplate item) async {
    final token = await AuthService.idToken();
    await _dio.delete(
      '${AppConfig.apiBaseUrl}/api/v1/question-templates/${item.id}',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  List<QuestionTemplate> _sorted(Iterable<QuestionTemplate> items) {
    final result = items.toList();
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  /// Signed-out users see only unclaimed device templates, never those of
  /// the account that was signed in before (same rule as HistoryService).
  bool _isVisible(QuestionTemplate item, String? uid) =>
      item.accountUid == null || item.accountUid == uid;
}
