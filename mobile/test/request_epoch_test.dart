import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/services/request_epoch.dart';

void main() {
  test('input invalidation makes an earlier response stale', () {
    final epoch = RequestEpoch();
    final requestEpoch = epoch.current;

    epoch.invalidate();

    expect(epoch.isCurrent(requestEpoch), isFalse);
    expect(epoch.isCurrent(epoch.current), isTrue);
  });
}
