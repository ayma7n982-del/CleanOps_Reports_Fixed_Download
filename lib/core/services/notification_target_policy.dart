import '../models/core_models.dart';
import 'operational_insights.dart';

/// Presentation checks supplement, and never replace, Firestore read rules.
class NotificationTargetPolicy {
  static const features = {
    'emergency': 'emergency',
    'trip': 'trips',
    'attendance': 'attendance',
    'leave': 'leave',
    'street_photo': 'streets',
    'container': 'containers',
    'group': 'groups',
    'worker': 'workers',
    'dumpsite': 'dumpsite',
    'cycle': 'cycle',
  };

  static bool addressedTo(AppUser user, NotificationItem notice) =>
      user.isActive &&
      user.can('notifications', 'view') &&
      (notice.targetUserId == null ||
          notice.targetUserId!.isEmpty ||
          notice.targetUserId == user.id) &&
      (notice.targetRole == null ||
          notice.targetRole!.isEmpty ||
          notice.targetRole == user.role);

  static bool canOpen(
    AppUser user,
    NotificationItem notice,
    Map<String, dynamic> record, {
    bool verifiedRecipient = false,
  }) {
    final entity = notice.sourceEntity;
    final feature = features[entity];
    if (!addressedTo(user, notice) ||
        feature == null ||
        !user.can(feature, 'view') ||
        record['_entity'] != entity ||
        record['isDeleted'] == true)
      return false;
    if (entity == 'emergency') {
      // Existing SOS management access also includes closed incidents.
      if (user.role == 'donor_manager' || user.role == 'jsc_coordinator')
        return true;
      if (user.role == 'municipality_coordinator' &&
          (record['municipalityCoordinatorId'] == user.id || verifiedRecipient))
        return true;
    }
    return OperationalInsights.visibleToUser(
      record,
      role: user.role,
      userId: user.id,
      scope: user.scope,
      groupId: user.groupId,
    );
  }
}
