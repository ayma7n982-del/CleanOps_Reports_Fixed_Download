/// Shared worker identity and attendance projection. Account-backed workers use
/// their Auth UID everywhere; imported workers keep their existing identifier.
class WorkerRoster {
  static bool isWorkforce(Map<String, dynamic> user) =>
      const ['worker', 'group_supervisor'].contains(user['role']);

  static String groupId(Map<String, dynamic> worker) {
    for (final key in ['groupId', 'groupNumber', 'group']) {
      final value = '${worker[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static Map<String, dynamic> fromUser(
    String uid,
    Map<String, dynamic> user,
  ) => {
    'id': uid,
    'userId': uid,
    '_entity': 'worker',
    'rosterSource': 'users',
    'name': '${user['name'] ?? ''}',
    'phone': '${user['phone'] ?? ''}',
    'job': '${user['jobTitle'] ?? ''}',
    'role': '${user['role'] ?? 'worker'}',
    'employeeId': '${user['employeeId'] ?? ''}',
    'groupId': groupId(user),
    'group': groupId(user),
    'groupNumber': groupId(user),
    'groupName': '${user['groupName'] ?? groupId(user)}',
    'cycleId': '${user['cycleId'] ?? ''}',
    'municipalityCoordinatorId': '${user['municipalityCoordinatorId'] ?? ''}',
    'municipalityName': '${user['municipalityName'] ?? ''}',
    'isActive': user['isActive'] != false,
    'status': '${user['status'] ?? 'active'}',
    'isDeleted': user['status'] == 'deleted',
  };

  static bool matchesUser(
    Map<String, dynamic>? worker,
    String uid,
    Map<String, dynamic> user,
  ) {
    final expected = fromUser(uid, user);
    return worker != null &&
        expected.entries.every((e) => worker[e.key] == e.value);
  }

  static List<Map<String, String>> forGroup(
    Iterable<Map<String, dynamic>> records,
    String group,
  ) {
    final all = records.where((r) => r['_entity'] == 'worker').toList();
    // Include inactive projections in identity matching so an old imported row
    // cannot resurrect a frozen/deleted account or its previous assignment.
    final accountIds = <String>{};
    final employeeIds = <String>{};
    for (final record in all.where((r) => r['rosterSource'] == 'users')) {
      accountIds.add('${record['id']}');
      final employeeId = '${record['employeeId'] ?? ''}'.trim();
      if (employeeId.isNotEmpty) employeeIds.add(employeeId);
    }
    final result = <String, Map<String, String>>{};
    for (final record in all) {
      final accountId = '${record['userId'] ?? ''}'.trim();
      final id = accountId.isNotEmpty ? accountId : '${record['id'] ?? ''}'.trim();
      if (id.isEmpty ||
          group.isEmpty ||
          groupId(record) != group ||
          record['isDeleted'] == true ||
          record['isActive'] == false ||
          const [
            'frozen',
            'deleted',
            'deactivated',
            'pending_deletion',
          ].contains('${record['status'] ?? ''}'.toLowerCase()))
        continue;
      if (record['rosterSource'] != 'users' &&
          (accountIds.contains(id) ||
              employeeIds.contains(id) ||
              employeeIds.contains('${record['employeeId'] ?? ''}')))
        continue;
      final name = '${record['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      result[id] = {
        'id': id,
        'name': name,
        'phone': '${record['phone'] ?? ''}',
        'job': '${record['job'] ?? ''}',
        'role': '${record['role'] ?? 'worker'}',
        'group': groupId(record),
        'groupId': groupId(record),
        'groupName': '${record['groupName'] ?? groupId(record)}',
        'municipalityName':
            '${record['municipalityName'] ?? record['municipality'] ?? ''}',
      };
    }
    return result.values.toList()
      ..sort((a, b) => a['name']!.compareTo(b['name']!));
  }
}
