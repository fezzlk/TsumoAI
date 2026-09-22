import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/history_entry.dart';
import 'auth_service.dart';

class HistoryService {
  HistoryService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const _fileName = 'usage_history.json';

  static String createId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final value = bytes.map(hex).join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<HistoryEntry>> loadLocal() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      final entries = decoded
          .whereType<Map>()
          .map((item) => HistoryEntry.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return entries;
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeLocal(Iterable<HistoryEntry> entries) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> save(HistoryEntry entry) async {
    final storedEntry =
        entry.accountUid == null && AuthService.currentUser != null
        ? entry.copyWith(accountUid: AuthService.currentUser!.uid)
        : entry;
    final entries = await loadLocal();
    final index = entries.indexWhere((item) => item.id == storedEntry.id);
    if (index == -1) {
      entries.add(storedEntry);
    } else {
      entries[index] = storedEntry;
    }
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _writeLocal(entries.take(500));
    unawaited(_uploadIfSignedIn(storedEntry));
  }

  Future<List<HistoryEntry>> synchronize() async {
    final user = AuthService.currentUser;
    final local = await loadLocal();
    if (user == null) return local;

    try {
      final token = await AuthService.idToken();
      final response = await _dio.get(
        '${AppConfig.apiBaseUrl}/api/v1/history',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final remoteItems = (response.data['items'] as List<dynamic>? ?? const [])
          .map(
            (item) => HistoryEntry.fromJson(
              Map<String, dynamic>.from(item as Map),
            ).copyWith(accountUid: user.uid),
          )
          .toList();
      final merged = <String, HistoryEntry>{};
      final claimedLocal = [
        for (final entry in local)
          if (entry.accountUid == null)
            entry.copyWith(accountUid: user.uid)
          else
            entry,
      ];
      for (final entry in [...remoteItems, ...claimedLocal]) {
        final current = merged[entry.id];
        if (current == null || entry.updatedAt.isAfter(current.updatedAt)) {
          merged[entry.id] = entry;
        }
      }
      final entries = merged.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await _writeLocal(entries.take(500));
      for (final entry in claimedLocal.where(
        (item) => item.accountUid == user.uid,
      )) {
        final remote = remoteItems
            .where((item) => item.id == entry.id)
            .firstOrNull;
        if (remote == null || entry.updatedAt.isAfter(remote.updatedAt)) {
          try {
            await _upload(token, entry);
          } catch (_) {
            // Keep the local entry queued for the next synchronization.
          }
        }
      }
      return entries;
    } catch (_) {
      return local;
    }
  }

  Future<void> deleteAll() async {
    if (AuthService.currentUser != null) {
      final token = await AuthService.idToken();
      await _dio.delete(
        '${AppConfig.apiBaseUrl}/api/v1/history',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    }
    await _writeLocal(const []);
  }

  Future<void> _uploadIfSignedIn(HistoryEntry entry) async {
    if (AuthService.currentUser == null) return;
    try {
      await _upload(await AuthService.idToken(), entry);
    } catch (_) {
      // The local record is authoritative while offline.
    }
  }

  Future<void> _upload(String token, HistoryEntry entry) => _dio.put(
    '${AppConfig.apiBaseUrl}/api/v1/history/${entry.id}',
    data: entry.toJson(includeId: false)..remove('updated_at'),
    options: Options(headers: {'Authorization': 'Bearer $token'}),
  );
}
