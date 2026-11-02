import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:solid_waste_operations/core/services/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('an empty authoritative roster survives restart and cannot restore a transferred worker', () async {
    final directory = await Directory.systemTemp.createTemp('worker_roster_');
    Hive.init(directory.path);
    final box = await Hive.openBox('worker_roster');
    try {
      final store = LocalStore(box);
      await store.saveWorkerRoster('head-a', 'group-a', [
        {'id': 'worker-a', 'name': 'Worker A', 'groupId': 'group-a'},
      ]);
      // The live old-group snapshot becomes empty after an atomic transfer.
      await store.saveWorkerRoster('head-a', 'group-a', []);
      await store.saveWorkerRoster('head-b', 'group-b', [
        {'id': 'worker-a', 'name': 'Worker A', 'groupId': 'group-b'},
      ]);
      final restored = LocalStore(box);
      expect(restored.hasWorkerRoster('head-a', 'group-a'), isTrue);
      expect(restored.cachedWorkerRoster('head-a', 'group-a'), isEmpty);
      expect(
        restored.cachedWorkerRoster('head-b', 'group-b').single['id'],
        'worker-a',
      );
      expect(restored.hasWorkerRoster('head-c', 'group-b'), isFalse);
    } finally {
      await box.close();
      await directory.delete(recursive: true);
    }
  });
}
