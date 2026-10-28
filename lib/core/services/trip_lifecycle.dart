class TripLifecycle {
  static const targetMinuteOptions = <int>[30, 60, 90, 120, 180, 240];
  static const activeStatuses = <String>{
    'pending', 'scheduled', 'assigned', 'active', 'open',
    'in_progress', 'in-progress', 'delayed', 'late', 'overdue',
  };

  static Map<String, dynamic> startFields({
    required DateTime startedAt,
    required int targetMinutes,
  }) {
    if (!targetMinuteOptions.contains(targetMinutes)) {
      throw ArgumentError.value(targetMinutes, 'targetMinutes', 'Unsupported trip target duration.');
    }
    final start = startedAt.toUtc();
    return <String, dynamic>{
      'status': 'in_progress',
      'startedAt': start.toIso8601String(),
      'deadlineAt': start.add(Duration(minutes: targetMinutes)).toIso8601String(),
      'targetDurationMinutes': targetMinutes,
    };
  }

  static Map<String, dynamic> completionFields({
    required DateTime completedAt,
    required String completedBy,
  }) {
    final actor = completedBy.trim();
    if (actor.isEmpty) throw ArgumentError('completedBy is required.');
    return <String, dynamic>{
      'status': 'completed',
      'completedAt': completedAt.toUtc().toIso8601String(),
      'completedBy': actor,
    };
  }

  static bool canSupervisorComplete({
    required Map<String, dynamic> trip,
    required String supervisorId,
    required String groupId,
  }) {
    if (trip['_entity'] != 'trip' || trip['isDeleted'] == true) return false;
    final status = '${trip['status'] ?? ''}'.trim().toLowerCase();
    if (!activeStatuses.contains(status)) return false;
    final assignedGroup = '${trip['groupId'] ?? ''}'.trim();
    return supervisorId.trim().isNotEmpty &&
        groupId.trim().isNotEmpty &&
        assignedGroup == groupId.trim();
  }
}
