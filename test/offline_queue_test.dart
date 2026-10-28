import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:solid_waste_operations/core/services/config_service.dart';
import 'package:solid_waste_operations/core/services/data_service.dart';
import 'package:solid_waste_operations/core/services/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline operations remain in the persistent queue without false sync', () async {
    final directory = await Directory.systemTemp.createTemp('cleanops_queue_');
    Hive.init(directory.path);
    final box = await Hive.openBox('queue_test');
    final store = LocalStore(box);
    final service = DataService(store, ConfigService(store));
    try {
      service.online = false;
      await service.enqueue('trip', 'create', {
        'id': 'offline-trip-1',
        'groupId': 'g1',
        'createdAt': '2026-10-28T09:00:00',
      });
      expect(service.queue.length, 1);
      expect(store.queue().length, 1);
      expect(jsonDecode(store.queue().first.payload)['id'], 'offline-trip-1');
      expect(service.operations.any((item) => item['id'] == 'offline-trip-1'), isTrue);
      await service.sync();
      expect(store.queue().length, 1);
      expect(service.lastSync, 'لم تتم المزامنة بعد');
    } finally {
      service.dispose();
      await box.close();
      await directory.delete(recursive: true);
    }
  });
}
