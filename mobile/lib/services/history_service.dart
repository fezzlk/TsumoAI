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
  HistoryService({
    Dio? dio,
    Future<Directory> Function()? directoryProvider,
    String? Function()? currentUidProvider,
    Future<String> Function()? tokenProvider,
  }) : _dio = dio ?? Dio(),
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _currentUidProvider =
           currentUidProvider ?? (() => AuthService.currentUser?.uid),
       _tokenProvider = tokenProvider ?? (() => AuthService.idToken());

  final Dio _dio;
  final Future<Directory> Function() _directoryProvider;
  final String? Function() _currentUidProvider;
  final Future<String> Function() _tokenProvider;
  static const _fileName = 'usage_history.json';
  static const _pendingDeletionFileName =
      'usage_history_pending_deletions.json';

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
    final directory = await _directoryProvider();
    return File('${directory.path}/$_fileName');
  }

  Future<File> _pendingDeletionFile() async {
    final directory = await _directoryProvider();
    return File('${directory.path}/$_pendingDeletionFileName');
  }

  Future<List<HistoryEntry>> _loadAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      final entries = decoded
          .whereType<Map>()
          .map((item) => HistoryEntry.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      return entries;
    } catch (_) {
      return [];
    }
  }

  Future<List<HistoryEntry>> loadLocal() async => _sorted(
    (await _loadAll()).where(
      (entry) => _isVisible(entry, _currentUidProvider()),
    ),
  );

  Future<void> _writeLocal(Iterable<HistoryEntry> entries) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> save(HistoryEntry entry) async {
    final uid = _currentUidProvider();
    final storedEntry = entry.accountUid == null && uid != null
        ? entry.copyWith(accountUid: uid)
        : entry;
    final entries = await _loadAll();
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

  Future<HistoryEntry?> updateDetails(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final entries = await _loadAll();
    final index = entries.indexWhere((item) => item.id == id);
    if (index == -1) return null;
    final updated = entries[index].copyWith(
      updatedAt: DateTime.now().toUtc(),
      details: {...entries[index].details, ...updates},
    );
    entries[index] = updated;
    await _writeLocal(entries);
    unawaited(_uploadIfSignedIn(updated));
    return updated;
  }

  Future<List<HistoryEntry>> synchronize() async {
    final uid = _currentUidProvider();
    final allLocal = await _loadAll();
    final local = _sorted(allLocal.where((entry) => _isVisible(entry, uid)));
    if (uid == null) return local;

    try {
      final token = await _tokenProvider();
      if (await _hasPendingDeletion(uid)) {
        try {
          await _deleteRemote(token);
          await _clearPendingDeletion(uid);
        } catch (_) {
          // Do not fetch deleted remote data back onto the device. Retry the
          // account deletion on the next synchronization.
          return local;
        }
      }
      final response = await _dio.get(
        '${AppConfig.apiBaseUrl}/api/v1/history',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final remoteItems = (response.data['items'] as List<dynamic>? ?? const [])
          .map(
            (item) => HistoryEntry.fromJson(
              Map<String, dynamic>.from(item as Map),
            ).copyWith(accountUid: uid),
          )
          .toList();
      final merged = <String, HistoryEntry>{};
      final claimedLocal = <HistoryEntry>[
        for (final entry in local)
          if (entry.accountUid == null)
            entry.copyWith(accountUid: uid)
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
      final otherAccounts = allLocal.where(
        (entry) => entry.accountUid != null && entry.accountUid != uid,
      );
      await _writeLocal([...otherAccounts, ...entries.take(500)]);
      for (final entry in claimedLocal.where(
        (item) => item.accountUid == uid,
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
    final uid = _currentUidProvider();
    final all = await _loadAll();
    await _writeLocal(all.where((entry) => !_isVisible(entry, uid)));
    if (uid == null) return;
    await _markPendingDeletion(uid);
    try {
      await _deleteRemote(await _tokenProvider());
      await _clearPendingDeletion(uid);
    } catch (_) {
      // Local deletion succeeds immediately. The account deletion remains
      // queued and blocks remote history from being re-imported.
    }
  }

  Future<void> _uploadIfSignedIn(HistoryEntry entry) async {
    final uid = _currentUidProvider();
    if (uid == null || entry.accountUid != uid) return;
    try {
      await _upload(await _tokenProvider(), entry);
    } catch (_) {
      // The local record is authoritative while offline.
    }
  }

  Future<void> _upload(String token, HistoryEntry entry) => _dio.put(
    '${AppConfig.apiBaseUrl}/api/v1/history/${entry.id}',
    data: entry.toJson(includeId: false)..remove('updated_at'),
    options: Options(headers: {'Authorization': 'Bearer $token'}),
  );

  Future<void> _deleteRemote(String token) => _dio.delete(
    '${AppConfig.apiBaseUrl}/api/v1/history',
    options: Options(headers: {'Authorization': 'Bearer $token'}),
  );

  Future<Set<String>> _pendingDeletions() async {
    try {
      final file = await _pendingDeletionFile();
      if (!await file.exists()) return {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return {};
      return decoded.whereType<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _writePendingDeletions(Set<String> uids) async {
    final file = await _pendingDeletionFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(uids.toList()..sort()), flush: true);
  }

  Future<bool> _hasPendingDeletion(String uid) async =>
      (await _pendingDeletions()).contains(uid);

  Future<void> _markPendingDeletion(String uid) async {
    final pending = (await _pendingDeletions())..add(uid);
    await _writePendingDeletions(pending);
  }

  Future<void> _clearPendingDeletion(String uid) async {
    final pending = (await _pendingDeletions())..remove(uid);
    await _writePendingDeletions(pending);
  }

  List<HistoryEntry> _sorted(Iterable<HistoryEntry> entries) {
    final result = entries.toList();
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  bool _isVisible(HistoryEntry entry, String? uid) => uid == null
      ? entry.accountUid == null
      : entry.accountUid == null || entry.accountUid == uid;
}
