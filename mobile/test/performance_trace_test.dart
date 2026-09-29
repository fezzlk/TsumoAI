import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/services/performance_trace.dart';

void main() {
  test('records ordered marks and interval durations in milliseconds', () {
    var now = 1000000;
    final trace = PerformanceTrace(
      name: 'recognition',
      metadata: const {'tile_count': 14},
      nowMicros: () => now,
    );

    now += 250000;
    trace.mark('pictureTaken');
    now += 125000;
    trace.mark('classificationCompleted');

    expect(trace.durationMicros('flowStarted', 'pictureTaken'), 250000);
    expect(trace.snapshot(), {
      'name': 'recognition',
      'metadata': {'tile_count': 14},
      'marks_ms': {
        'flowStarted': 0.0,
        'pictureTaken': 250.0,
        'classificationCompleted': 375.0,
      },
      'intervals_ms': {
        'flowStarted->pictureTaken': 250.0,
        'pictureTaken->classificationCompleted': 125.0,
      },
    });
  });
}
