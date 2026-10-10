import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/screens/scan_screen.dart';
import 'package:tsumoai_mobile/screens/training_data_screen.dart';

const _cameras = [
  CameraDescription(
    name: 'back',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  ),
];

void main() {
  for (final training in [false, true]) {
    testWidgets(
      '${training ? 'training' : 'scan'} waits for explicit retry after permission denial',
      (tester) async {
        const channel = MethodChannel('plugins.flutter.io/camera');
        final permission = Completer<void>();
        var requests = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'create') {
              requests++;
              if (requests == 1) await permission.future;
              throw PlatformException(code: 'CameraAccessDenied');
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        tester.view.physicalSize = const Size(540, 1200);
        tester.view.devicePixelRatio = 1.3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: training
                ? const TrainingDataScreen(cameras: _cameras)
                : const ScanScreen(cameras: _cameras),
          ),
        );
        await tester.pump();
        expect(requests, 1);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        permission.complete();
        await tester.pumpAndSettle();
        expect(requests, 1, reason: 'denying permission must not prompt again');
        expect(find.text('再試行'), findsOneWidget);
        await tester.tap(find.text('再試行'));
        await tester.pumpAndSettle();
        expect(requests, 2);
        expect(find.text('再試行'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}
