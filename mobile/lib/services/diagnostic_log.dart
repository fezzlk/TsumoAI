import 'dart:async';
import 'dart:convert';

import 'local_document.dart';

enum DiagnosticEvent {
  appStarted,
  appReady,
  appInitializationFailed,
  settingsOpened,
  scanOpened,
  guidedModeSelected,
  detectionModeSelected,
  matchOpened,
  cameraReady,
  cameraFailed,
  captureRequested,
  captureCompleted,
  captureFailed,
  segmentationCompleted,
  classificationCompleted,
  analysisRequested,
  analysisCompleted,
  analysisFailed,
  logsUploadRequested,
  logsUploadSucceeded,
  logsUploadFailed,
  flutterUnhandledError,
  platformUnhandledError,
  apiRequestFailed,
}

abstract class DiagnosticLogStorage {
  Future<String?> read();
  Future<void> write(String contents);
}

class _DocumentLogStorage implements DiagnosticLogStorage {
  Future<LocalDocument> _document() async {
    final directory = await getApplicationSupportDirectory();
    return LocalDocument('${directory.path}/diagnostic_log.json');
  }

  @override
  Future<String?> read() async {
    final document = await _document();
    if (!await document.exists()) return null;
    return document.readAsString();
  }

  @override
  Future<void> write(String contents) async {
    await (await _document()).writeAsString(contents, flush: true);
  }
}

/// Bounded local journal. It never records user-entered text, URLs or tokens.
class DiagnosticLog {
  DiagnosticLog({
    DiagnosticLogStorage? storage,
    DateTime Function()? now,
    this.retention = const Duration(days: 7),
    this.maxEntries = 2000,
  }) : _storage = storage ?? _DocumentLogStorage(),
       _now = now ?? DateTime.now;

  static final DiagnosticLog instance = DiagnosticLog();

  final DiagnosticLogStorage _storage;
  final DateTime Function() _now;
  final Duration retention;
  final int maxEntries;
  final List<Map<String, Object?>> _entries = [];
  Future<void> _queue = Future.value();
  bool _loaded = false;

  Future<void> _load() async {
    if (_loaded) return;
    try {
      final contents = await _storage.read();
      if (contents != null) {
        final decoded = jsonDecode(contents);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              _entries.add(Map<String, Object?>.from(item));
            }
          }
        }
      }
    } catch (_) {
      _entries.clear(); // A damaged log must never prevent app startup.
    }
    _loaded = true;
    _prune();
  }

  void _prune() {
    final cutoff = _now().toUtc().subtract(retention);
    _entries.removeWhere((entry) {
      final value = entry['time'];
      final time = value is String ? DateTime.tryParse(value)?.toUtc() : null;
      return time == null || time.isBefore(cutoff);
    });
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }

  Future<void> record(
    DiagnosticEvent event, {
    int? count,
    int? elapsedMs,
    int? statusCode,
    Object? error,
    StackTrace? stack,
  }) {
    final errorType = error?.runtimeType.toString().replaceAll(
      RegExp(r'[^A-Za-z0-9_]'),
      '_',
    );
    final stackText = stack
        ?.toString()
        .split('\n')
        .take(8)
        .map((line) => line.replaceAll(RegExp(r'/Users/[^/\s]+'), '/Users/*'))
        .join('\n');
    final entry = <String, Object?>{
      'time': _now().toUtc().toIso8601String(),
      'event': event.name,
      'count': ?count,
      'elapsed_ms': ?elapsedMs,
      'status_code': ?statusCode,
      if (errorType != null)
        'error_type': errorType.length > 64
            ? errorType.substring(0, 64)
            : errorType,
      if (stackText != null)
        'stack': stackText.length > 2000
            ? stackText.substring(0, 2000)
            : stackText,
    };
    final task = _queue.then((_) async {
      await _load();
      _entries.add(entry);
      _prune();
      await _storage.write(jsonEncode(_entries));
    });
    // Logging must never turn a recoverable app error into another crash.
    _queue = task.catchError((Object _) {});
    return _queue;
  }

  Future<List<Map<String, Object?>>> entriesSince(Duration lookback) async {
    final end = _now().toUtc();
    return entriesBetween(end.subtract(lookback), end);
  }

  Future<List<Map<String, Object?>>> entriesBetween(
    DateTime start,
    DateTime end,
  ) async {
    await _queue;
    await _load();
    _prune();
    return [
      for (final entry in _entries)
        if (!DateTime.parse(entry['time']! as String).toUtc().isBefore(start) &&
            !DateTime.parse(entry['time']! as String).toUtc().isAfter(end))
          Map<String, Object?>.from(entry),
    ];
  }
}
