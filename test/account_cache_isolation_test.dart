import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:solid_waste_operations/core/models/core_models.dart';
import 'package:solid_waste_operations/core/services/auth_service.dart';
import 'package:solid_waste_operations/core/services/config_service.dart';
import 'package:solid_waste_operations/core/services/data_service.dart';
import 'package:solid_waste_operations/core/services/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box box;
  late LocalStore store;
  const manager = AppUser(
      id: 'manager',
      username: 'manager',
      name: 'Manager',
      role: 'donor_manager',
      scope: 'all',
      policies: {});
  const worker = AppUser(
      id: 'worker',
      username: 'worker',
      name: 'Worker',
      role: 'worker',
      scope: 'assigned_only',
      groupId: 'group-a',
      policies: {});

  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('cleanops_account_cache_');
    Hive.init(directory.path);
    box = await Hive.openBox('cache');
    store = LocalStore(box);
  });
  tearDown(() async {
    await box.close();
    await directory.delete(recursive: true);
  });

  test(
      'manager caches are hidden from worker and restored only for original account',
      () async {
    await store.saveCachedUser(manager);
    await store.saveCachedOperations([
      {'id': 'private-trip'}
    ]);
    await store.saveCachedContainers([
      {'id': 'private-container'}
    ]);
    await store.saveNotifications([
      const NotificationItem(
        id: 'private-notice',
        title: 'SOS',
        body: 'Private',
        level: 'urgent',
        createdAt: '2026-10-30',
      )
    ]);
    await store.saveLastSync('manager-sync');
    await store.saveLastDataRefresh('2026-10-30');
    await store.saveQueue([
      const SyncItem(
          id: 'pending-manager',
          ownerUid: 'manager',
          entity: 'trip',
          operation: 'create',
          payload: '{}',
          createdAt: '2026-10-30')
    ]);

    await store.clearCachedUser();
    expect(store.cachedOperations(), isEmpty);
    await store.saveCachedUser(worker);
    expect(store.cachedOperations(), isEmpty);
    expect(store.cachedContainers(), isEmpty);
    expect(store.notifications(), isEmpty);
    expect(store.lastDataRefresh(), isEmpty);
    expect(store.lastSync(), isNot('manager-sync'));
    expect(store.queue().single.ownerUid, 'manager');
    await store.saveCachedOperations([
      {'id': 'worker-trip'}
    ]);

    await store.saveCachedUser(manager);
    final reopened = LocalStore(box);
    expect(reopened.cachedOperations().single['id'], 'private-trip');
    expect(reopened.cachedContainers().single['id'], 'private-container');
    expect(reopened.notifications().single.id, 'private-notice');
    expect(reopened.queue().single.id, 'pending-manager');
  });

  test('role or group changes cannot reuse an earlier authorization scope',
      () async {
    await store.saveCachedUser(worker);
    await store.saveCachedOperations([
      {'id': 'group-a-trip'}
    ]);
    final transferred =
        AppUser.fromJson({...worker.toJson(), 'groupId': 'group-b'});
    await store.saveCachedUser(transferred);
    expect(store.cachedOperations(), isEmpty);
    final promoted = AppUser.fromJson(
        {...worker.toJson(), 'role': 'municipality_coordinator'});
    await store.saveCachedUser(promoted);
    expect(store.cachedOperations(), isEmpty);
  });

  test(
      'legacy caches without a known owner are preserved but never assigned to a user',
      () async {
    await box.put(
        'operations_cache',
        jsonEncode([
          {'id': 'unknown-owner'}
        ]));
    await store.saveCachedUser(worker);
    expect(store.cachedOperations(), isEmpty);
    expect(box.containsKey('operations_cache'), isTrue);
  });

  test(
      'live DataService state clears on logout and switches without merging previous account',
      () async {
    final auth = AuthService(store);
    final data = DataService(store, ConfigService(store));
    try {
      await store.saveCachedUser(manager);
      await store.saveCachedOperations([
        {'id': 'manager-only'}
      ]);
      auth.currentUser = manager;
      data.bindAuth(auth);
      expect(data.operations.single['id'], 'manager-only');
      auth.currentUser = null;
      auth.notifyListeners();
      expect(data.operations, isEmpty);
      expect(data.notifications, isEmpty);
      await store.saveCachedUser(worker);
      auth.currentUser = worker;
      auth.notifyListeners();
      expect(data.operations, isEmpty);
      await data.enqueue('trip', 'create', {'id': 'worker-local-trip'});
      expect(store.queue().single.ownerUid, 'worker');
      auth.currentUser = manager;
      auth.notifyListeners();
      expect(data.operations.single['id'], 'manager-only');
      expect(store.queue().single.ownerUid, 'worker');
    } finally {
      data.dispose();
      auth.dispose();
    }
  });
}
