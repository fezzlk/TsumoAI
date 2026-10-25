import 'dart:async';

import 'package:flutter/widgets.dart';

/// Serializes camera ownership across permission dialogs and app switches.
/// Camera plugins require the app to release and reopen their controller.
class CameraLifecycle with WidgetsBindingObserver {
  CameraLifecycle({
    required this.open,
    required this.close,
    required this.onError,
  });

  final Future<void> Function() open;
  final Future<void> Function() close;
  final void Function(Object error, StackTrace stack) onError;
  Future<void> _pending = Future.value();
  bool _wantedActive = false;
  bool _active = false;
  bool _disposed = false;

  bool get isActive => _wantedActive && !_disposed;

  Future<void> start() {
    WidgetsBinding.instance.addObserver(this);
    return _setActive(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_setActive(state == AppLifecycleState.resumed));
  }

  Future<void> _setActive(bool active) {
    _wantedActive = active && !_disposed;
    return _enqueue(() async {
      // Preserve suspend/resume ordering even when a permission dialog
      // emits both events while open is pending. Never reopen after dispose.
      final nextActive = active && !_disposed;
      if (_active == nextActive) return;
      _active = nextActive;
      if (_active) {
        await open();
      } else {
        await close();
      }
    });
  }

  Future<void> retry() => _enqueue(() async {
    if (!isActive) return;
    await close();
    if (isActive) await open();
  });

  Future<void> _enqueue(Future<void> Function() action) {
    _pending = _pending.then((_) => action()).catchError((
      Object error,
      StackTrace stack,
    ) {
      onError(error, stack);
    });
    return _pending;
  }

  Future<void> dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    return _setActive(false);
  }
}
