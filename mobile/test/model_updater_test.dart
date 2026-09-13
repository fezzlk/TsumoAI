import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:tsumoai_mobile/services/model_updater.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('model_updater_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  MockClient offlineClient() {
    return MockClient((request) async {
      throw const SocketException('Failed host lookup: no address associated with hostname');
    });
  }

  test('falls back to the cached model when offline and a cached model exists', () async {
    await File('${tempDir.path}/tile_classifier.tflite').writeAsBytes([1, 2, 3]);
    await File('${tempDir.path}/model_meta.json')
        .writeAsString(jsonEncode({'version': 'v1'}));

    final result = await ModelUpdater.checkAndUpdate(
      client: offlineClient(),
      modelDir: tempDir,
    );

    expect(result, tempDir.path);
  });

  test('falls back to the bundled model (null) when offline and no cached model exists', () async {
    final result = await ModelUpdater.checkAndUpdate(
      client: offlineClient(),
      modelDir: tempDir,
    );

    expect(result, isNull);
  });

  test('falls back to the cached model when the request times out', () async {
    await File('${tempDir.path}/tile_classifier.tflite').writeAsBytes([1, 2, 3]);
    await File('${tempDir.path}/model_meta.json')
        .writeAsString(jsonEncode({'version': 'v1'}));

    final timeoutClient = MockClient((request) async {
      await Future.delayed(const Duration(seconds: 15));
      throw StateError('should have timed out before completing');
    });

    final result = await ModelUpdater.checkAndUpdate(
      client: timeoutClient,
      modelDir: tempDir,
    );

    expect(result, tempDir.path);
  }, timeout: const Timeout(Duration(seconds: 20)));
}
