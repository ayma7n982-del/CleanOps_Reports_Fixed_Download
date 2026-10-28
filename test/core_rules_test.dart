import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/constants/app_constants.dart';
import 'package:solid_waste_operations/core/models/core_models.dart';

void main() {
  test('all five system roles are defined', () {
    expect(roles.length, 5);
    expect(roles.toSet().length, 5);
    expect(roles.contains('worker'), isTrue);
    expect(roles.contains('group_supervisor'), isTrue);
    expect(roles.contains('municipality_coordinator'), isTrue);
    expect(roles.contains('jsc_coordinator'), isTrue);
    expect(roles.contains('donor_manager'), isTrue);
  });

  test('image target options are supported', () {
    expect([300, 400, 500, 600, 1024].contains(300), isTrue);
    expect([300, 400, 500, 600, 1024].contains(1024), isTrue);
  });

  test('municipality coordinator owns group management', () {
    expect(defaultPolicy('municipality_coordinator', 'workers').create, isTrue);
    expect(defaultPolicy('group_supervisor', 'workers').visible, isFalse);
  });


  test('worker permissions stay inside Firebase write boundaries', () {
    expect(defaultPolicy('worker', 'messages').create, isFalse);
    expect(defaultPolicy('worker', 'attendance').create, isFalse);
    expect(defaultPolicy('worker', 'trips').create, isFalse);
    expect(defaultPolicy('worker', 'emergency').create, isFalse);
    expect(defaultPolicy('worker', 'containers').edit, isTrue);
    expect(defaultPolicy('worker', 'dumpsite').visible, isFalse);
  });

  test('group supervisor keeps own operational write permissions', () {
    expect(defaultPolicy('group_supervisor', 'messages').create, isTrue);
    expect(defaultPolicy('group_supervisor', 'attendance').create, isTrue);
    expect(defaultPolicy('group_supervisor', 'trips').create, isTrue);
    expect(defaultPolicy('group_supervisor', 'emergency').create, isTrue);
    expect(defaultPolicy('group_supervisor', 'containers').create, isTrue);
    expect(defaultPolicy('group_supervisor', 'workers').visible, isFalse);
  });

  test('management UI does not grant backend-impossible actions', () {
    expect(defaultPolicy('jsc_coordinator', 'audit').visible, isFalse);
    expect(defaultPolicy('jsc_coordinator', 'users').create, isFalse);
    expect(defaultPolicy('municipality_coordinator', 'containers').create, isFalse);
    expect(defaultPolicy('municipality_coordinator', 'containers').edit, isTrue);
    expect(defaultPolicy('donor_manager', 'dumpsite').create, isFalse);
    expect(defaultPolicy('donor_manager', 'containers').edit, isFalse);
  });


  test('report actions follow the backend role ceiling', () {
    expect(defaultPolicy('worker', 'reports').create, isFalse);
    expect(defaultPolicy('group_supervisor', 'reports').create, isTrue);
    expect(defaultPolicy('municipality_coordinator', 'reports').create, isTrue);
    expect(defaultPolicy('jsc_coordinator', 'reports').create, isTrue);
    expect(defaultPolicy('donor_manager', 'reports').create, isTrue);
    expect(defaultPolicy('jsc_coordinator', 'users').create, isFalse);
  });

test('dynamic policies cannot exceed the role security ceiling', () {
    final worker = AppUser(
      id: 'worker-a',
      username: 'worker-a',
      name: 'Worker A',
      role: 'worker',
      scope: 'assigned_only',
      groupId: 'group-a',
      policies: const {
        'trips': FeaturePolicy(create: true, edit: true),
        'dumpsite': FeaturePolicy(create: true, edit: true),
      },
    );
    expect(worker.can('trips', 'create'), isFalse);
    expect(worker.can('dumpsite', 'view'), isFalse);
  });
}
