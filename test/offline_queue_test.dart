import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:solid_waste_operations/core/models/core_models.dart';
import 'package:solid_waste_operations/core/services/config_service.dart';
import 'package:solid_waste_operations/core/services/data_service.dart';
import 'package:solid_waste_operations/core/services/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({Directory directory, Box box, LocalStore store})> openStore(
    String suffix,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'cleanops_queue_$suffix',
    );
    Hive.init(directory.path);
    final box = await Hive.openBox('queue_$suffix');
    return (directory: directory, box: box, store: LocalStore(box));
  }

  test('offline operations remain in the persistent queue without false sync',
      () async {
    final fixture = await openStore('offline');
    final service = DataService(
      fixture.store,
      ConfigService(fixture.store),
    );
    try {
      service.online = false;
      await service.enqueue('trip', 'create', {
        'id': 'offline-trip-1',
        'groupId': 'g1',
        'createdAt': '2026-10-28T09:00:00',
      });

      expect(service.queue.length, 1);
      expect(fixture.store.queue().length, 1);
      expect(
        jsonDecode(fixture.store.queue().first.payload)['id'],
        'offline-trip-1',
      );
      expect(
        service.operations.any((item) => item['id'] == 'offline-trip-1'),
        isTrue,
      );

      await service.sync();

      expect(fixture.store.queue().length, 1);
      expect(service.lastSync, 'لم تتم المزامنة بعد');
    } finally {
      service.dispose();
      await fixture.box.close();
      await fixture.directory.delete(recursive: true);
    }
  });

  test('offline queue survives restart and clears only after online dispatch succeeds',
      () async {
    final fixture = await openStore('reconnect');
    final offline = DataService(
      fixture.store,
      ConfigService(fixture.store),
    );
    try {
      offline.online = false;
      await offline.enqueue('trip', 'create', {
        'id': 'offline-trip-2',
        'groupId': 'g1',
        'status': 'in_progress',
        'createdAt': '2026-10-28T09:05:00',
      });
      expect(fixture.store.queue(), hasLength(1));

      offline.dispose();

      final dispatched = <Map<String, dynamic>>[];
      final online = DataService(
        fixture.store,
        ConfigService(fixture.store),
        syncItemOverride: (
          SyncItem item,
          Map<String, dynamic> payload,
        ) async {
          expect(item.entity, 'trip');
          dispatched.add(Map<String, dynamic>.from(payload));
        },
      );
      try {
        // Equivalent to app state restored before connectivity/auth callbacks.
        online.queue = fixture.store.queue();
        online.operations = fixture.store.cachedOperations();
        online.lastSync = fixture.store.lastSync();
        online.online = true;

        await online.sync();

        expect(dispatched, hasLength(1));
        expect(dispatched.single['id'], 'offline-trip-2');
        expect(online.queue, isEmpty);
        expect(fixture.store.queue(), isEmpty);
        expect(online.lastSync, isNot('لم تتم المزامنة بعد'));
      } finally {
        online.dispose();
      }
    } finally {
      await fixture.box.close();
      await fixture.directory.delete(recursive: true);
    }
  });

  test('failed online dispatch keeps the item queued for automatic retry',
      () async {
    final fixture = await openStore('retry');
    final service = DataService(
      fixture.store,
      ConfigService(fixture.store),
      syncItemOverride: (
        SyncItem item,
        Map<String, dynamic> payload,
      ) async {
        throw StateError('temporary network failure');
      },
    );
    try {
      service.online = false;
      await service.enqueue('trip', 'update', {
        'id': 'offline-trip-3',
        'groupId': 'g1',
        'status': 'completed',
      });
      expect(fixture.store.queue(), hasLength(1));

      service.online = true;
      await service.sync();

      expect(service.queue, hasLength(1));
      expect(fixture.store.queue(), hasLength(1));
      expect(service.lastSync, 'لم تتم المزامنة بعد');
    } finally {
      service.dispose();
      await fixture.box.close();
      await fixture.directory.delete(recursive: true);
    }
  });
}
