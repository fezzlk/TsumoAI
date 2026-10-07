import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/history_entry.dart';
import 'package:tsumoai_mobile/services/history_service.dart';

HistoryEntry entry(String id, {String? accountUid}) => HistoryEntry(
  id: id,
  createdAt: DateTime.utc(2026, 9, 30),
  updatedAt: DateTime.utc(2026, 9, 30),
  purpose: 'wait',
  title: '待ち確認',
  summary: id,
  details: const {},
  accountUid: accountUid,
);

void main() {
  test('unavailable storage reports an unsaved result and can recover', () async {
    final directory = await Directory.systemTemp.createTemp('history-recovery-');
    addTearDown(() => directory.delete(recursive: true));
    var storageAvailable = false;
    final service = HistoryService(
      directoryProvider: () async {
        if (!storageAvailable) throw StateError('Storage is blocked or full');
        return directory;
      },
      currentUidProvider: () => null,
    );
    expect(await service.trySave(entry('analysis')), isFalse);
    expect(await service.loadLocal(), isEmpty);
    storageAvailable = true;
    expect(await service.trySave(entry('analysis')), isTrue);
    expect((await service.loadLocal()).single.id, 'analysis');
  });

  test(
    'local history only exposes the signed-in account and unowned items',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'history-service-',
      );
      addTearDown(() => directory.delete(recursive: true));
      String? uid;
      final service = HistoryService(
        directoryProvider: () async => directory,
        currentUidProvider: () => uid,
        tokenProvider: () async => 'token',
      );

      await service.save(entry('unowned'));
      await service.save(entry('account-a', accountUid: 'a'));
      await service.save(entry('account-b', accountUid: 'b'));

      expect((await service.loadLocal()).map((item) => item.id), ['unowned']);
      uid = 'a';
      expect((await service.loadLocal()).map((item) => item.id).toSet(), {
        'unowned',
        'account-a',
      });
      uid = 'b';
      expect((await service.loadLocal()).map((item) => item.id).toSet(), {
        'unowned',
        'account-b',
      });
    },
  );

  test(
    'failed account deletion stays local and retries before remote fetch',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'history-delete-',
      );
      addTearDown(() => directory.delete(recursive: true));
      var deleteSucceeds = false;
      var deleteRequests = 0;
      var getRequests = 0;
      String? uid;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.method == 'DELETE') {
              deleteRequests++;
              if (!deleteSucceeds) {
                handler.reject(DioException(requestOptions: options));
                return;
              }
              handler.resolve(
                Response(requestOptions: options, statusCode: 200, data: {}),
              );
              return;
            }
            if (options.method == 'GET') {
              getRequests++;
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'items': <Object>[]},
                ),
              );
              return;
            }
            handler.next(options);
          },
        ),
      );
      final service = HistoryService(
        dio: dio,
        directoryProvider: () async => directory,
        currentUidProvider: () => uid,
        tokenProvider: () async => 'token',
      );

      await service.save(entry('account-a', accountUid: 'a'));
      await service.save(entry('account-b', accountUid: 'b'));
      uid = 'a';
      await service.deleteAll();

      expect(await service.loadLocal(), isEmpty);
      expect(deleteRequests, 1);

      expect(await service.synchronize(), isEmpty);
      expect(deleteRequests, 2);
      expect(
        getRequests,
        0,
        reason: 'deleted remote rows must not be re-imported',
      );

      deleteSucceeds = true;
      expect(await service.synchronize(), isEmpty);
      expect(deleteRequests, 3);
      expect(getRequests, 1);
    },
  );

  test(
    'updateDetails preserves the entry and merges conversation data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'history-update-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final service = HistoryService(
        directoryProvider: () async => directory,
        currentUidProvider: () => null,
        tokenProvider: () async => 'token',
      );
      await service.save(entry('analysis'));

      final updated = await service.updateDetails('analysis', {
        'ai_conversation': [
          {'role': 'user', 'content': '何を切る？'},
        ],
      });

      expect(updated, isNotNull);
      expect(updated!.details['ai_conversation'], isA<List<dynamic>>());
      expect((await service.loadLocal()).single.details, updated.details);
    },
  );
}
