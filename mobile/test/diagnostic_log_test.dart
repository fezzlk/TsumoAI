import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/services/diagnostic_log.dart';

class MemoryLogStorage implements DiagnosticLogStorage {
  String? contents;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String value) async => contents = value;
}

void main() {
  test(
    'retains only recent bounded entries and filters the chosen interval',
    () async {
      final storage = MemoryLogStorage();
      var now = DateTime.utc(2026, 10, 9, 10);
      final log = DiagnosticLog(
        storage: storage,
        now: () => now,
        maxEntries: 2,
      );
      await log.record(DiagnosticEvent.appStarted);
      now = now.add(const Duration(hours: 2));
      await log.record(DiagnosticEvent.scanOpened);
      now = now.add(const Duration(hours: 2));
      await log.record(DiagnosticEvent.captureCompleted, count: 14);

      final entries = await log.entriesBetween(
        DateTime.utc(2026, 10, 9, 11),
        DateTime.utc(2026, 10, 9, 13),
      );
      expect(entries.map((entry) => entry['event']), ['scanOpened']);
      expect(jsonDecode(storage.contents!) as List, hasLength(2));

      now = now.add(const Duration(days: 8));
      expect(await log.entriesSince(const Duration(days: 7)), isEmpty);
    },
  );

  test('stores error type without exception message', () async {
    final storage = MemoryLogStorage();
    final log = DiagnosticLog(storage: storage);
    await log.record(
      DiagnosticEvent.captureFailed,
      error: StateError('secret user-entered text'),
    );
    expect(storage.contents, contains('StateError'));
    expect(storage.contents, isNot(contains('secret user-entered text')));
  });
}
