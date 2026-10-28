import '../constants/app_constants.dart';

class FeaturePolicy {
  final bool visible;
  final bool enabled;
  final bool view;
  final bool create;
  final bool edit;
  final bool approve;
  final bool softDelete;
  final bool export;
  final bool importData;
  final bool notifications;
  final bool offlineAllowed;

  const FeaturePolicy({
    this.visible = true,
    this.enabled = true,
    this.view = true,
    this.create = false,
    this.edit = false,
    this.approve = false,
    this.softDelete = false,
    this.export = false,
    this.importData = false,
    this.notifications = true,
    this.offlineAllowed = true,
  });

  FeaturePolicy copyWith({
    bool? visible,
    bool? enabled,
    bool? view,
    bool? create,
    bool? edit,
    bool? approve,
    bool? softDelete,
    bool? export,
    bool? importData,
    bool? notifications,
    bool? offlineAllowed,
  }) => FeaturePolicy(
    visible: visible ?? this.visible,
    enabled: enabled ?? this.enabled,
    view: view ?? this.view,
    create: create ?? this.create,
    edit: edit ?? this.edit,
    approve: approve ?? this.approve,
    softDelete: softDelete ?? this.softDelete,
    export: export ?? this.export,
    importData: importData ?? this.importData,
    notifications: notifications ?? this.notifications,
    offlineAllowed: offlineAllowed ?? this.offlineAllowed,
  );

  Map<String, dynamic> toJson() => {
    'visible': visible,
    'enabled': enabled,
    'view': view,
    'create': create,
    'edit': edit,
    'approve': approve,
    'softDelete': softDelete,
    'export': export,
    'import': importData,
    'notifications': notifications,
    'offlineAllowed': offlineAllowed,
  };

  factory FeaturePolicy.fromJson(Map<String, dynamic> j) => FeaturePolicy(
    visible: j['visible'] != false,
    enabled: j['enabled'] != false,
    view: j['view'] != false,
    create: j['create'] == true,
    edit: j['edit'] == true,
    approve: j['approve'] == true,
    softDelete: j['softDelete'] == true,
    export: j['export'] == true,
    importData: j['import'] == true,
    notifications: j['notifications'] != false,
    offlineAllowed: j['offlineAllowed'] != false,
  );
}

FeaturePolicy defaultPolicy(String role, String feature) {
  const hidden = FeaturePolicy(view: false, visible: false);

  if (feature == 'messages') {
    return FeaturePolicy(
      create: role != 'worker',
      edit: false,
      notifications: true,
      offlineAllowed: true,
    );
  }

  if (role == 'worker') {
    if (const {
      'permissions', 'audit', 'settings', 'excel', 'workers', 'users',
      'dumpsite', 'critical_areas', 'cycle',
    }.contains(feature)) {
      return hidden;
    }
    if (feature == 'containers') {
      return const FeaturePolicy(
        edit: true,
        notifications: true,
        offlineAllowed: true,
      );
    }
    // Workers may view their scoped operational data, but writes are limited
    // by Firestore to container status updates and self GPS tracking.
    return const FeaturePolicy();
  }

  if (role == 'group_supervisor') {
    if (const {
      'permissions', 'audit', 'settings', 'excel', 'workers', 'users',
      'dumpsite', 'critical_areas', 'cycle',
    }.contains(feature)) {
      return hidden;
    }
    if (feature == 'containers') {
      return const FeaturePolicy(
        create: true,
        edit: true,
        notifications: true,
        offlineAllowed: true,
      );
    }
    if (const {
      'attendance', 'leave', 'trips', 'streets', 'emergency',
      'notifications', 'activity', 'reports',
    }.contains(feature)) {
      return const FeaturePolicy(
        create: true,
        edit: true,
        notifications: true,
        offlineAllowed: true,
      );
    }
    return const FeaturePolicy();
  }

  if (role == 'municipality_coordinator') {
    if (feature == 'permissions' || feature == 'audit') return hidden;
    if (feature == 'cycle' || feature == 'trips') {
      return const FeaturePolicy(export: true, notifications: true);
    }
    if (feature == 'containers') {
      return const FeaturePolicy(edit: true, export: true, notifications: true);
    }
    if (feature == 'settings') return const FeaturePolicy();
    return const FeaturePolicy(
      create: true,
      edit: true,
      export: true,
      notifications: true,
    );
  }

  if (role == 'jsc_coordinator') {
    if (feature == 'permissions' || feature == 'settings' || feature == 'audit') {
      return hidden;
    }
    if (feature == 'users' || feature == 'workers' ||
        feature == 'cycle' || feature == 'trips') {
      return const FeaturePolicy(export: true, notifications: true);
    }
    return const FeaturePolicy(
      create: true,
      edit: true,
      approve: true,
      export: true,
      notifications: true,
    );
  }

  if (role == 'donor_manager') {
    if (feature == 'workers') {
      return const FeaturePolicy(
        create: false,
        edit: false,
        softDelete: false,
        export: true,
        importData: true,
      );
    }
    if (feature == 'dumpsite' || feature == 'containers' ||
        feature == 'trips' || feature == 'emergency') {
      return const FeaturePolicy(
        approve: true,
        export: true,
        notifications: true,
      );
    }
    return const FeaturePolicy(
      create: true,
      edit: true,
      approve: true,
      softDelete: true,
      export: true,
      importData: true,
    );
  }

  return hidden;
}

