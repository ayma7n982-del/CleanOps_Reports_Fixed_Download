import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/work_report_summary.dart';

void main() {
  final day = DateTime(2026, 11, 2);
  Map<String, dynamic> attendance(
    String id,
    String worker,
    String status, {
    String group = 'g1',
    String shift = 'morning',
    DateTime? date,
  }) => {
    'id': id,
    '_entity': 'attendance',
    'workerId': worker,
    'status': status,
    'groupId': group,
    'shift': shift,
    'createdAt': (date ?? day).toIso8601String(),
  };
  Map<String, dynamic> trip(String id, String status) => {
    'id': id,
    '_entity': 'trip',
    'groupId': 'g1',
    'status': status,
    'shift': 'morning',
    'startedAt': day.toIso8601String(),
  };
  WorkReportSummary summary(
    List<Map<String, dynamic>> records, {
    bool confirmed = true,
    DateTime? selectedDay,
  }) => WorkReportSummary.build(
    records: records,
    groupId: 'g1',
    day: selectedDay ?? day,
    shift: 'morning',
    serverConfirmed: confirmed,
    now: day,
  );

  test(
    'counts source records and separates leave, active and cancelled trips',
    () {
      final s = summary([
        attendance('a1', 'w1', 'present'),
        attendance('a2', 'w2', 'absent'),
        attendance('a3', 'w3', 'permission'),
        attendance('a4', 'w4', 'sick_leave'),
        attendance('a5', 'w5', 'external_task'),
        trip('t1', 'completed'),
        trip('t2', 'in_progress'),
        trip('t3', 'cancelled'),
        {...trip('t4', 'completed'), 'isDeleted': true},
        {
          'id': 'r',
          '_entity': 'work_report',
          'groupId': 'g1',
          'attendance': 999,
          'trips': 999,
        },
      ]);
      expect(s.counts, {
        'attendance': 1,
        'absence': 1,
        'specialLeave': 1,
        'sickLeave': 1,
        'otherAbsence': 1,
        'trips': 1,
      });
      expect(s.activeTrips, 1);
      expect(s.cancelledTrips, 1);
      expect(s.readyForSubmission, isTrue);
    },
  );
  test('never mixes groups, days or shifts', () {
    final s = summary([
      attendance('a1', 'w1', 'present'),
      attendance('a2', 'w2', 'present', group: 'g2'),
      attendance('a3', 'w3', 'present', shift: 'evening'),
      attendance(
        'a4',
        'w4',
        'present',
        date: day.subtract(const Duration(days: 1)),
      ),
    ]);
    expect(s.present, 1);
    expect(s.attendanceRecords.length, 1);
  });
  test('duplicate attendance counts once and conflicting states require correction', () {
    final a = attendance('a1', 'w1', 'present');
    expect(
      summary([
        a,
        {...a, 'id': 'a2'},
      ]).present,
      1,
    );
    final conflict = summary([a, attendance('a2', 'w1', 'absent')]);
    expect(conflict.present, 0);
    expect(conflict.absent, 0);
    expect(conflict.issues.join(), contains('تعارض'));
    expect(conflict.readyForSubmission, isFalse);
  });
  test('missing attendance and unknown offline trip totals remain null', () {
    final s = summary([], confirmed: false);
    expect(s.counts['attendance'], isNull);
    expect(s.counts['absence'], isNull);
    expect(s.counts['trips'], isNull);
    expect(s.readyForSubmission, isFalse);
    expect(summary([]).counts['trips'], 0);
  });
  test('unified roster catches unfinished sheets without inventing historical absences', () {
    final records = [
      attendance('a1', 'w1', 'present'),
      {'id': 'w1', 'name': 'محمد', '_entity': 'worker', 'groupId': 'g1'},
      {'id': 'w2', 'name': 'أحمد', '_entity': 'worker', 'groupId': 'g1'},
    ];
    final s = summary(records);
    expect(s.missingWorkers, 1);
    expect(s.absent, 0);
    final yesterday = day.subtract(const Duration(days: 1));
    expect(
      summary([
        attendance('a2', 'w1', 'present', date: yesterday),
        ...records.skip(1),
      ], selectedDay: yesterday).missingWorkers,
      0,
    );
  });
  test('pending source corrections remain provisional', () {
    final s = summary([
      {...attendance('a1', 'w1', 'present'), '_pendingSource': true},
    ]);
    expect(s.present, 1);
    expect(s.hasPendingSources, isTrue);
    expect(s.readyForSubmission, isFalse);
  });
  test('fingerprint is order independent and changes with source state', () {
    final rows = [attendance('a1', 'w1', 'present'), trip('t1', 'in_progress')];
    final s = summary(rows);
    expect(summary(rows.reversed.toList()).fingerprint, s.fingerprint);
    expect(
      summary([rows.first, trip('t1', 'completed')]).fingerprint,
      isNot(s.fingerprint),
    );
    final saved = s.snapshot();
    rows.last['status'] = 'completed';
    expect((saved['counts'] as Map)['trips'], 0);
  });
  test('missing shift, worker identity or status cannot be guessed', () {
    for (final r in [
      attendance('a1', 'w1', 'present', shift: ''),
      attendance('a1', '', 'present'),
      attendance('a1', 'w1', 'unset'),
    ]) {
      final s = summary([r]);
      expect(s.present, 0);
      expect(s.readyForSubmission, isFalse);
    }
  });
  test('a trip completed after midnight belongs to its start day', () {
    final s = summary([
      {
        ...trip('t1', 'completed'),
        'completedAt': day.add(const Duration(days: 1)).toIso8601String(),
      },
      attendance('a1', 'w1', 'present'),
    ]);
    expect(s.completedTrips, 1);
    expect(
      summary(
        s.tripRecords,
        selectedDay: day.add(const Duration(days: 1)),
      ).completedTrips,
      0,
    );
  });
  test('repaired account aliases do not duplicate worker counts or roster coverage', () {
    final s = summary([
      {
        'id': 'uid1',
        '_entity': 'worker',
        'name': 'محمد',
        'groupId': 'g1',
        'rosterSource': 'users',
        'userId': 'uid1',
        'employeeId': 'old1',
      },
      {
        'id': 'old1',
        '_entity': 'worker',
        'name': 'محمد',
        'groupId': 'g1',
        'isDeleted': true,
        'canonicalWorkerId': 'uid1',
      },
      attendance('a1', 'uid1', 'present'),
      attendance('a2', 'old1', 'present'),
    ]);
    expect(s.present, 1);
    expect(s.missingWorkers, 0);
    expect(s.readyForSubmission, isTrue);
  });
}
