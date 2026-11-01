import '../models/core_models.dart';

enum FeatureDestination {
  attendanceEntry, attendanceReport, leaveEntry, leaveReport,
  tripEntry, tripRecords, streetEntry, streetRecords,
  emergencyEntry, emergencyRecords, containers, groups, reports,
  dumpsites, cycles, messages,
}

/// A task always resolves to its own content, never a generic role dashboard.
/// UI gating does not replace the destination's existing write/rules checks.
class FeatureRoutePolicy {
  static FeatureDestination? resolve(AppUser user, String feature) {
    if (!user.can(feature, 'view')) return null;
    final fieldEntry = user.role == 'group_supervisor' &&
        user.can(feature, 'create') &&
        (feature != 'leave' || user.can('attendance', 'create'));
    return switch (feature) {
      'attendance' => fieldEntry ? FeatureDestination.attendanceEntry : FeatureDestination.attendanceReport,
      'leave' => fieldEntry ? FeatureDestination.leaveEntry : FeatureDestination.leaveReport,
      'trips' => fieldEntry ? FeatureDestination.tripEntry : FeatureDestination.tripRecords,
      'streets' => fieldEntry ? FeatureDestination.streetEntry : FeatureDestination.streetRecords,
      'emergency' => fieldEntry ? FeatureDestination.emergencyEntry : FeatureDestination.emergencyRecords,
      'containers' => FeatureDestination.containers,
      'workers' => FeatureDestination.groups,
      'reports' => FeatureDestination.reports,
      'dumpsite' => FeatureDestination.dumpsites,
      'cycle' => user.role == 'donor_manager' ? FeatureDestination.cycles : null,
      'messages' => FeatureDestination.messages,
      _ => null,
    };
  }

  static String label(AppUser user, String feature) => switch (resolve(user, feature)) {
    FeatureDestination.attendanceEntry => 'تسجيل الحضور والغياب',
    FeatureDestination.attendanceReport => 'سجل الحضور والغياب',
    FeatureDestination.leaveEntry => 'تسجيل الإجازة أو الإذن',
    FeatureDestination.leaveReport => 'سجل الإجازات والأذونات',
    FeatureDestination.tripEntry => 'تسجيل نقلة',
    FeatureDestination.tripRecords => 'سجل النقلات',
    FeatureDestination.streetEntry => 'توثيق الشوارع',
    FeatureDestination.streetRecords => 'سجل توثيق الشوارع',
    FeatureDestination.emergencyEntry => 'بلاغ طارئ',
    FeatureDestination.emergencyRecords => 'البلاغات والطوارئ',
    _ => '',
  };
}