class AppUser {
  static final Map<String, Map<String, FeaturePolicy>> roleOverrides = {};
  final String id;
  final String username;
  final String name;
  final String role;
  final String scope;
  final String? groupId;
  final String? municipalityCoordinatorId;
  final Map<String, FeaturePolicy> policies;
  final bool isActive;

  const AppUser({
    required this.id,
    required this.username,
    required this.name,
    required this.role,
    required this.scope,
    this.groupId,
    this.municipalityCoordinatorId,
    required this.policies,
    this.isActive = true,
  });

  bool can(String feature, String action) {
    final ceiling = defaultPolicy(role, feature);
    final configured =
        roleOverrides[role]?[feature] ?? policies[feature] ?? ceiling;
    if (!ceiling.visible || !ceiling.enabled ||
        !configured.visible || !configured.enabled) {
      return false;
    }
    switch (action) {
      case 'view': return ceiling.view && configured.view;
      case 'create': return ceiling.create && configured.create;
      case 'edit': return ceiling.edit && configured.edit;
      case 'approve': return ceiling.approve && configured.approve;
      case 'delete': return ceiling.softDelete && configured.softDelete;
      case 'export': return ceiling.export && configured.export;
      case 'import': return ceiling.importData && configured.importData;
      default: return false;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'name': name,
    'role': role,
    'scope': scope,
    'groupId': groupId,
    'municipalityCoordinatorId': municipalityCoordinatorId,
    'isActive': isActive,
    'policies': policies.map((k, v) => MapEntry(k, v.toJson()))
  };

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
    id: '${j['id']}',
    username: '${j['username']}',
    name: '${j['name']}',
    role: '${j['role']}',
    scope: '${j['scope'] ?? 'assigned_only'}',
    groupId: j['groupId']?.toString(),
    municipalityCoordinatorId: j['municipalityCoordinatorId']?.toString(),
    isActive: j['isActive'] != false,
    policies: (j['policies'] as Map? ?? {}).map(
      (k, v) => MapEntry('$k', FeaturePolicy.fromJson(Map.from(v))),
    ),
  );
}

class NotificationItem {
  final String id, title, body, level, createdAt;
  final bool read;
  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.level,
    required this.createdAt,
    this.read = false,
  });

  NotificationItem copyWith({bool? read}) => NotificationItem(
    id: id,
    title: title,
    body: body,
    level: level,
    createdAt: createdAt,
    read: read ?? this.read,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'level': level,
    'createdAt': createdAt,
    'read': read,
  };

  factory NotificationItem.fromJson(Map<String, dynamic> j) => NotificationItem(
    id: '${j['id']}',
    title: '${j['title']}',
    body: '${j['body']}',
    level: '${j['level']}',
    createdAt: '${j['createdAt']}',
    read: j['read'] == true,
  );
}

class ActivityItem {
  final String id, title, detail, createdAt, level;
  const ActivityItem({
    required this.id,
    required this.title,
    required this.detail,
    required this.createdAt,
    required this.level,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'detail': detail,
    'createdAt': createdAt,
    'level': level,
  };

  factory ActivityItem.fromJson(Map<String, dynamic> j) => ActivityItem(
    id: '${j['id']}',
    title: '${j['title']}',
    detail: '${j['detail']}',
    createdAt: '${j['createdAt']}',
    level: '${j['level']}',
  );
}

class SyncItem {
  final String id, entity, operation, payload, createdAt;
  final int retryCount;
  /// The Firebase account that originally queued this operation.
  /// Null supports records written before this field was introduced.
  final String? ownerUid;
  const SyncItem({
    required this.id,
    required this.entity,
    required this.operation,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.ownerUid,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'entity': entity,
    'operation': operation,
    'payload': payload,
    'createdAt': createdAt,
    'retryCount': retryCount,
    if (ownerUid != null) 'ownerUid': ownerUid,
  };

  factory SyncItem.fromJson(Map<String, dynamic> j) => SyncItem(
    id: '${j['id']}',
    entity: '${j['entity']}',
    operation: '${j['operation']}',
    payload: '${j['payload']}',
    createdAt: '${j['createdAt']}',
    retryCount: (j['retryCount'] ?? 0) as int,
    ownerUid: j['ownerUid']?.toString(),
  );
}
