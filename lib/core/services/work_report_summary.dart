import 'dart:convert';

import 'worker_roster.dart';

/// One daily report covers one group and one shift. Counts come exclusively
/// from operational records, never from other reports or editable counters.
class WorkReportSummary {
  final String groupId, shift;
  final DateTime day;
  final List<Map<String, dynamic>> attendanceRecords, tripRecords;
  final List<String> issues;
  final int present, absent, specialLeave, sickLeave, otherAbsence;
  final int completedTrips, activeTrips, cancelledTrips, missingWorkers;
  final bool serverConfirmed, pendingRoster;
  final String fingerprint;

  WorkReportSummary._({
    required this.groupId,
    required this.shift,
    required this.day,
    required this.attendanceRecords,
    required this.tripRecords,
    required this.issues,
    required this.present,
    required this.absent,
    required this.specialLeave,
    required this.sickLeave,
    required this.otherAbsence,
    required this.completedTrips,
    required this.activeTrips,
    required this.cancelledTrips,
    required this.missingWorkers,
    required this.serverConfirmed,
    required this.pendingRoster,
    required this.fingerprint,
  });

  static DateTime? date(dynamic value) {
    if (value is DateTime) return value.toLocal();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.tryParse('${value ?? ''}')?.toLocal();
  }

  static String dayKey(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  static String text(dynamic value) => '${value ?? ''}'.trim();
  static bool isWorkReport(Map<String, dynamic> r) =>
      r['_entity'] == 'work_report' ||
      (r['_entity'] == 'report' && r['reportKind'] == 'work_report');

  bool get hasAttendance => attendanceRecords.isNotEmpty;
  bool get hasPendingSources =>
      pendingRoster ||
      [
        ...attendanceRecords,
        ...tripRecords,
      ].any((r) => r['_pendingSource'] == true);
  bool get readyForSubmission =>
      hasAttendance && issues.isEmpty && serverConfirmed && !hasPendingSources;

  Map<String, dynamic> get counts => {
    'attendance': hasAttendance ? present : null,
    'absence': hasAttendance ? absent : null,
    'specialLeave': hasAttendance ? specialLeave : null,
    'sickLeave': hasAttendance ? sickLeave : null,
    'otherAbsence': hasAttendance ? otherAbsence : null,
    // Zero is meaningful only when the complete group query reached the server.
    'trips': serverConfirmed || tripRecords.isNotEmpty ? completedTrips : null,
  };

  Map<String, dynamic> snapshot() => {
    'version': 1,
    'groupId': groupId,
    'day': dayKey(day),
    'shift': shift,
    'fingerprint': fingerprint,
    'capturedAt': DateTime.now().toIso8601String(),
    'serverConfirmed': serverConfirmed,
    'pendingSources': hasPendingSources,
    'needsReview': !readyForSubmission,
    'issues': issues,
    'missingWorkers': missingWorkers,
    'activeTrips': activeTrips,
    'cancelledTrips': cancelledTrips,
    'counts': counts,
    'attendanceIds': attendanceRecords.map((r) => text(r['id'])).toList()
      ..sort(),
    'tripIds': tripRecords.map((r) => text(r['id'])).toList()..sort(),
    'tripDateBasis': 'startedAt_or_createdAt',
  };

  static WorkReportSummary build({
    required Iterable<Map<String, dynamic>> records,
    required String groupId,
    required DateTime day,
    required String shift,
    required bool serverConfirmed,
    DateTime? now,
  }) {
    final issues = <String>[];
    final attendance = <Map<String, dynamic>>[],
        trips = <Map<String, dynamic>>[];
    final byId = <String, Map<String, dynamic>>{};
    var pendingRoster = false;
    final selectedDay = dayKey(day);
    for (final r in records) {
      if (text(r['groupId']) != groupId || groupId.isEmpty) continue;
      final id = text(r['id']);
      if (id.isNotEmpty) byId[id] = r;
    }
    final roster = WorkerRoster.forGroup(
      byId.values,
      groupId,
    ).map((r) => r['id']!).toSet();
    final aliases = <String, String>{};
    final employeeOwners = <String, Set<String>>{};
    for (final r in byId.values.where((r) => r['_entity'] == 'worker')) {
      final id = text(r['id']);
      final canonical = text(r['canonicalWorkerId'] ?? r['userId'] ?? r['id']);
      if (canonical.isNotEmpty) aliases[id] = canonical;
      final employeeId = text(r['employeeId']);
      if (r['rosterSource'] == 'users' && employeeId.isNotEmpty) {
        employeeOwners.putIfAbsent(employeeId, () => <String>{}).add(canonical);
      }
    }
    for (final e in employeeOwners.entries) {
      if (e.value.length == 1) aliases[e.key] = e.value.single;
    }
    var missingShift = 0, invalidIdentity = 0;
    final byWorker = <String, List<Map<String, dynamic>>>{};
    for (final r in byId.values) {
      final entity = text(r['_entity']);
      if (entity == 'worker' &&
          r['_pendingSource'] == true &&
          dayKey(now ?? DateTime.now()) == selectedDay)
        pendingRoster = true;
      if (r['isDeleted'] == true ||
          !const {'attendance', 'trip'}.contains(entity))
        continue;
      final d = date(
        entity == 'attendance'
            ? (r['workDate'] ??
                  r['attendanceDate'] ??
                  r['date'] ??
                  r['createdAt'])
            : (r['workDate'] ?? r['startedAt'] ?? r['createdAt']),
      );
      if (d == null || dayKey(d) != selectedDay) continue;
      if (text(r['shift']).isEmpty) {
        missingShift++;
        continue;
      }
      if (text(r['shift']) != shift) continue;
      if (entity == 'trip') {
        trips.add(r);
        continue;
      }
      attendance.add(r);
      final rawWorker = text(r['workerId']);
      final worker = aliases[rawWorker] ?? rawWorker;
      if (worker.isEmpty) {
        invalidIdentity++;
        continue;
      }
      byWorker.putIfAbsent(worker, () => []).add(r);
    }
    var present = 0, absent = 0, special = 0, sick = 0, other = 0;
    var conflicts = 0, invalidStatus = 0;
    const accepted = {
      'present',
      'absent',
      'leave',
      'permission',
      'excused_absence',
      'unexcused_absence',
      'external_task',
      'sick_leave',
      'special_leave',
    };
    for (final rows in byWorker.values) {
      // A repeated record with the same status counts once; conflicting records
      // cannot silently select a winner based on upload order.
      final states = rows.map((r) => text(r['status'])).toSet();
      final leaveTypes = rows.map((r) => text(r['leaveType'])).toSet();
      if (states.length > 1 ||
          (states.first == 'leave' && leaveTypes.length > 1)) {
        conflicts++;
        continue;
      }
      final status = states.first;
      if (!accepted.contains(status)) {
        invalidStatus++;
        continue;
      }
      if (status == 'present') {
        present++;
      } else if (status == 'special_leave' || status == 'permission') {
        special++;
      } else if (status == 'sick_leave' ||
          (status == 'leave' && leaveTypes.first == 'sick')) {
        sick++;
      } else if (status == 'leave') {
        special++;
      } else if (status == 'absent' || status == 'unexcused_absence') {
        absent++;
      } else {
        other++;
      }
    }
    var completed = 0, active = 0, cancelled = 0, unknownTrips = 0;
    for (final r in trips) {
      final status = text(r['status']).toLowerCase();
      if (const {'completed', 'done', 'closed'}.contains(status)) {
        completed++;
      } else if (const {'cancelled', 'canceled', 'rejected'}.contains(status)) {
        cancelled++;
      } else if (const {
        'pending',
        'scheduled',
        'assigned',
        'active',
        'open',
        'in_progress',
        'in-progress',
        'delayed',
        'late',
        'overdue',
      }.contains(status)) {
        active++;
      } else {
        unknownTrips++;
      }
    }
    // Today's roster helps detect an unfinished sheet. The current roster must
    // not be used to invent historical absences after workers have moved groups.
    final checkRoster = dayKey(now ?? DateTime.now()) == selectedDay;
    final missing = checkRoster
        ? roster.difference(byWorker.keys.toSet()).length
        : 0;
    if (attendance.isEmpty)
      issues.add('لم يُسجّل كشف حضور لهذه المجموعة والوردية والتاريخ.');
    if (missing > 0)
      issues.add('لم تُحدد حالة $missing من العمال المسجلين في المجموعة.');
    if (conflicts > 0)
      issues.add('يوجد تعارض في حالات $conflicts من العمال؛ صحح كشف المصدر.');
    if (invalidIdentity > 0 || invalidStatus > 0)
      issues.add('توجد سجلات حضور بمعرّف أو حالة غير مكتملة.');
    if (missingShift > 0)
      issues.add('يوجد $missingShift سجلًا دون وردية؛ لم يُضم إلى الأعداد.');
    if (unknownTrips > 0)
      issues.add('توجد $unknownTrips نقلة بحالة غير معروفة؛ راجع سجل النقلات.');
    if (groupId.isEmpty || shift.isEmpty) issues.add('اختر المجموعة والوردية.');
    final signatureRows =
        [...attendance, ...trips]
            .map(
              (r) => jsonEncode([
                text(r['id']),
                text(r['_entity']),
                text(r['workerId']),
                text(r['status']),
                text(r['leaveType']),
                text(r['shift']),
                text(r['completedAt']),
                text(r['workDate']),
                text(r['startedAt']),
                text(r['createdAt']),
              ]),
            )
            .toList()
          ..sort();
    final signature = jsonEncode([
      groupId,
      selectedDay,
      shift,
      signatureRows,
      missing,
      issues,
    ]);
    // Stable change detector, not a security or authorization token.
    var hash = 0;
    for (final unit in signature.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return WorkReportSummary._(
      groupId: groupId,
      shift: shift,
      day: day,
      attendanceRecords: attendance,
      tripRecords: trips,
      issues: issues,
      present: present,
      absent: absent,
      specialLeave: special,
      sickLeave: sick,
      otherAbsence: other,
      completedTrips: completed,
      activeTrips: active,
      cancelledTrips: cancelled,
      missingWorkers: missing,
      serverConfirmed: serverConfirmed,
      pendingRoster: pendingRoster,
      fingerprint: hash.toRadixString(16),
    );
  }
}
