import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/models/core_models.dart';

void main() {
  test('offline queue preserves original Firebase account across restart', () {
    const item = SyncItem(
      id: 'queue-1',
      entity: 'attendance',
      operation: 'create',
      payload: '{"id":"attendance-1"}',
      createdAt: '2026-10-28T10:00:00',
      ownerUid: 'worker-uid-1',
    );
    final restored = SyncItem.fromJson(item.toJson());
    expect(restored.ownerUid, 'worker-uid-1');
    expect(restored.payload, item.payload);
    expect(restored.id, item.id);
  });

  test('legacy offline items load without ownerUid', () {
    final item = SyncItem.fromJson(<String, dynamic>{
      'id': 'queue-legacy',
      'entity': 'attendance',
      'operation': 'create',
      'payload': '{"id":"attendance-legacy"}',
      'createdAt': '2026-10-27T10:00:00',
      'retryCount': 2,
    });
    expect(item.ownerUid, isNull);
    expect(item.retryCount, 2);
  });
}
