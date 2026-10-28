import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/operations_cache_merge.dart';

void main() {
  test('confirmed remote assignment supersedes stale cached assignment', () {
    final result = OperationsCacheMerge.merge(
      <Map<String, dynamic>>[
        {'id': 'cart-1', 'groupId': 'group-B', 'createdAt': '2026-10-28'},
      ],
      <Map<String, dynamic>>[
        {'id': 'cart-1', 'groupId': 'group-A', 'createdAt': '2026-10-28'},
      ],
      pendingIds: {},
    );
    expect(result.single['groupId'], 'group-B');
  });

  test('pending offline transfer takes priority until confirmed by server', () {
    final result = OperationsCacheMerge.merge(
      <Map<String, dynamic>>[
        {'id': 'record-2', 'status': 'pending'},
      ],
      <Map<String, dynamic>>[
        {'id': 'record-2', 'status': 'completed'},
      ],
      pendingIds: {'record-2'},
    );
    expect(result.single['status'], 'completed');
  });

  test('records outside the limited server query remain cached', () {
    final result = OperationsCacheMerge.merge(
      <Map<String, dynamic>>[
        {'id': 'recent', 'status': 'synced'},
      ],
      <Map<String, dynamic>>[
        {'id': 'old', 'status': 'cached'},
      ],
      pendingIds: {},
    );
    expect(result.map((x) => x['id']).toSet(), {'recent', 'old'});
  });
}
