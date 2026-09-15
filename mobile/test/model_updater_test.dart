import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumoai_mobile/services/model_updater.dart';

final class _FailingCandidateIO extends IOOverrides {
  _FailingCandidateIO(this.fileName, {this.failRename = false});

  final String fileName;
  final bool failRename;
  bool triggered = false;

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    if (path.contains('/candidate_') && path.endsWith('/$fileName')) {
      return _FailingCandidateFile(file, this);
    }
    return file;
  }
}

class _FailingCandidateFile implements File {
  _FailingCandidateFile(this.delegate, this.failure);

  final File delegate;
  final _FailingCandidateIO failure;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    if (!failure.failRename) {
      failure.triggered = true;
      throw FileSystemException('injected disk write failure', delegate.path);
    }
    await delegate.writeAsString(
      contents,
      mode: mode,
      encoding: encoding,
      flush: flush,
    );
    return this;
  }

  @override
  Future<File> rename(String newPath) async {
    failure.triggered = true;
    throw FileSystemException('injected publication failure', delegate.path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory supportDirectory;
  late Directory modelDirectory;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'model_updater_test_',
    );
    modelDirectory = await Directory(
      '${supportDirectory.path}/ml_model',
    ).create();
  });

  tearDown(() async {
    await supportDirectory.delete(recursive: true);
  });

  Future<void> cacheModel({bool model = true, bool labels = true}) async {
    if (model) {
      await File(
        '${modelDirectory.path}/tile_classifier.tflite',
      ).writeAsBytes([1, 2, 3]);
    }
    if (labels) {
      await File('${modelDirectory.path}/labels.txt').writeAsString('1m\n2m\n');
    }
    await File(
      '${modelDirectory.path}/model_meta.json',
    ).writeAsString(jsonEncode({'version': 'cached'}));
  }

  Future<String?> update(http.Client client) => ModelUpdater.checkAndUpdate(
    client: client,
    supportDirectory: supportDirectory,
  );

  http.Client availableModel({String version = 'new'}) =>
      MockClient((request) async {
        if (request.url.path.endsWith('/latest')) {
          return http.Response(
            jsonEncode({'status': 'ok', 'version': version}),
            200,
          );
        }
        if (request.url.path.endsWith('/labels.txt')) {
          return http.Response('3m\n', 200);
        }
        return http.Response.bytes([4, 5, 6], 200);
      });

  http.Client offline() =>
      MockClient((_) async => throw const SocketException('offline'));

  for (final error in <Object>[
    const SocketException('offline'),
    TimeoutException('update check timed out'),
    http.ClientException('network unavailable'),
  ]) {
    test('uses cached model after ${error.runtimeType}', () async {
      await cacheModel();
      expect(
        await update(MockClient((_) async => throw error)),
        modelDirectory.path,
      );
    });
  }

  test(
    'returns null for bundled fallback when offline without cache',
    () async {
      expect(
        await update(
          MockClient((_) async => throw const SocketException('offline')),
        ),
        isNull,
      );
    },
  );

  for (final missing in ['model', 'labels']) {
    test('returns null for bundled fallback with missing $missing', () async {
      await cacheModel(model: missing != 'model', labels: missing != 'labels');
      expect(
        await update(
          MockClient((_) async => throw const SocketException('offline')),
        ),
        isNull,
      );
    });
  }

  test('rejects empty cached labels', () async {
    await cacheModel();
    await File('${modelDirectory.path}/labels.txt').writeAsString(' \n');
    expect(
      await update(MockClient((_) async => http.Response('', 503))),
      isNull,
    );
  });

  test('rejects an empty cached model', () async {
    await cacheModel();
    await File(
      '${modelDirectory.path}/tile_classifier.tflite',
    ).writeAsBytes([]);
    expect(
      await update(MockClient((_) async => http.Response('', 503))),
      isNull,
    );
  });

  test(
    'rejects invalid cached labels without preventing bundled fallback',
    () async {
      await cacheModel();
      await File('${modelDirectory.path}/labels.txt').writeAsBytes([0xff]);
      expect(
        await update(
          MockClient((_) async => throw const SocketException('offline')),
        ),
        isNull,
      );
    },
  );

  test('preserves cache when a newer model download times out', () async {
    await cacheModel();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/latest')) {
        return http.Response(
          jsonEncode({'status': 'ok', 'version': 'new'}),
          200,
        );
      }
      throw TimeoutException('download timed out');
    });
    expect(await update(client), modelDirectory.path);
    expect(
      await File('${modelDirectory.path}/tile_classifier.tflite').readAsBytes(),
      [1, 2, 3],
    );
  });

  test('keeps the model and labels when labels download fails', () async {
    await cacheModel();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/latest')) {
        return http.Response(
          jsonEncode({'status': 'ok', 'version': 'new'}),
          200,
        );
      }
      if (request.url.path.endsWith('/tile_classifier.tflite')) {
        return http.Response.bytes([4, 5, 6], 200);
      }
      throw const SocketException('offline');
    });
    expect(await update(client), modelDirectory.path);
    expect(
      await File('${modelDirectory.path}/tile_classifier.tflite').readAsBytes(),
      [1, 2, 3],
    );
    expect(
      await File('${modelDirectory.path}/labels.txt').readAsString(),
      '1m\n2m\n',
    );
  });

  test(
    'downloads missing cache files even when metadata version matches',
    () async {
      await cacheModel(labels: false);
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/latest')) {
          return http.Response(
            jsonEncode({'status': 'ok', 'version': 'cached'}),
            200,
          );
        }
        if (request.url.path.endsWith('/labels.txt')) {
          return http.Response('3m\n', 200);
        }
        return http.Response.bytes([4, 5, 6], 200);
      });
      final downloadedPath = await update(client);
      expect(downloadedPath, isNotNull);
      expect(paths, hasLength(3));
      expect(await File('$downloadedPath/labels.txt').readAsString(), '3m\n');
    },
  );

  for (final fileName in ['labels.txt', 'model_meta.json', 'active_model']) {
    test(
      'failed $fileName write preserves the previous pair on the next offline start',
      () async {
        await cacheModel();
        final failure = _FailingCandidateIO(fileName);
        final result = await IOOverrides.runWithIOOverrides(
          () => update(availableModel()),
          failure,
        );
        expect(failure.triggered, isTrue);
        expect(result, modelDirectory.path);
        expect(await File('$result/tile_classifier.tflite').readAsBytes(), [
          1,
          2,
          3,
        ]);
        expect(await File('$result/labels.txt').readAsString(), '1m\n2m\n');
        expect(
          jsonDecode(
            await File('$result/model_meta.json').readAsString(),
          )['version'],
          'cached',
        );
        expect(await update(offline()), result);
        expect(
          (await modelDirectory.list().toList()).whereType<Directory>(),
          isEmpty,
        );
      },
    );
  }

  test(
    'a failed activation rename preserves an already published cache',
    () async {
      final previousPath = await update(availableModel());
      final failure = _FailingCandidateIO('active_model', failRename: true);
      final result = await IOOverrides.runWithIOOverrides(
        () => update(availableModel(version: 'newer')),
        failure,
      );
      expect(failure.triggered, isTrue);
      expect(result, previousPath);
      expect(await File('$result/tile_classifier.tflite').readAsBytes(), [
        4,
        5,
        6,
      ]);
      expect(await File('$result/labels.txt').readAsString(), '3m\n');
      expect(
        jsonDecode(
          await File('$result/model_meta.json').readAsString(),
        )['version'],
        'new',
      );
      expect(await update(offline()), previousPath);
      expect(
        (await modelDirectory.list().toList()).whereType<Directory>(),
        hasLength(1),
      );
    },
  );

  test(
    'failed first download write leaves no partial cache for the next start',
    () async {
      final failure = _FailingCandidateIO('labels.txt');
      final result = await IOOverrides.runWithIOOverrides(
        () => update(availableModel()),
        failure,
      );
      expect(failure.triggered, isTrue);
      expect(result, isNull);
      expect(await update(offline()), isNull);
      expect(await modelDirectory.list().toList(), isEmpty);
    },
  );

  test(
    'publishes a complete new pair and selects it on subsequent starts',
    () async {
      await cacheModel();
      final result = await update(availableModel());
      expect(result, isNotNull);
      expect(result, isNot(modelDirectory.path));
      expect(await File('$result/tile_classifier.tflite').readAsBytes(), [
        4,
        5,
        6,
      ]);
      expect(await File('$result/labels.txt').readAsString(), '3m\n');
      expect(
        jsonDecode(
          await File('$result/model_meta.json').readAsString(),
        )['version'],
        'new',
      );
      expect(
        await File(
          '${modelDirectory.path}/tile_classifier.tflite',
        ).readAsBytes(),
        [1, 2, 3],
      );
      expect(
        await File('${modelDirectory.path}/labels.txt').readAsString(),
        '1m\n2m\n',
      );
      expect(await update(offline()), result);

      final requests = <Uri>[];
      final upToDate = MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          jsonEncode({'status': 'ok', 'version': 'new'}),
          200,
        );
      });
      expect(await update(upToDate), result);
      expect(requests, hasLength(1));
      final newerPath = await update(availableModel(version: 'newer'));
      expect(newerPath, isNotNull);
      expect(newerPath, isNot(result));
      expect(await update(offline()), newerPath);
      expect(
        jsonDecode(await File('$newerPath/model_meta.json').readAsString())['version'],
        'newer',
      );
    },
  );
}
