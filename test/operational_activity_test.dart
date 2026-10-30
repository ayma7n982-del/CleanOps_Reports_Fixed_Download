import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/operational_activity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recent activity accepts Firestore timestamps, ISO strings and epoch values',
      () {
    final early = DateTime.utc(2026, 10, 28, 8, 0);
    final middle = DateTime.utc(2026, 10, 29, 9, 0);
    final late = DateTime.utc(2026, 10, 30, 10, 0);
    final items = <Map<String, dynamic>>[
      {'id': 'iso', 'createdAt': middle.toIso8601String()},
      {'id': 'undated', 'status': 'active'},
      {'id': 'timestamp', 'createdAt': Timestamp.fromDate(late)},
      {'id': 'milliseconds', 'createdAt': early.millisecondsSinceEpoch},
      {'id': 'seconds', 'createdAt': early.millisecondsSinceEpoch ~/ 1000},
    ];
    final ordered = OperationalActivity.ordered(items);
    expect(ordered.length, 4);
    expect(ordered.first['id'], 'timestamp');
    expect(ordered[1]['id'], 'iso');
    expect(ordered.last['id'], anyOf('seconds', 'milliseconds'));
    expect(OperationalActivity.label(items[1]), 'بدون تاريخ');
    expect(
      OperationalActivity.asDate(Timestamp.fromDate(late))!
          .isAtSameMomentAs(late),
      isTrue,
    );
  });

  test('daily count respects the local calendar and ignores undated rows', () {
    final localDay = DateTime(2026, 10, 30);
    final rows = <Map<String, dynamic>>[
      {'createdAt': DateTime(2026, 10, 30, 1)},
      {'updatedAt': DateTime(2026, 10, 30, 23, 59).toIso8601String()},
      {'createdAt': DateTime(2026, 10, 29, 23)},
      {'id': 'missing'},
    ];
    expect(OperationalActivity.countOnDate(rows, localDay), 2);
  });
}
