import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/operational_insights.dart';

void main() {
  test('staffing gap counts supervised groups without active workers once', () {
    final users = <Map<String, dynamic>>[
      {'role': 'group_supervisor', 'groupId': 'g1', 'isActive': true},
      {'role': 'group_supervisor', 'groupId': 'g1', 'isActive': true},
      {'role': 'group_supervisor', 'groupId': 'g2', 'isActive': true},
      {'role': 'worker', 'groupId': 'g2', 'isActive': true},
      {'role': 'worker', 'groupId': 'g1', 'isActive': false},
    ];
    expect(OperationalInsights.supervisedGroupsWithoutWorkers(users), 1);
  });

  test('overdue trips require deadline and recognized unfinished status', () {
    final now = DateTime.utc(2026, 10, 28, 12);
    final operations = <Map<String, dynamic>>[
      {'_entity': 'trip', 'status': 'pending', 'dueAt': '2026-10-28T10:00:00Z'},
      {'_entity': 'trip', 'status': 'in_progress', 'deadlineAt': DateTime.utc(2026, 10, 29)},
      {'_entity': 'trip', 'status': 'completed', 'dueAt': '2026-10-27T00:00:00Z'},
      {'_entity': 'trip', 'status': 'pending', 'scheduledAt': '2026-10-27T00:00:00Z'},
      {'_entity': 'trip', 'status': 'pending', 'dueAt': '2026-10-27T00:00:00Z', 'isDeleted': true},
      {'_entity': 'emergency', 'status': 'pending', 'dueAt': '2026-10-27T00:00:00Z'},
      {'_entity': 'trip', 'status': 'unknown', 'dueAt': '2026-10-27T00:00:00Z'},
    ];
    final review = OperationalInsights.reviewTrips(operations, now: now);
    expect(review.assessable, 2);
    expect(review.overdue, 1);
  });

  test('missing deadlines do not create false overdue alarms', () {
    final result = OperationalInsights.reviewTrips(
      <Map<String, dynamic>>[
        {'_entity': 'trip', 'status': 'scheduled'},
      ],
      now: DateTime.utc(2026, 10, 28),
    );
    expect(result.assessable, 0);
    expect(result.overdue, 0);
  });

  test('council-scope filtering excludes records of other councils', () {
    expect(OperationalInsights.visibleToUser(
      {'_entity': 'trip', 'councilName': 'Council A'},
      role: 'jsc_coordinator', userId: 'c1', scope: 'Council A',
    ), isTrue);
    expect(OperationalInsights.visibleToUser(
      {'_entity': 'trip', 'councilName': 'Council B'},
      role: 'jsc_coordinator', userId: 'c1', scope: 'Council A',
    ), isFalse);
    expect(OperationalInsights.visibleToUser(
      {'_entity': 'trip', 'groupId': 'g1'},
      role: 'jsc_coordinator', userId: 'c1', scope: 'assigned_only',
    ), isFalse);
  });

  test('SOS notifications must be addressed to the current user', () {
    final notification = <String, dynamic>{
      '_entity': 'notification', 'targetRole': 'jsc_coordinator',
      'targetUserId': 'c1', 'sourceId': 'incident-5', 'sourceEntity': 'emergency',
    };
    expect(OperationalInsights.visibleToUser(
      notification, role: 'jsc_coordinator', userId: 'c1', scope: 'Council A',
    ), isTrue);
    expect(OperationalInsights.visibleToUser(
      notification, role: 'jsc_coordinator', userId: 'c2', scope: 'Council A',
    ), isFalse);
    expect(OperationalInsights.alertIncidentKey(notification, 'notification-a'),
        'emergency:incident-5');
    expect(OperationalInsights.alertIncidentKey(
      {'_entity': 'emergency'}, 'incident-5'), 'emergency:incident-5');
  });

  test('closed critical emergencies are not presented as open alerts', () {
    expect(OperationalInsights.isOpenAlert(
      {'_entity': 'emergency', 'status': 'closed', 'statusLevel': 'critical'},
    ), isFalse);
    expect(OperationalInsights.isOpenAlert(
      {'_entity': 'emergency', 'status': 'urgent', 'statusLevel': 'critical'},
    ), isTrue);
    expect(OperationalInsights.alertPriority(
      {'_entity': 'emergency', 'statusLevel': 'critical'}), 0);
  });

}
