import 'dart:convert';

import 'package:flutter/foundation.dart';

class PerformanceTrace {
  PerformanceTrace({
    required this.name,
    Map<String, Object?> metadata = const {},
    int Function()? nowMicros,
  }) : metadata = Map.unmodifiable(metadata),
       _nowMicros = nowMicros ?? _stopwatchMicros {
    _originMicros = _nowMicros();
    mark('flowStarted');
  }

  final String name;
  final Map<String, Object?> metadata;
  final int Function() _nowMicros;
  late final int _originMicros;
  final Map<String, int> _marks = {};

  static final Stopwatch _clock = Stopwatch()..start();
  static int _stopwatchMicros() => _clock.elapsedMicroseconds;

  void mark(String event) {
    _marks[event] = _nowMicros() - _originMicros;
  }

  int? durationMicros(String from, String to) {
    final start = _marks[from];
    final end = _marks[to];
    return start == null || end == null ? null : end - start;
  }

  Map<String, Object?> snapshot() {
    final ordered = _marks.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final intervals = <String, double>{};
    for (var index = 1; index < ordered.length; index++) {
      final previous = ordered[index - 1];
      final current = ordered[index];
      intervals['${previous.key}->${current.key}'] =
          (current.value - previous.value) / 1000;
    }
    return {
      'name': name,
      'metadata': metadata,
      'marks_ms': {for (final entry in ordered) entry.key: entry.value / 1000},
      'intervals_ms': intervals,
    };
  }

  void log() {
    if (kReleaseMode) return;
    debugPrint('PERFORMANCE_TRACE ${jsonEncode(snapshot())}');
  }
}
