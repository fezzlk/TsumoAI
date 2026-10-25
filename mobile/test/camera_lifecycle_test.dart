import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/services/camera_lifecycle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('background releases camera and resume reopens it only once', () async {
    final events = <String>[];
    final camera = CameraLifecycle(
      open: () async => events.add('open'),
      close: () async => events.add('close'),
      onError: (error, stack) => fail('$error'),
    );
    await camera.start();
    camera.didChangeAppLifecycleState(AppLifecycleState.inactive);
    camera.didChangeAppLifecycleState(AppLifecycleState.hidden);
    camera.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    expect(events, ['open', 'close']);
    expect(camera.isActive, isFalse);
    camera.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(events, ['open', 'close', 'open']);
    await camera.dispose();
    expect(events, ['open', 'close', 'open', 'close']);
  });

  test(
    'permission dialog during initialization serializes close and reopen',
    () async {
      final firstOpen = Completer<void>();
      final events = <String>[];
      final camera = CameraLifecycle(
        open: () async {
          events.add('open');
          if (events.length == 1) await firstOpen.future;
          events.add('ready');
        },
        close: () async => events.add('close'),
        onError: (error, stack) => fail('$error'),
      );
      final starting = camera.start();
      await Future<void>.delayed(Duration.zero);
      camera.didChangeAppLifecycleState(AppLifecycleState.inactive);
      camera.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(events, ['open']);
      firstOpen.complete();
      await starting;
      await Future<void>.delayed(Duration.zero);
      expect(events, ['open', 'ready', 'close', 'open', 'ready']);
      await camera.dispose();
    },
  );

  test(
    'leaving while initializing closes the camera without reopening',
    () async {
      final opening = Completer<void>();
      final events = <String>[];
      final camera = CameraLifecycle(
        open: () async {
          events.add('open');
          await opening.future;
        },
        close: () async => events.add('close'),
        onError: (error, stack) => fail('$error'),
      );
      unawaited(camera.start());
      await Future<void>.delayed(Duration.zero);
      camera.didChangeAppLifecycleState(AppLifecycleState.inactive);
      camera.didChangeAppLifecycleState(AppLifecycleState.resumed);
      final disposing = camera.dispose();
      opening.complete();
      await disposing;
      expect(events, ['open', 'close']);
      expect(camera.isActive, isFalse);
    },
  );

  test(
    'failed initialization can be retried and still releases resources',
    () async {
      var attempts = 0;
      var closes = 0;
      final errors = <Object>[];
      final camera = CameraLifecycle(
        open: () async {
          if (++attempts == 1) throw StateError('permission denied');
        },
        close: () async {
          closes++;
        },
        onError: (error, stack) => errors.add(error),
      );
      await camera.start();
      expect(errors, hasLength(1));
      await camera.retry();
      expect(attempts, 2);
      expect(closes, 1);
      await camera.dispose();
      await camera.retry();
      expect(attempts, 2);
      expect(closes, 2);
    },
  );
}
