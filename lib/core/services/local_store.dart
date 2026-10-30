import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/core_models.dart';

class LocalStore {
  final Box box;
  AppUser? _cacheUser;
  LocalStore(this.box) {
    _cacheUser = cachedUser();
  }

  // Legacy caches have no reliable owner. Leave them on disk, but never expose
  // them to a new session. Pending uploads remain in their separate durable queue.
  String get cacheScope => jsonEncode([
        _cacheUser?.id,
        _cacheUser?.role,
        _cacheUser?.scope,
        _cacheUser?.groupId,
        _cacheUser?.municipalityCoordinatorId,
      ]);
  void setCacheUser(AppUser? user) => _cacheUser = user;
  String _scoped(String key) => 'session_cache_v1:$cacheScope:$key';

  List<Map<String, dynamic>> _list(String key) {
    final raw = box.get(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final value = jsonDecode(raw);
      if (value is! List) return [];
      return value.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(String key, List<Map<String, dynamic>> value) =>
      box.put(key, jsonEncode(value));

  NotificationItem? cachedNotification(String id) {
    for (final item in notifications()) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<NotificationItem> notifications() =>
      _list(_scoped('notifications')).map(NotificationItem.fromJson).toList();
  Future<void> saveNotifications(List<NotificationItem> v) =>
      _save(_scoped('notifications'), v.map((e) => e.toJson()).toList());

  List<ActivityItem> activities() =>
      _list(_scoped('activities')).map(ActivityItem.fromJson).toList();
  Future<void> saveActivities(List<ActivityItem> v) =>
      _save(_scoped('activities'), v.map((e) => e.toJson()).toList());

  List<SyncItem> queue() => _list('sync_queue').map(SyncItem.fromJson).toList();
  Future<void> saveQueue(List<SyncItem> v) =>
      _save('sync_queue', v.map((e) => e.toJson()).toList());

  List<Map<String, dynamic>> cachedOperations() =>
      _list(_scoped('operations_cache'));
  Future<void> saveCachedOperations(List<Map<String, dynamic>> value) =>
      _save(_scoped('operations_cache'), value);

  List<Map<String, dynamic>> cachedEquipmentCarts(String userId) =>
      _list('equipment_carts_cache_$userId');
  Future<void> saveCachedEquipmentCarts(
          String userId, List<Map<String, dynamic>> carts) =>
      _save('equipment_carts_cache_$userId', carts);

  List<Map<String, dynamic>> cachedContainers() =>
      _list(_scoped('containers_cache'));
  Future<void> saveCachedContainers(List<Map<String, dynamic>> value) =>
      _save(_scoped('containers_cache'), value);

  String lastSync() =>
      box.get(_scoped('last_sync'))?.toString() ?? 'لم تتم المزامنة بعد';
  Future<void> saveLastSync(String value) =>
      box.put(_scoped('last_sync'), value);

  String lastDataRefresh() =>
      box.get(_scoped('last_data_refresh'))?.toString() ?? '';
  Future<void> saveLastDataRefresh(String value) =>
      box.put(_scoped('last_data_refresh'), value);

  Future<void> saveCachedUser(AppUser user) {
    setCacheUser(user);
    return box.put('cached_user', jsonEncode(user.toJson()));
  }

  AppUser? cachedUser() {
    final raw = box.get('cached_user');
    if (raw == null || raw.isEmpty) return null;
    try {
      return AppUser.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCachedUser() {
    setCacheUser(null);
    return box.delete('cached_user');
  }

  List<Map<String, dynamic>> cachedMessages(String userId) =>
      _list('messages_cache_$userId');
  Future<void> saveCachedMessages(
          String userId, List<Map<String, dynamic>> value) =>
      _save('messages_cache_$userId', value);

  List<String> messageReadIds(String userId) {
    final raw = box.get('message_read_$userId');
    if (raw == null || raw.toString().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw.toString());
      return decoded is List ? decoded.map((e) => '$e').toList() : [];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveMessageReadIds(String userId, List<String> ids) =>
      box.put('message_read_$userId', jsonEncode(ids.toSet().toList()));
}
