/// Conservative, read-only operational risk signals for the local assistant.
///
/// Counts are limited to documents the caller was authorized to read.
/// A trip is overdue only when an explicit completion deadline and an
/// unfinished status are both present. Scheduled start times are not deadlines.
class OperationalTripReview {
  final int assessable;
  final int overdue;
  const OperationalTripReview({required this.assessable, required this.overdue});
}

class OperationalInsights {
  static const _unfinishedTripStatuses = <String>{
    'pending', 'scheduled', 'assigned', 'active', 'open',
    'in_progress', 'in-progress', 'delayed', 'late', 'overdue',
  };

  static int supervisedGroupsWithoutWorkers(Iterable<Map<String, dynamic>> users) {
    final supervisedGroups = <String>{};
    final workerGroups = <String>{};
    for (final user in users) {
      if (user['isActive'] == false) continue;
      final group = '${user['groupId'] ?? ''}'.trim();
      if (group.isEmpty) continue;
      if (user['role'] == 'group_supervisor') supervisedGroups.add(group);
      if (user['role'] == 'worker') workerGroups.add(group);
    }
    return supervisedGroups.difference(workerGroups).length;
  }

  static OperationalTripReview reviewTrips(
    Iterable<Map<String, dynamic>> operations, {
    required DateTime now,
  }) {
    var assessable = 0;
    var overdue = 0;
    for (final trip in operations) {
      if (trip['_entity'] != 'trip' || trip['isDeleted'] == true) continue;
      final status = '${trip['status'] ?? ''}'.trim().toLowerCase();
      if (!_unfinishedTripStatuses.contains(status)) continue;
      final deadline = _date(
        trip['deadlineAt'] ?? trip['dueAt'] ?? trip['expectedCompletionAt'] ??
        trip['expectedArrivalAt'] ?? trip['plannedEndAt'],
      );
      if (deadline == null) continue;
      assessable++;
      if (deadline.isBefore(now)) overdue++;
    }
    return OperationalTripReview(assessable: assessable, overdue: overdue);
  }


  /// UI and assistant visibility filter. Firestore Security Rules are still
  /// authoritative: client filtering alone does not replace server permissions.
  static bool visibleToUser(
    Map<String, dynamic> record, {
    required String role,
    required String userId,
    required String scope,
    String? groupId,
  }) {
    if (record['isDeleted'] == true) return false;
    if (record['_entity'] == 'notification') {
      final recipient = '${record['targetUserId'] ?? ''}'.trim();
      return recipient.isNotEmpty && recipient == userId &&
          record['targetRole'] == role;
    }
    if (role == 'donor_manager') return true;
    if (role == 'jsc_coordinator') {
      final assigned = scope.trim();
      if (assigned.isEmpty || assigned == 'all' || assigned == 'assigned_only') {
        return false;
      }
      final council = '${record['councilName'] ?? record['councilId'] ?? ''}'.trim();
      final municipality = '${record['municipalityName'] ?? record['municipality'] ?? record['municipalityId'] ?? ''}'.trim();
      return council == assigned || municipality == assigned;
    }
    if (role == 'municipality_coordinator') {
      if ('${record['municipalityCoordinatorId'] ?? ''}'.trim() == userId) return true;
      final assigned = scope.trim();
      if (assigned.isEmpty || assigned == 'all' || assigned == 'assigned_only') return false;
      final municipality = '${record['municipalityName'] ?? record['municipality'] ?? record['municipalityId'] ?? ''}'.trim();
      return municipality == assigned;
    }
    if (role == 'group_supervisor' || role == 'worker') {
      final assigned = (groupId ?? '').trim();
      return assigned.isNotEmpty && '${record['groupId'] ?? ''}'.trim() == assigned;
    }
    return false;
  }

  static bool isOpenAlert(Map<String, dynamic> record) {
    if (record['isDeleted'] == true) return false;
    final status = '${record['status'] ?? ''}'.toLowerCase().trim();
    return !const {'closed', 'resolved', 'secured', 'referred_to_eod', 'cancelled', 'dismissed'}
        .contains(status);
  }

  static int alertPriority(Map<String, dynamic> record) {
    final severity = '${record['statusLevel'] ?? record['level'] ?? ''}'.toLowerCase();
    if (record['_entity'] == 'emergency' || severity == 'critical' ||
        severity == 'urgent') return 0;
    if (severity == 'high' || severity == 'warning') return 1;
    return 2;
  }

  static String alertIncidentKey(Map<String, dynamic> record, String documentId) {
    final reference = '${record['sourceId'] ?? record['emergencyId'] ?? ''}'.trim();
    if (reference.isNotEmpty && record['sourceEntity'] == 'emergency') return 'emergency:$reference';
    if (record['_entity'] == 'emergency') return 'emergency:$documentId';
    return 'notification:$documentId';
  }

  static DateTime? _date(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
