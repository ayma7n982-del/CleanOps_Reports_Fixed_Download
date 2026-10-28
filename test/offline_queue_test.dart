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


  test('offline status explains automatic retry without manual sync', () async {
    final fixture = await openStore('status');
    final service = DataService(
      fixture.store,
      ConfigService(fixture.store),
    );
    try {
      service.online = false;
      await service.enqueue('trip', 'create', {
        'id': 'offline-status-trip',
        'groupId': 'g1',
      });

      expect(service.automaticSyncStatus, contains('ستُزامن تلقائيًا'));

      service.online = true;
      expect(service.automaticSyncStatus, contains('بانتظار المزامنة التلقائية'));
    } finally {
      service.dispose();
      await fixture.box.close();
      await fixture.directory.delete(recursive: true);
    }
  });

test('cart redirect: offline equipment move persists and reconciles on reconnect',
      () async {
    final fixture = await openStore('cart_equipment');
    const coordinatorId = 'coordinator-a';
    const otherCoordinatorId = 'coordinator-b';
    await fixture.store.saveCachedEquipmentCarts(coordinatorId, [
      {
        'id': 'cart-1',
        'groupId': 'group-a',
        'municipalityCoordinatorId': coordinatorId,
        'name': 'كارة تجريبية',
      },
    ]);
    await fixture.store.saveCachedEquipmentCarts(otherCoordinatorId, [
      {
        'id': 'cart-2',
        'groupId': 'group-c',
        'municipalityCoordinatorId': otherCoordinatorId,
      },
    ]);
    final offline = DataService(fixture.store, ConfigService(fixture.store));
    try {
      offline.online = false;
      await offline.enqueue('cart_redirect', 'create', {
        'id': 'move-1',
        'cartId': 'cart-1',
        'cartCollection': 'equipment',
        'fromGroupId': 'group-a',
        'toGroupId': 'group-b',
        'municipalityCoordinatorId': coordinatorId,
        'requestedBy': coordinatorId,
      });
      expect(fixture.store.queue(), hasLength(1));
      expect(offline.hasPendingCartRedirect('cart-1', 'equipment'), isTrue);
      expect(offline.hasPendingCartRedirect('cart-1', 'operations'), isFalse);
      expect(offline.hasPendingCartRedirect('cart-2', 'equipment'), isFalse);
      expect(fixture.store.cachedEquipmentCarts(coordinatorId).single['groupId'],
          'group-a');
      expect(offline.operations.where((e) => e['_entity'] == 'cart_redirect'),
          isEmpty);

      await offline.sync();
      expect(fixture.store.queue(), hasLength(1));
      offline.dispose();

      final dispatched = <Map<String, dynamic>>[];
      final resumed = DataService(
        fixture.store,
        ConfigService(fixture.store),
        syncItemOverride: (item, payload) async {
          expect(item.entity, 'cart_redirect');
          dispatched.add(Map<String, dynamic>.from(payload));
        },
      );
      try {
        resumed.queue = fixture.store.queue();
        resumed.operations = fixture.store.cachedOperations();
        resumed.online = true;
        await resumed.sync();
        expect(dispatched, hasLength(1));
        expect(dispatched.single['cartId'], 'cart-1');
        expect(resumed.queue, isEmpty);
        expect(resumed.hasPendingCartRedirect('cart-1', 'equipment'), isFalse);
        expect(fixture.store.queue(), isEmpty);
        expect(fixture.store.cachedEquipmentCarts(coordinatorId).single['groupId'],
            'group-b');
        expect(fixture.store.cachedEquipmentCarts(otherCoordinatorId).single['groupId'],
            'group-c');
        expect(fixture.store.cachedOperations()
            .where((e) => e['_entity'] == 'cart_redirect'), isEmpty);
      } finally {
        resumed.dispose();
      }
    } finally {
      await fixture.box.close();
      await fixture.directory.delete(recursive: true);
    }
  });

  test('cart redirect: failed dispatch preserves original cart until retry succeeds',
      () async {
    final fixture = await openStore('cart_retry');
    await fixture.store.saveCachedOperations([
      {
        'id': 'cart-operations',
        '_entity': 'cart',
        'groupId': 'group-a',
        'municipalityCoordinatorId': 'coordinator-a',
      },
    ]);
    var shouldFail = true;
    final service = DataService(
      fixture.store,
      ConfigService(fixture.store),
      syncItemOverride: (item, payload) async {
        if (shouldFail) throw StateError('connection interrupted');
      },
    );
    try {
      service.operations = fixture.store.cachedOperations();
      service.online = false;
      await service.enqueue('cart_redirect', 'create', {
        'id': 'move-2',
        'cartId': 'cart-operations',
        'cartCollection': 'operations',
        'fromGroupId': 'group-a',
        'toGroupId': 'group-b',
        'municipalityCoordinatorId': 'coordinator-a',
      });
      expect(service.operations.single['groupId'], 'group-a');
      expect(service.queue, hasLength(1));

      service.online = true;
      await service.sync();
      expect(fixture.store.queue(), hasLength(1));
      expect(service.operations.single['groupId'], 'group-a');

      shouldFail = false;
      await service.sync();
      expect(service.queue, isEmpty);
      expect(fixture.store.queue(), isEmpty);
      expect(service.operations.single['groupId'], 'group-b');
      expect(fixture.store.cachedOperations().single['groupId'], 'group-b');
    } finally {
      service.dispose();
      await fixture.box.close();
      await fixture.directory.delete(recursive: true);
    }
  });
  test('JSC SOS actions persist offline and replay in the correct order', () async {
    final fixture = await openStore('jsc_sos');
    await fixture.store.saveCachedOperations([{
      'id': 'sos-local-1',
      '_entity': 'emergency',
      'status': 'urgent',
      'acknowledged': false,
    }]);
    final offline = DataService(fixture.store, ConfigService(fixture.store));
    try {
      offline.online = false;
      offline.operations = fixture.store.cachedOperations();
      await offline.enqueue('emergency', 'sos_acknowledge', {
        'id': 'sos-local-1',
        'acknowledged': true,
        'acknowledgedBy': 'jsc',
        'acknowledgedAt': '2026-10-28T09:00:00Z',
        'status': 'acknowledged',
      });
      await offline.enqueue('emergency', 'sos_close', {
        'id': 'sos-local-1',
        'acknowledged': true,
        'status': 'closed',
        'closedBy': 'jsc',
        'closedAt': '2026-10-28T10:00:00Z',
        'resolutionNote': 'Coordinated safe closure',
      });
      expect(offline.queue.map((item) => item.operation),
          ['sos_acknowledge', 'sos_close']);
      expect(offline.operations.single['status'], 'closed');
      await offline.sync();
      expect(fixture.store.queue(), hasLength(2));
      offline.dispose();

      final uploaded = <String>[];
      final resumed = DataService(
        fixture.store,
        ConfigService(fixture.store),
        syncItemOverride: (item, payload) async {
          expect(item.entity, 'emergency');
          expect(payload['id'], 'sos-local-1');
          uploaded.add(item.operation);
        },
      );
      try {
        resumed.queue = fixture.store.queue();
        resumed.operations = fixture.store.cachedOperations();
        resumed.online = true;
        await resumed.sync();
        expect(uploaded, ['sos_acknowledge', 'sos_close']);
        expect(resumed.queue, isEmpty);
        expect(fixture.store.queue(), isEmpty);
        expect(resumed.operations.single['status'], 'closed');
      } finally {
        resumed.dispose();
      }
    } finally {
      await fixture.box.close();
      await fixture.directory.delete(recursive: true);
    }
  });

  test('equipment dispatch stays pending without falsely reassigning a cart', () async {
    final fixture = await openStore('jsc_machine');
    final service = DataService(fixture.store, ConfigService(fixture.store));
    try {
      service.online = false;
      await service.enqueue('equipment_dispatch', 'dispatch', {
        'id': 'dispatch-local-1',
        'equipmentId': 'loader-1',
        'municipality': 'دير البلح',
        'requestedBy': 'jsc',
      });
      expect(fixture.store.queue(), hasLength(1));
      expect(service.operations.where(
          (e) => e['_entity'] == 'equipment_dispatch'), isEmpty);
      await service.sync();
      expect(fixture.store.queue(), hasLength(1));
    } finally {
      service.dispose();
      await fixture.box.close();
      await fixture.directory.delete(recursive: true);
    }
  });

  test('failed SOS replay reports pending confirmation, not success', () async {
    final fixture = await openStore('jsc_reject');
    final service = DataService(
      fixture.store,
      ConfigService(fixture.store),
      syncItemOverride: (item, payload) async {
        throw StateError('permission-denied');
      },
    );
    try {
      service.online = false;
      await service.enqueue('emergency', 'sos_close', {
        'id': 'sos-pending',
        'status': 'closed',
        'closedBy': 'jsc',
        'resolutionNote': 'Submitted offline',
      });
      service.online = true;
      await service.sync();
      expect(service.queue, hasLength(1));
      expect(service.automaticSyncStatus, contains('لم يؤكدها الخادم'));
      expect(fixture.store.queue(), hasLength(1));
    } finally {
      service.dispose();
      await fixture.box.close();
      await fixture.directory.delete(recursive: true);
    }
  });

  test('offline JSC equipment return leaves server assignment unchanged', () async {
    final fixture = await openStore('jsc_machine_return');
    final data = DataService(fixture.store, ConfigService(fixture.store));
    try {
      data.online = false;
      await data.enqueue('equipment_return', 'return', {
        'id':'return-local-1','equipmentId':'loader-1',
        'sourceDispatchRequestId':'dispatch-1','requestedBy':'jsc',
        'returnNote':'Mission completed',
      });
      expect(data.hasPendingEquipmentDispatch('loader-1'), isTrue);
      expect(data.operations.where((e) => e['_entity'] == 'equipment_return'),
        isEmpty);
      await data.sync();
      expect(fixture.store.queue(), hasLength(1));
    } finally {
      data.dispose();
      await fixture.box.close();
      await fixture.directory.delete(recursive:true);
    }
  });

  test('SOS clearance, reopening and closure stay in deterministic offline order', () async {
    final fixture = await openStore('jsc_sos_clear');
    final offline = DataService(fixture.store, ConfigService(fixture.store));
    try {
      offline.online = false;
      for (final action in ['sos_secure','sos_reopen','sos_close']) {
        await offline.enqueue('emergency', action, {
          'id':'sos-clear-1','updatedAt':'2026-10-28T11:00:00Z',
        });
      }
      await offline.sync();
      expect(fixture.store.queue(), hasLength(3));
      offline.dispose();
      final seen = <String>[];
      final resumed = DataService(fixture.store, ConfigService(fixture.store),
        syncItemOverride: (item, payload) async => seen.add(item.operation));
      try {
        resumed.queue = fixture.store.queue();
        resumed.operations = fixture.store.cachedOperations();
        resumed.online = true;
        await resumed.sync();
        expect(seen, ['sos_secure','sos_reopen','sos_close']);
        expect(resumed.queue, isEmpty);
      } finally {
        resumed.dispose();
      }
    } finally {
      await fixture.box.close();
      await fixture.directory.delete(recursive:true);
    }
  });

  test('L2 SOS acknowledgement persists offline before connection recovers', () async {
    final fixture = await openStore('municipality_sos_ack');
    final service = DataService(fixture.store, ConfigService(fixture.store));
    try {
      service.online = false;
      await service.enqueue('emergency', 'sos_acknowledge', {
        'id':'municipal-sos-a',
        'status':'acknowledged',
        'acknowledged':true,
        'acknowledgedBy':'coordinator',
        'acknowledgedAt':'2026-10-28T10:00:00Z',
      });
      expect(service.hasPendingEmergencyAction('municipal-sos-a'), isTrue);
      expect(fixture.store.queue(), hasLength(1));
      await service.sync();
      expect(fixture.store.queue(), hasLength(1));
    } finally {
      service.dispose();
      await fixture.box.close();
      await fixture.directory.delete(recursive: true);
    }
  });

  test('SOS notification waits until its emergency exists on the server', () async {
    final fixture = await openStore('sos_notification_dependency');
    var failEmergency = true;
    final sent = <String>[];
    final service = DataService(
      fixture.store,
      ConfigService(fixture.store),
      syncItemOverride: (item, payload) async {
        if (item.entity == 'emergency' && failEmergency) {
          throw StateError('Cannot persist emergency yet');
        }
        sent.add(item.entity);
      },
    );
    try {
      service.online = false;
      await service.enqueue('emergency', 'create', {
        'id':'sos-dependency','street':'Some street',
      });
      await service.enqueue('notification', 'urgent', {
        'id':'sos-dependency_L3','sourceEntity':'emergency',
        'sourceId':'sos-dependency','targetRole':'jsc_coordinator',
      });
      service.online = true;
      await service.sync();
      expect(service.queue, hasLength(2));
      expect(sent, isEmpty);
      expect(service.hasPendingEmergencyCreation('sos-dependency'), isTrue);

      failEmergency = false;
      await service.sync();
      expect(sent, ['emergency', 'notification']);
      expect(service.queue, isEmpty);
    } finally {
      service.dispose();
      await fixture.box.close();
      await fixture.directory.delete(recursive:true);
    }
  });

}
