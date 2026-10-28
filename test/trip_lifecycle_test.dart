import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/operational_insights.dart';
import 'package:solid_waste_operations/core/services/trip_lifecycle.dart';

void main() {
  test('trip deadline is derived from the real start time and selected target', () {
    final start = DateTime.utc(2026, 10, 28, 8);
    final fields = TripLifecycle.startFields(startedAt: start, targetMinutes: 90);

    expect(fields['status'], 'in_progress');
    expect(fields['startedAt'], '2026-10-28T08:00:00.000Z');
    expect(fields['deadlineAt'], '2026-10-28T09:30:00.000Z');
    expect(fields['targetDurationMinutes'], 90);

    final beforeDeadline = OperationalInsights.reviewTrips(
      [{'_entity': 'trip', ...fields}],
      now: DateTime.utc(2026, 10, 28, 9, 29),
    );
    expect(beforeDeadline.assessable, 1);
    expect(beforeDeadline.overdue, 0);

    final afterDeadline = OperationalInsights.reviewTrips(
      [{'_entity': 'trip', ...fields}],
      now: DateTime.utc(2026, 10, 28, 9, 31),
    );
    expect(afterDeadline.overdue, 1);
  });

  test('completed trip is no longer reported overdue', () {
    final started = TripLifecycle.startFields(
      startedAt: DateTime.utc(2026, 10, 28, 8),
      targetMinutes: 60,
    );
    final completed = TripLifecycle.completionFields(
      completedAt: DateTime.utc(2026, 10, 28, 8, 45),
      completedBy: 'supervisor-a',
    );
    final review = OperationalInsights.reviewTrips(
      [{'_entity': 'trip', ...started, ...completed}],
      now: DateTime.utc(2026, 10, 28, 10),
    );
    expect(review.assessable, 0);
    expect(review.overdue, 0);
  });

  test('only supervisor of the assigned group may complete an active trip', () {
    final trip = {
      '_entity': 'trip',
      'groupId': 'group-a',
      'status': 'in_progress',
    };
    expect(TripLifecycle.canSupervisorComplete(
      trip: trip,
      supervisorId: 'head-a',
      groupId: 'group-a',
    ), isTrue);
    expect(TripLifecycle.canSupervisorComplete(
      trip: trip,
      supervisorId: 'head-b',
      groupId: 'group-b',
    ), isFalse);
    expect(TripLifecycle.canSupervisorComplete(
      trip: {...trip, 'status': 'completed'},
      supervisorId: 'head-a',
      groupId: 'group-a',
    ), isFalse);
  });
}
