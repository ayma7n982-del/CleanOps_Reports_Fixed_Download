import 'package:cloud_firestore/cloud_firestore.dart';

import 'worker_roster.dart';

/// Maintains the operational projection in the SAME commit as its user profile.
/// No Cloud Function, trigger, timer, or second successful write is required.
class WorkforceRepository {
  final FirebaseFirestore firestore;
  WorkforceRepository(this.firestore);

  void project(Transaction tx, String uid, Map<String, dynamic> profile) {
    if (!WorkerRoster.isWorkforce(profile)) return;
    tx.set(firestore.collection('operations').doc(uid), {
      ...WorkerRoster.fromUser(uid, profile),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Idempotent repair of older accounts. Read again inside each transaction so
  /// a concurrent transfer/deactivation always wins over a stale query snapshot.
  Future<void> repairManagedWorkers(String actorId) async {
    final users = await firestore
        .collection('users')
        .where('municipalityCoordinatorId', isEqualTo: actorId)
        .get();
    final workers = await firestore
        .collection('operations')
        .where('_entity', isEqualTo: 'worker')
        .where('municipalityCoordinatorId', isEqualTo: actorId)
        .get();
    final existing = {
      for (final worker in workers.docs) worker.id: worker.data(),
    };
    final employeeOwners = <String, List<String>>{};
    for (final user in users.docs.where(
      (u) => WorkerRoster.isWorkforce(u.data()),
    )) {
      final employeeId = '${user.data()['employeeId'] ?? ''}'.trim();
      if (employeeId.isNotEmpty) {
        employeeOwners.putIfAbsent(employeeId, () => []).add(user.id);
      }
    }
    for (final user in users.docs) {
      if (!WorkerRoster.isWorkforce(user.data()) ||
          WorkerRoster.matchesUser(existing[user.id], user.id, user.data()))
        continue;
      await firestore.runTransaction((tx) async {
        final latest = await tx.get(user.reference);
        final workerRef = firestore.collection('operations').doc(user.id);
        final worker = await tx.get(workerRef);
        final profile = latest.data();
        if (profile == null ||
            profile['municipalityCoordinatorId'] != actorId ||
            !WorkerRoster.isWorkforce(profile) ||
            WorkerRoster.matchesUser(worker.data(), user.id, profile))
          return;
        project(tx, user.id, profile);
      });
    }
    // Earlier CSV/Excel imports used the visible group number rather than its
    // document ID. Resolve only unambiguous aliases inside this municipality.
    final groups = await firestore
        .collection('operations')
        .where('_entity', isEqualTo: 'group')
        .where('municipalityCoordinatorId', isEqualTo: actorId)
        .get();
    final aliases =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final group in groups.docs.where(
      (g) => g.data()['isDeleted'] != true,
    )) {
      for (final alias in {
        group.id,
        '${group.data()['number'] ?? ''}',
        '${group.data()['groupNumber'] ?? ''}',
      }.where((v) => v.isNotEmpty)) {
        aliases.putIfAbsent(alias, () => []).add(group);
      }
    }
    for (final old in workers.docs) {
      if (old.data()['rosterSource'] == 'users' ||
          old.data()['isDeleted'] == true ||
          users.docs.any((user) => user.id == old.id))
        continue;
      final owners =
          employeeOwners[old.id] ??
          employeeOwners['${old.data()['employeeId'] ?? ''}'] ??
          [];
      final matches = aliases[WorkerRoster.groupId(old.data())] ?? [];
      if (owners.length != 1 && matches.length != 1) continue;
      await firestore.runTransaction((tx) async {
        final latest = await tx.get(old.reference);
        final data = latest.data();
        if (data == null ||
            data['rosterSource'] == 'users' ||
            data['isDeleted'] == true ||
            data['municipalityCoordinatorId'] != actorId)
          return;
        if (owners.length == 1) {
          final owner = await tx.get(
            firestore.collection('users').doc(owners.single),
          );
          final profile = owner.data();
          if (profile == null ||
              profile['municipalityCoordinatorId'] != actorId ||
              !WorkerRoster.isWorkforce(profile) ||
              ![
                old.id,
                '${data['employeeId'] ?? ''}',
              ].contains('${profile['employeeId'] ?? ''}'))
            return;
          // Preserve historical attendance IDs; retire only the duplicate roster
          // row. Name matching is deliberately never used as identity evidence.
          tx.update(old.reference, {
            'isDeleted': true,
            'canonicalWorkerId': owners.single,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final currentMatches = aliases[WorkerRoster.groupId(data)] ?? [];
          if (currentMatches.length != 1 ||
              data['groupId'] == currentMatches.single.id)
            return;
          tx.update(old.reference, {
            'groupId': currentMatches.single.id,
            'groupName':
                '${currentMatches.single.data()['name'] ?? currentMatches.single.id}',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    }
  }
}
