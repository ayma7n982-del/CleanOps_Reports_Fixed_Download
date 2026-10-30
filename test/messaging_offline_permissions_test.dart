import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:solid_waste_operations/core/models/core_models.dart';
import 'package:solid_waste_operations/core/services/config_service.dart';
import 'package:solid_waste_operations/core/services/local_store.dart';
import 'package:solid_waste_operations/core/services/messaging_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('supervisor messages are persisted offline as pending, never falsely sent',
      () async {
    final directory = await Directory.systemTemp.createTemp('cleanops_messages_');
    Hive.init(directory.path);
    final box = await Hive.openBox('messages_offline');
    final store = LocalStore(box);
    final config = ConfigService(store);
    final supervisor = AppUser(
      id: 'supervisor-message',
      username: 'supervisor-message',
      name: 'Supervisor',
      role: 'group_supervisor',
      scope: 'assigned_only',
      groupId: 'group-a',
      policies: const {},
    );
    final messaging = MessagingService(store, config);
    MessagingService? restored;
    try {
      await messaging.attachUser(supervisor);
      await expectLater(
        messaging.sendBroadcast(
          content: 'Unauthorized group attempt',
          type: 'info',
          groupId: 'group-b',
        ),
        throwsStateError,
      );
      expect(messaging.messages, isEmpty);

      await messaging.sendBroadcast(
        content: 'Morning group reminder',
        type: 'info',
        groupId: 'group-a',
      );
      expect(messaging.messages, hasLength(1));
      expect(messaging.messages.single.deliveryStatus, 'pending');
      expect(store.cachedMessages(supervisor.id), hasLength(1));

      messaging.dispose();
      restored = MessagingService(store, config);
      await restored.attachUser(supervisor);
      expect(restored.messages, hasLength(1));
      expect(restored.messages.single.deliveryStatus, 'pending');
      expect(restored.messages.single.targetGroupId, 'group-a');
    } finally {
      restored?.dispose();
      await box.close();
      await directory.delete(recursive: true);
    }
  });
}
