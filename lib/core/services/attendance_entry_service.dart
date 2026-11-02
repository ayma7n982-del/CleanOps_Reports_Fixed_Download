import 'dart:convert';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/core_models.dart';
import 'data_service.dart';

/// One worker/day/shift identity shared by the full sheet and quick leave form.
class AttendanceEntryService {
  final DataService data;
  AttendanceEntryService(this.data);

  static String dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  static String recordId(
    String groupId,
    String shift,
    DateTime day,
    String workerId,
  ) =>
      'attendance_${groupId}_${shift.replaceAll(RegExp(r'[^0-9]'), '')}_${dayKey(day)}_$workerId';

  Future<Map<String, dynamic>?> record({
    required AppUser actor,
    required String workerId,
    required DateTime day,
  }) async {
    final groupId = actor.groupId?.trim() ?? '';
    if (groupId.isEmpty || workerId.trim().isEmpty) return null;
    final id = recordId(groupId, data.config.shift, day, workerId);
    Map<String, dynamic>? result;
    for (final row in data.operations) {
      if (row['id'] == id && row['_entity'] == 'attendance')
        result = Map.of(row);
    }
    // Direct document reads cannot miss today's record due to a list limit.
    if (data.online && Firebase.apps.isNotEmpty) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('operations')
            .doc(id)
            .get()
            .timeout(const Duration(seconds: 8));
        if (snapshot.exists) result = {...snapshot.data()!, 'id': id};
      } on TimeoutException {
        // Connectivity can report online while the server is unreachable.
        // Keep local-first behavior; the durable queue will retry later.
      } on FirebaseException catch (error) {
        if (!const [
          'unavailable',
          'deadline-exceeded',
          'network-request-failed',
        ].contains(error.code))
          rethrow;
      }
    }
    // Unsynced local edits take precedence over an older server snapshot.
    for (final item in data.queue) {
      if (item.entity != 'attendance') continue;
      final payload = Map<String, dynamic>.from(
        jsonDecode(item.payload) as Map,
      );
      if (payload['id'] == id) result = {...?result, ...payload};
    }
    if (result == null || result['isDeleted'] == true) return null;
    if (result['groupId'] != groupId || result['workerId'] != workerId) {
      throw StateError('سجل العامل لا يطابق المجموعة المحددة.');
    }
    return result;
  }

  Future<bool> saveLeave({
    required AppUser actor,
    required Map<String, String> worker,
    required String status,
    required DateTime day,
    String reason = '',
    int? fromMinute,
    int? toMinute,
    required Future<bool> Function(Map<String, dynamic> previous)
    confirmReplacement,
    bool Function()? canContinue,
  }) async {
    void validate() {
      if (actor.role != 'group_supervisor' ||
          !actor.can('leave', 'view') ||
          !actor.can('leave', 'create') ||
          !actor.can('attendance', 'create')) {
        throw StateError('لا تملك صلاحية تسجيل الإجازات.');
      }
      if (data.config.stageFrozen)
        throw StateError('المرحلة مجمّدة — التعديلات التشغيلية مقفلة.');
      final groupId = actor.groupId?.trim() ?? '';
      if (groupId.isEmpty ||
          worker['groupId'] != groupId ||
          (worker['id'] ?? '').trim().isEmpty) {
        throw StateError('اختر عاملًا من مجموعتك.');
      }
      if (!const ['leave', 'permission'].contains(status))
        throw ArgumentError('نوع الإجازة غير صالح.');
      if (status == 'permission' &&
          (fromMinute == null ||
              toMinute == null ||
              fromMinute < 0 ||
              toMinute > 1440 ||
              toMinute <= fromMinute)) {
        throw ArgumentError(
          'حدد بداية الإذن ونهايته؛ يجب أن تكون النهاية بعد البداية في اليوم نفسه.',
        );
      }
    }

    validate();
    final previous = await record(
      actor: actor,
      workerId: worker['id']!,
      day: day,
    );
    if (previous != null && previous['reportedBy'] != actor.id) {
      throw StateError(
        'السجل مسجل بواسطة مشرف آخر؛ راجع منسق البلدية لتعديله.',
      );
    }
    if (previous != null &&
        previous['status'] != status &&
        !await confirmReplacement(previous))
      return false;
    if (canContinue != null && !canContinue()) return false;
    validate();
    if (previous != null &&
        previous['status'] == status &&
        '${previous['leaveReason'] ?? ''}' == reason.trim() &&
        (status == 'leave' ||
            (previous['permissionFromMinute'] == fromMinute &&
                previous['permissionToMinute'] == toMinute)))
      return true;
    final now = DateTime.now();
    final recordedDay = DateTime(
      day.year,
      day.month,
      day.day,
      now.hour,
      now.minute,
      now.second,
    );
    await data.enqueue('attendance', previous == null ? 'create' : 'update', {
      'id': recordId(actor.groupId!, data.config.shift, day, worker['id']!),
      'workerId': worker['id'], 'workerName': worker['name'] ?? '',
      'workerRole': worker['role'] ?? 'worker',
      if (worker['temporaryDecisionId'] != null)
        'temporaryDecisionId': worker['temporaryDecisionId'],
      'groupId': actor.groupId!,
      'groupName': worker['groupName'] ?? actor.groupId!,
      'municipalityName': actor.scope == 'assigned_only'
          ? (worker['municipalityName'] ?? '')
          : actor.scope,
      'municipalityCoordinatorId': actor.municipalityCoordinatorId ?? '',
      'status': status, 'leaveReason': reason.trim(),
      'permissionFromMinute': status == 'permission' ? fromMinute : null,
      'permissionToMinute': status == 'permission' ? toMinute : null,
      'checkInAt': status == 'permission' ? (previous?['checkInAt']) : null,
      'checkOutAt': status == 'permission' ? (previous?['checkOutAt']) : null,
      'checkInTime': status == 'permission' ? (previous?['checkInTime']) : null,
      'checkOutTime': status == 'permission'
          ? (previous?['checkOutTime'])
          : null,
      'ppeComplete': status == 'permission' && previous?['ppeComplete'] == true,
      'ppe': status == 'permission'
          ? (previous?['ppe'] ?? <String, bool>{})
          : <String, bool>{},
      'reportedBy': actor.id, 'shift': data.config.shift,
      // Existing reports use createdAt as the attendance date.
      'createdAt': previous?['createdAt'] ?? recordedDay.toIso8601String(),
      'attendanceDate': dayKey(day), 'recordedAt': now.toIso8601String(),
      'isDeleted': false,
    });
    return true;
  }
}
