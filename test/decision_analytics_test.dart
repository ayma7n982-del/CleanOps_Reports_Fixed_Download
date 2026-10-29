import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/decision_analytics.dart';

final now = DateTime(2026, 10, 29, 10);
Map<String, dynamic> group(String id, String owner, {String number = '1'}) =>
  {'id': id, '_entity': 'group', 'name': id, 'number': number,
    'municipalityCoordinatorId': owner};
Map<String, dynamic> worker(String id, String group) =>
  {'id': id, '_entity': 'worker', 'name': id, 'groupId': group};
DecisionAnalytics calc(List<DecisionRow> ops, {List<DecisionRow> containers = const [],
    List<DecisionRow> dumpsites = const [], DateTime? at}) =>
  DecisionAnalytics.calculate(operations: ops, users: [], containers: containers,
    dumpsites: dumpsites, trips: [], cycles: [], now: at ?? now,
    shiftText: '08:00 - 16:00');
void main() {
  test('operational roster takes priority over login accounts in the same group', () {
    final a = DecisionAnalytics.calculate(operations: [group('a', 'm'),worker('roster', 'a')],
      users: [{'id':'login','role':'worker','groupId':'a'}], containers: [],
      dumpsites: [], trips: [], cycles: [], now: now, shiftText:'08:00 - 16:00');
    expect(a.workers,1);
    expect(a.groups.single.workers.single['id'],'roster');
  });
  test('missing attendance remains unknown rather than absent', () {
    final a = calc([group('a', 'm'), worker('w1', 'a'), worker('w2', 'a'),
      {'id': 'p', '_entity': 'attendance', 'workerId': 'w1', 'groupId': 'a',
        'createdAt': '2026-10-29T08:05:00', 'status': 'present'}]);
    expect(a.present, 1); expect(a.absent, 0); expect(a.unknown, 1);
    expect(a.attendanceRate, .5);
  });
  test('latest attendance status wins and frozen workers are excluded', () {
    final a = calc([group('a', 'm'), worker('w1', 'a'),
      {...worker('w2', 'a'), 'status': 'frozen'},
      {'id': 'old', '_entity': 'attendance', 'workerId': 'w1', 'groupId': 'a',
        'createdAt': '2026-10-29T08:05:00', 'status': 'present'},
      {'id': 'new', '_entity': 'attendance', 'workerId': 'w1', 'groupId': 'a',
        'createdAt': '2026-10-29T08:06:00', 'status': 'absent'}]);
    expect(a.workers, 1); expect(a.present, 0); expect(a.absent, 1);
  });
  test('a group with no trips is stagnant only inside an established active shift', () {
    expect(calc([group('a', 'm')]).groups.single.stagnant, isTrue);
    expect(calc([group('a', 'm')], at: DateTime(2026, 10, 29, 8, 30))
      .groups.single.stagnant, isFalse);
    expect(calc([group('a', 'm')], at: DateTime(2026, 10, 29, 17))
      .groups.single.stagnant, isFalse);
  });
  test('overnight shifts use the preceding day before midnight boundary', () {
    final shift = DecisionShift.parse(DateTime(2026, 10, 30, 1), '20:00 - 04:00');
    expect(shift.start, DateTime(2026, 10, 29, 20));
    expect(shift.contains(DateTime(2026, 10, 30, 1)), isTrue);
  });
  test('health risk requires fullSince and cannot be inferred from updatedAt', () {
    final a = calc([], containers: [
      {'id': 'old', 'status': 'full', 'fullSince': '2026-10-28T21:59:00'},
      {'id': 'unknown', 'status': 'full', 'updatedAt': '2026-10-27T00:00:00'},
      {'id': 'emptied', 'status': 'empty', 'fullSince': '2026-10-27T00:00:00'},
    ]);
    expect(a.healthHazards.map((c) => c['id']), ['old']);
  });
  test('dumpsite percentages are weighted by capacity, not a simple average', () {
    final a = calc([], dumpsites: [
      {'id': 'a', 'capacity': 100, 'fillPercentage': 100},
      {'id': 'b', 'capacity': 900, 'fillPercentage': 0},
    ]);
    expect(a.dumpsiteRate, closeTo(.1, .00001));
  });
  test('unknown quantities are never silently converted to tons', () {
    expect(DecisionGroup.tonsOf({'quantity': 20, 'quantityUnit': 'm3'}), isNull);
    expect(DecisionGroup.tonsOf({'quantity': 2000, 'quantityUnit': 'kg'}), 2);
    expect(DecisionGroup.tonsOf({'quantity': -1, 'quantityUnit': 'ton'}), isNull);
  });
  test('same group number in two municipalities never mixes workers', () {
    final a = calc([group('a', 'm1'), group('b', 'm2'),
      {...worker('w1', '1'), 'municipalityCoordinatorId': 'm1'},
      {...worker('w2', '1'), 'municipalityCoordinatorId': 'm2'}]);
    expect(a.groups[0].workers.single['id'], 'w1');
    expect(a.groups[1].workers.single['id'], 'w2');
  });
  test('empty data produces unavailable percentages and no invented recommendations', () {
    final a = calc([]);
    expect(a.attendanceRate, isNull); expect(a.emptyRate, isNull);
    expect(a.dumpsiteRate, isNull); expect(a.recommendations, isEmpty);
  });
  test('historical fullness and attendance produce evidence-backed expansion', () {
    final ops = <DecisionRow>[group('a', 'm'), worker('w1', 'a')];
    for (var day = 24; day <= 28; day++) {
      ops.add({'id': 'p$day', '_entity': 'attendance', 'workerId': 'w1',
        'groupId': 'a', 'status': 'present', 'createdAt': '2026-10-$day' 'T08:00:00'});
    }
    final a = calc(ops, containers: [
      {'id': 'c', 'groupId': 'a', 'status': 'full',
        'statusHistory': [for (var day = 24; day <= 28; day++)
          {'status': 'full', 'at': '2026-10-$day' 'T09:00:00'}]},
    ]);
    expect(a.recommendations.single.kind, 'expand_manpower');
    expect(a.recommendations.single.delta, 1);
  });
}
