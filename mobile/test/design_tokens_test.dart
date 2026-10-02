import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Screens must take colors, text sizes and radii from the theme tokens
/// (`lib/theme/`), so the same meaning always looks the same.
void main() {
  test('lib/ uses theme tokens instead of hard-coded styles', () {
    final forbidden = <String, RegExp>{
      'Colors.*': RegExp(r'\bColors\.(?!transparent\b)[a-zA-Z]'),
      'fontSize': RegExp(r'\bfontSize:'),
      'numeric radius': RegExp(r'BorderRadius\.circular\(\d'),
    };
    final violations = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.startsWith('lib/theme/'));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        for (final entry in forbidden.entries) {
          if (entry.value.hasMatch(lines[index])) {
            violations.add('${file.path}:${index + 1} ${entry.key}');
          }
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
