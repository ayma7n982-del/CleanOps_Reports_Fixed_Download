import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/worker_roster.dart';

void main() {
  final profile = <String, dynamic>{
    'name': 'عامل',
    'role': 'worker',
    'phone': '059',
    'jobTitle': 'عامل مع كارة',
    'groupId': 'group-a',
    'cycleId': 'cycle-1',
    'employeeId': '123456789',
    'municipalityCoordinatorId': 'coordinator',
    'isActive': true,
    'username': 'private-login',
    'email': 'private@example.test',
    'notes': 'private',
  };

  test('account and attendance use one UID without exposing login fields', () {
    final row = WorkerRoster.fromUser('uid-1', profile);
    expect(row['id'], 'uid-1');
    expect(row['userId'], 'uid-1');
    expect(row['job'], 'عامل مع كارة');
    expect(row.keys, isNot(contains('username')));
    expect(row.keys, isNot(contains('email')));
    expect(row.keys, isNot(contains('notes')));
    expect(WorkerRoster.forGroup([row], 'group-a').single['id'], 'uid-1');
  });

  test('transfer removes old assignment and retains worker identity', () {
    final old = WorkerRoster.fromUser('uid-1', profile);
    final moved = WorkerRoster.fromUser('uid-1', {
      ...profile,
      'groupId': 'group-b',
    });
    expect(WorkerRoster.matchesUser(old, 'uid-1', profile), isTrue);
    expect(
      WorkerRoster.matchesUser(old, 'uid-1', {
        ...profile,
        'groupId': 'group-b',
      }),
      isFalse,
    );
    expect(WorkerRoster.forGroup([moved], 'group-a'), isEmpty);
    expect(WorkerRoster.forGroup([moved], 'group-b').single['id'], 'uid-1');
  });

  test(
    'inactive and deleted accounts cannot reappear through an imported alias',
    () {
      for (final status in [
        'frozen',
        'deleted',
        'deactivated',
        'pending_deletion',
      ]) {
        final worker = WorkerRoster.fromUser('uid-1', {
          ...profile,
          'status': status,
          'isActive': false,
        });
        final imported = {
          '_entity': 'worker',
          'id': '123456789',
          'name': 'اسم قديم',
          'groupId': 'group-a',
        };
        expect(WorkerRoster.forGroup([worker, imported], 'group-a'), isEmpty);
      }
    },
  );

  test('imports and accounts with explicit identity appear exactly once', () {
    final worker = WorkerRoster.fromUser('uid-1', profile);
    final imported = {
      '_entity': 'worker',
      'id': '123456789',
      'name': 'عامل',
      'groupId': 'group-a',
    };
    final unrelated = {
      '_entity': 'worker',
      'id': 'import-2',
      'name': 'عامل',
      'groupId': 'group-a',
    };
    final result = WorkerRoster.forGroup([
      imported,
      worker,
      unrelated,
    ], 'group-a');
    expect(result.map((r) => r['id']), unorderedEquals(['uid-1', 'import-2']));
  });

  test(
    'group ID takes precedence over legacy number; empty values fall back',
    () {
      expect(
        WorkerRoster.groupId({'groupId': 'group-a', 'groupNumber': '1'}),
        'group-a',
      );
      expect(WorkerRoster.groupId({'groupId': '', 'groupNumber': '1'}), '1');
      expect(
        WorkerRoster.forGroup([
          {
            '_entity': 'worker',
            'id': 'w',
            'name': 'عامل',
            'groupId': 'group-b',
            'groupNumber': 'group-a',
          },
        ], 'group-a'),
        isEmpty,
      );
      expect(WorkerRoster.forGroup([], 'group-a'), isEmpty);
    },
  );
}
