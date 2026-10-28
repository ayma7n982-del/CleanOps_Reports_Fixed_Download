import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/core_models.dart';
import 'config_service.dart';
import 'local_store.dart';
import 'operations_cache_merge.dart';

class DataService extends ChangeNotifier {
  final LocalStore store;
  final ConfigService config;
  final Uuid uuid = const Uuid();
  List<NotificationItem> notifications = [];
  List<ActivityItem> activities = [];
  List<SyncItem> queue = [];
  List<Map<String, dynamic>> operations = [];
  bool online = false, syncing = false;
  String lastSync = 'لم تتم المزامنة بعد';
  String lastDataRefresh = '';
  String? lastSyncError;
  StreamSubscription<List<ConnectivityResult>>? connectivitySub;
  Timer? automaticSyncTimer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sosNotificationSub;
  StreamSubscription<User?>? authNotificationSub;
  final Future<void> Function(SyncItem item, Map<String, dynamic> payload)?
      _syncItemOverride;

  DataService(
    this.store,
    this.config, {
    Future<void> Function(SyncItem item, Map<String, dynamic> payload)?
        syncItemOverride,
  }) : _syncItemOverride = syncItemOverride;

  Future<void> init() async {
    notifications = store.notifications();
    activities = store.activities();
    queue = store.queue();
    operations = store.cachedOperations();
    lastSync = store.lastSync();
    lastDataRefresh = store.lastDataRefresh();
    final c = await Connectivity().checkConnectivity();
    online = !c.contains(ConnectivityResult.none);
    connectivitySub = Connectivity().onConnectivityChanged.listen((v) {
      online = !v.contains(ConnectivityResult.none);
      notifyListeners();
      if (online) {
        unawaited(sync());
        unawaited(refreshOperations());
        unawaited(refreshSosInbox());
      }
    });
    automaticSyncTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      final connections = await Connectivity().checkConnectivity();
      final nextOnline = !connections.contains(ConnectivityResult.none);
      if (online != nextOnline) {
        online = nextOnline;
        notifyListeners();
      }
      if (!online) return;
      if (!syncing && queue.isNotEmpty) unawaited(sync());
      final lastRefresh = DateTime.tryParse(lastDataRefresh);
      final stale = lastRefresh == null ||
          DateTime.now().difference(lastRefresh) >= const Duration(minutes: 3);
      if (stale) unawaited(refreshOperations());
    });
    notifyListeners();
    if (Firebase.apps.isNotEmpty) {
      // Subscribe after authentication, including when sign-in happens after init.
      // Reconnect after account changes so stale listeners do not outlive a session.
      authNotificationSub = FirebaseAuth.instance.authStateChanges().listen(
        (account) {
          final previous = sosNotificationSub;
          if (previous != null) unawaited(previous.cancel());
          sosNotificationSub = null;
          if (account == null) return;
          sosNotificationSub = FirebaseFirestore.instance.collection('operations')
              .where('_entity', isEqualTo: 'notification').snapshots().listen(
            (_) => unawaited(refreshSosInbox()),
            onError: (Object error) => debugPrint('SOS notification listener failed: $error'),
          );
          if (online) {
            // A queue created while signed out must retry immediately after the
            // real Firebase session becomes available instead of waiting for
            // the periodic retry timer.
            unawaited(sync());
            unawaited(refreshOperations());
          }
          unawaited(refreshSosInbox());
        },
        onError: (Object error) => debugPrint('SOS auth listener failed: $error'),
      );
    }
    if (online) {
      unawaited(sync());
      unawaited(refreshOperations());
      unawaited(refreshSosInbox());
    }
  }

  String get automaticSyncStatus {
    if (!online) {
      return queue.isEmpty
          ? 'غير متصل • البيانات المحلية متاحة'
          : 'غير متصل • ' + queue.length.toString() + ' عملية محفوظة وستُزامن تلقائيًا';
    }
    if (syncing) return 'مزامنة تلقائية جارية';
    if (queue.isNotEmpty && lastSyncError != null) {
      return '${queue.length} عملية لم يؤكدها الخادم؛ ستُعاد المحاولة تلقائيًا';
    }
    if (queue.isNotEmpty) {
      return queue.length.toString() + ' عملية بانتظار المزامنة التلقائية';
    }
    final refreshed = DateTime.tryParse(lastDataRefresh);
    if (refreshed == null) return 'متصل • التحديث التلقائي جاهز';
    final age = DateTime.now().difference(refreshed);
    if (age.inMinutes < 1) return 'متصل • البيانات محدثة الآن';
    if (age.inHours < 1) return 'متصل • آخر تحديث قبل ' + age.inMinutes.toString() + ' دقيقة';
    return 'متصل • آخر تحديث قبل ' + age.inHours.toString() + ' ساعة';
  }

  bool get usingCachedData => !online && operations.isNotEmpty;
  @override
  void dispose() {
    connectivitySub?.cancel();
    automaticSyncTimer?.cancel();
    sosNotificationSub?.cancel();
    authNotificationSub?.cancel();
    super.dispose();
  }

  Future<void> addActivity(String title, String detail, {String level = 'info'}) async {
    final a = ActivityItem(
      id: uuid.v4(),
      title: title,
      detail: detail,
      createdAt: DateTime.now().toIso8601String(),
      level: level,
    );
    activities = [a, ...activities].take(100).toList();
    await store.saveActivities(activities);
    notifyListeners();

    // Persist actual activity events to the shared audit feed. The local history
    // remains usable offline; Firestore's offline persistence sends pending writes
    // when connectivity returns. Never block the user interface on a network write.
    if (Firebase.apps.isNotEmpty) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        unawaited(
          FirebaseFirestore.instance.collection('audit').doc(a.id).set({
            'id': a.id,
            'actorId': uid,
            'operation': a.title,
            'targetId': 'activity:${a.id}',
            'detail': a.detail,
            'level': a.level,
            'createdAt': a.createdAt,
            'timestamp': FieldValue.serverTimestamp(),
            'immutable': true,
            '_entity': 'activity',
          }).catchError((Object error) {
            debugPrint('تعذر حفظ النشاط في Firebase: $error');
          }),
        );
      }
    }
  }

  Future<void> writeAudit({
    required String actorId,
    required String operation,
    required String targetId,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  }) async {
    final payload = {
      'id': uuid.v4(),
      'actorId': actorId,
      'operation': operation,
      'targetId': targetId,
      'before': before ?? {},
      'after': after ?? {},
      'createdAt': DateTime.now().toIso8601String(),
      'immutable': true,
    };
    await enqueue('audit', 'create', payload);
  }

  Future<void> notifyUser(String title, String body, {String level = 'info'}) async {
    final n = NotificationItem(
      id: uuid.v4(),
      title: title,
      body: body,
      level: level,
      createdAt: DateTime.now().toIso8601String(),
    );
    notifications = [n, ...notifications].take(100).toList();
    await store.saveNotifications(notifications);
    notifyListeners();
  }

  Future<void> refreshSosInbox() async {
    if (!online || Firebase.apps.isEmpty) return;
    final current = FirebaseAuth.instance.currentUser;
    if (current == null) return;
    try {
      final profile = await FirebaseFirestore.instance.collection('users').doc(current.uid).get();
      final role = profile.data()?['role']?.toString();
      if (profile.data()?['isActive'] == false || role == null) return;
      if (!['municipality_coordinator', 'jsc_coordinator', 'donor_manager'].contains(role)) return;
      final result = await FirebaseFirestore.instance.collection('operations')
          .where('_entity', isEqualTo: 'notification').limit(300).get();
      var changed = false;
      for (final document in result.docs) {
        final item = document.data();
        if (item['sourceEntity'] != 'emergency' || item['targetRole'] != role) continue;
        final recipient = item['targetUserId']?.toString();
        if ((role == 'municipality_coordinator' || role == 'jsc_coordinator' || role == 'donor_manager') && (recipient == null || recipient.isEmpty || recipient != current.uid)) continue;
        if (role != 'municipality_coordinator' && recipient != null && recipient.isNotEmpty && recipient != current.uid) continue;
        if (notifications.any((n) => n.id == document.id)) continue;
        notifications = [NotificationItem(
          id: document.id, title: '${item['title'] ?? 'SOS'}',
          body: '${item['body'] ?? ''}', level: 'urgent',
          createdAt: '${item['createdAt'] ?? ''}',
        ), ...notifications].take(100).toList();
        changed = true;
      }
      if (changed) {
        await store.saveNotifications(notifications);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('SOS inbox refresh failed: $e');
    }
  }

  Future<void> markRead(String id) async {
    notifications = notifications.map((n) => n.id == id ? n.copyWith(read: true) : n).toList();
    await store.saveNotifications(notifications);
    notifyListeners();
  }

  /// Converts Firestore and Dart values to JSON-safe primitives before placing
  /// operations in the offline queue. Firestore Timestamp/GeoPoint values can be
  /// present in imported or edited records and jsonEncode cannot encode them by default.
  dynamic _toJsonSafe(dynamic value) {
    if (value == null || value is String || value is bool || value is num) return value;
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is GeoPoint) return <String, dynamic>{'latitude': value.latitude, 'longitude': value.longitude};
    if (value is DocumentReference) return value.path;
    if (value is Map) {
      return value.map((key, item) => MapEntry('$key', _toJsonSafe(item)));
    }
    if (value is Iterable) return value.map(_toJsonSafe).toList();
    // Preserve useful diagnostics without allowing an unsupported object to abort
    // an otherwise valid offline-first operation.
    return value.toString();
  }

  /// Block competing offline redirects of the same cart until the first move
  /// is confirmed by Firestore. Separate collections may reuse document IDs.
  bool hasPendingCartRedirect(String cartId, String cartCollection) {
    for (final item in queue) {
      if (item.entity != 'cart_redirect') continue;
      try {
        final value = jsonDecode(item.payload);
        if (value is Map &&
            '${value['cartId'] ?? ''}' == cartId &&
            '${value['cartCollection'] ?? ''}' == cartCollection) {
          return true;
        }
      } catch (_) {
        // A malformed unrelated queued record must not block this cart.
      }
    }
    return false;
  }

  /// Camera and recorder paths may live in a temporary directory that the OS
  /// clears before connectivity returns. Retain a durable copy for queued work.
  Future<void> _preserveOfflineAttachment(
      Map<String, dynamic> payload, String queueId) async {
    final path = payload['localAttachmentPath']?.toString() ?? '';
    if (path.isEmpty) return;
    final source = File(path);
    if (!await source.exists()) {
      throw StateError('لا يمكن حفظ العملية: ملف المرفق غير موجود على الهاتف.');
    }
    final directory = Directory(
        '${(await getApplicationSupportDirectory()).path}/offline_attachments');
    await directory.create(recursive: true);
    final extension = payload['attachmentType'] == 'audio' ? 'm4a' : 'jpg';
    final stored = await source.copy('${directory.path}/$queueId.$extension');
    payload['localAttachmentPath'] = stored.path;
  }

  Future<void> enqueue(String entity, String operation, Map<String, dynamic> payload) async {
    final safePayload = Map<String, dynamic>.from(_toJsonSafe(payload) as Map);
    final queueId = uuid.v4();
    await _preserveOfflineAttachment(safePayload, queueId);
    final item = SyncItem(
      id: queueId,
      ownerUid: Firebase.apps.isNotEmpty
          ? FirebaseAuth.instance.currentUser?.uid : null,
      entity: entity,
      operation: operation,
      payload: jsonEncode(safePayload),
      createdAt: DateTime.now().toIso8601String(),
    );
    queue = [...queue, item];
    await store.saveQueue(queue);
    if (entity != 'cart_redirect' && entity != 'equipment_dispatch') {
      _applyLocalOperation(entity == 'attendance_checkout' ? 'attendance' : entity, operation, safePayload);
    }
    notifyListeners();
    if (online) unawaited(sync());
  }

  Future<List<Map<String, dynamic>>> refreshOperations({int limit = 1000}) async {
    if (!online || Firebase.apps.isEmpty) return operations;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('operations')
          .limit(limit)
          .get();
      final loaded = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        loaded.add({'id': doc.id, ...doc.data()});
      }
      operations = _mergeOperations(loaded, operations);
      await store.saveCachedOperations(operations.take(limit).toList());
      lastDataRefresh = DateTime.now().toIso8601String();
      await store.saveLastDataRefresh(lastDataRefresh);
      notifyListeners();
    } catch (e) {
      debugPrint('Operations refresh failed; keeping local cache: $e');
    }
    return operations;
  }

  List<Map<String, dynamic>> _mergeOperations(
    List<Map<String, dynamic>> remote,
    List<Map<String, dynamic>> local,
  ) {
    final pendingIds = <String>{};
    for (final item in queue) {
      if (item.entity == 'audit' || item.entity == 'notification' ||
          item.entity == 'cart_redirect' ||
          item.entity == 'equipment_dispatch') continue;
      try {
        final payload = jsonDecode(item.payload);
        if (payload is! Map) continue;
        final id = '${payload['id'] ?? ''}'.trim();
        if (id.isNotEmpty) pendingIds.add(id);
      } catch (_) {
        // An invalid pending record cannot overwrite a confirmed server value.
      }
    }
    return OperationsCacheMerge.merge(
      remote, local, pendingIds: pendingIds,
    );
  }

  void _applyLocalOperation(String entity, String operation, Map<String, dynamic> payload) {
    if (entity == 'audit' || entity == 'notification') return;
    final id = '${payload['id'] ?? ''}';
    if (id.isEmpty) return;
    if (operation == 'delete' || operation == 'soft_delete') {
      operations = operations.map((e) => '${e['id']}' == id
          ? {...e, ...payload, '_entity': entity, 'isDeleted': true}
          : e).toList();
      return;
    }
    final next = {...payload, '_entity': entity};
    final index = operations.indexWhere((e) => '${e['id']}' == id);
    if (index >= 0) {
      operations = [...operations]..[index] = {...operations[index], ...next};
    } else {
      operations = _mergeOperations([next], operations);
    }
    unawaited(store.saveCachedOperations(operations.take(1000).toList()));
  }

  /// Reflect a server-confirmed cart move in local caches. Pending moves never
  /// alter the assigned group, and no synthetic cart_redirect operation is shown.
  Future<void> _applyConfirmedCartRedirect(
    Map<String, dynamic> payload, {
    required String? coordinatorId,
  }) async {
    final cartId = '${payload['cartId'] ?? ''}';
    final destinationId = '${payload['toGroupId'] ?? ''}';
    final collection = '${payload['cartCollection'] ?? ''}';
    if (cartId.isEmpty || destinationId.isEmpty) {
      throw StateError('Confirmed cart redirect has missing identifiers.');
    }
    if (collection == 'operations') {
      operations = operations.map((entry) =>
          '${entry['id']}' == cartId && entry['_entity'] != 'cart_redirect'
              ? {...entry, 'groupId': destinationId}
              : entry).toList();
    } else if (collection == 'equipment') {
      // Never write another coordinator's scoped cart cache on account changes.
      if (coordinatorId != null &&
          coordinatorId.isNotEmpty &&
          coordinatorId == '${payload['municipalityCoordinatorId'] ?? ''}') {
        final cached = store.cachedEquipmentCarts(coordinatorId);
        await store.saveCachedEquipmentCarts(coordinatorId, cached.map((entry) =>
            '${entry['id']}' == cartId
                ? {...entry, 'groupId': destinationId}
                : entry).toList());
      }
    } else {
      throw StateError('Unknown cart collection in confirmed redirect.');
    }
    operations = operations.where((entry) =>
        !(entry['_entity'] == 'cart_redirect' &&
          '${entry['id']}' == '${payload['id']}')).toList();
    await store.saveCachedOperations(operations.take(1000).toList());
    notifyListeners();
  }

  Future<void> _uploadAttachment(Map<String, dynamic> payload, String fallbackOperationId) async {
    if ('${payload['attachmentUrl'] ?? ''}'.isNotEmpty) return;
    final localPath = '${payload['localAttachmentPath'] ?? ''}';
    if (localPath.isEmpty) return;
    final file = File(localPath);
    if (!await file.exists()) {
      throw StateError('المرفق المحلي مفقود؛ العملية محفوظة بانتظار استعادة الملف.');
    }
    final kind = '${payload['attachmentType'] ?? ''}';
    final userId = '${payload['userId'] ?? payload['reportedBy'] ?? 'unknown'}';
    final operationId = '${payload['id'] ?? fallbackOperationId}';
    if (operationId.isEmpty) {
      throw StateError('لا يمكن رفع مرفق دون معرّف العملية.');
    }
    late final String url;
    if (kind == 'audio') {
      final ref = FirebaseStorage.instance.ref('audio/$userId/$operationId/emergency.m4a');
      await ref.putFile(file, SettableMetadata(contentType: 'audio/mp4'));
      url = await ref.getDownloadURL();
    } else {
      // A fixed object path makes retries idempotent instead of creating duplicates.
      final ref = FirebaseStorage.instance.ref('photos/$userId/$operationId/attachment.jpg');
      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      url = await ref.getDownloadURL();
    }
    payload['attachmentUrl'] = url;
    payload.remove('attachmentWarning');
    // Keep localAttachmentPath until the Firestore write is confirmed.
  }

  Future<void> sync() async {
    if (!online || syncing || queue.isEmpty ||
        (Firebase.apps.isEmpty && _syncItemOverride == null)) {
      return;
    }
    // Signed-out devices must not upload queued records under a future account.
    final currentUid = _syncItemOverride == null
        ? FirebaseAuth.instance.currentUser?.uid : null;
    if (_syncItemOverride == null && currentUid == null) return;
    syncing = true;
    lastSyncError = null;
    notifyListeners();
    var completed = 0;

    try {
      for (final item in List.from(queue)) {
        // Stop the previous account's sync immediately after an auth switch.
        if (_syncItemOverride == null &&
            FirebaseAuth.instance.currentUser?.uid != currentUid) break;
        // Retain records for a different account; its own session will retry.
        if (_syncItemOverride == null && item.ownerUid != null &&
            item.ownerUid != currentUid) continue;
        try {
          final payload = Map<String, dynamic>.from(jsonDecode(item.payload));

          // Deterministic test seam for the complete offline -> online queue
          // lifecycle. Production never supplies this override.
          if (_syncItemOverride != null) {
            await _syncItemOverride!(item, payload);
            completed++;
            if (item.entity == 'cart_redirect') {
              await _applyConfirmedCartRedirect(
                payload,
                coordinatorId: '${payload['municipalityCoordinatorId'] ?? ''}',
              );
            } else if (item.entity != 'equipment_dispatch') {
              _applyLocalOperation(
                item.entity == 'attendance_checkout' ? 'attendance' : item.entity,
                item.operation,
                payload,
              );
            }
            queue = queue.where((e) => e.id != item.id).toList();
            await store.saveQueue(queue);
            continue;
          }

          final attachmentPath = payload['localAttachmentPath']?.toString();
          if (attachmentPath != null && attachmentPath.isNotEmpty) {
            await _uploadAttachment(payload, item.id);
            // Persist the successful upload before attempting the Firestore write.
            // After an app restart, retrying won't re-upload the same attachment.
            queue = queue.map((queued) => queued.id == item.id
                ? SyncItem(id: queued.id, entity: queued.entity,
                    operation: queued.operation, payload: jsonEncode(payload),
                    createdAt: queued.createdAt, retryCount: queued.retryCount,
                    ownerUid: queued.ownerUid)
                : queued).toList();
            await store.saveQueue(queue);
          }
          if (_syncItemOverride == null &&
              FirebaseAuth.instance.currentUser?.uid != currentUid) {
            throw StateError('تغير الحساب أثناء المزامنة؛ ستُستأنف للحساب الصحيح.');
          }
          final cloudPayload = Map<String, dynamic>.from(payload)
            ..remove('localAttachmentPath')
            ..remove('attachmentType');

          final collection = item.entity == 'audit' ? 'audit' : (item.entity == 'container' ? 'containers' : 'operations');
          final docId = payload['id']?.toString() ?? item.id;
          final ref = FirebaseFirestore.instance.collection(collection).doc(docId);

          if (item.entity == 'audit') {
            await ref.set({
              ...cloudPayload,
              'timestamp': FieldValue.serverTimestamp(),
              'immutable': true,
              '_entity': item.entity
            });
          } else if (item.entity == 'container') {
            // Containers have their own Firestore collection and strict field-level rules.
            // Do not inject the generic _entity marker into this collection.
            await ref.set({
              ...cloudPayload,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } else if (item.entity == 'cart_redirect') {
            final actorId = FirebaseAuth.instance.currentUser?.uid ?? '';
            final cartId = '${payload['cartId'] ?? ''}'.trim();
            final cartCollection = '${payload['cartCollection'] ?? ''}'.trim();
            final fromGroupId = '${payload['fromGroupId'] ?? ''}'.trim();
            final toGroupId = '${payload['toGroupId'] ?? ''}'.trim();
            if (actorId.isEmpty || cartId.isEmpty ||
                !const ['operations', 'equipment'].contains(cartCollection) ||
                fromGroupId.isEmpty || toGroupId.isEmpty || fromGroupId == toGroupId) {
              throw StateError('بيانات إعادة توجيه الكارة غير مكتملة.');
            }
            final db = FirebaseFirestore.instance;
            final cartRef = db.collection(cartCollection).doc(cartId);
            final fromRef = db.collection('operations').doc(fromGroupId);
            final toRef = db.collection('operations').doc(toGroupId);
            final logRef = db.collection('operations').doc(docId);
            await db.runTransaction((tx) async {
              final existing = await tx.get(logRef);
              if (existing.exists) {
                final data = existing.data();
                final sameRequest = data?['_entity'] == 'cart_redirect' &&
                    data?['cartId'] == cartId &&
                    data?['fromGroupId'] == fromGroupId &&
                    data?['toGroupId'] == toGroupId &&
                    data?['requestedBy'] == actorId &&
                    data?['status'] == 'applied';
                if (!sameRequest) {
                  throw StateError('معرّف طلب إعادة التوجيه مستخدم لعملية أخرى.');
                }
                return;
              }

              final snapshots = await Future.wait([
                tx.get(cartRef),
                tx.get(fromRef),
                tx.get(toRef),
              ]);
              final cart = snapshots[0].data();
              final fromGroup = snapshots[1].data();
              final toGroup = snapshots[2].data();
              if (cart == null || fromGroup == null || toGroup == null) {
                throw StateError('تعذر العثور على الكارة أو إحدى المجموعتين.');
              }
              if (fromGroup['_entity'] != 'group' || toGroup['_entity'] != 'group' ||
                  fromGroup['municipalityCoordinatorId'] != actorId ||
                  toGroup['municipalityCoordinatorId'] != actorId ||
                  cart['municipalityCoordinatorId'] != actorId ||
                  cart['isDeleted'] == true) {
                throw StateError('الكارة أو المجموعات خارج نطاق البلدية.');
              }
              if ('${cart['groupId'] ?? ''}' != fromGroupId) {
                throw StateError('تغير تخصيص الكارة قبل المزامنة؛ حدّث البيانات وأعد المحاولة.');
              }
              final cartEntity = cartCollection == 'equipment'
                  ? 'equipment'
                  : '${cart['_entity'] ?? payload['cartEntity'] ?? ''}';
              tx.update(cartRef, {
                'groupId': toGroupId,
                'updatedBy': actorId,
                'updatedAt': FieldValue.serverTimestamp(),
                'lastRedirectRequestId': docId,
              });
              tx.set(logRef, {
                ...cloudPayload,
                'id': docId,
                '_entity': 'cart_redirect',
                'cartId': cartId,
                'cartEntity': cartEntity,
                'cartCollection': cartCollection,
                'fromGroupId': fromGroupId,
                'toGroupId': toGroupId,
                'municipalityCoordinatorId': actorId,
                'requestedBy': actorId,
                'status': 'applied',
                'updatedAt': FieldValue.serverTimestamp(),
              });
            });
          } else if (item.entity == 'emergency' &&
              const ['sos_acknowledge', 'sos_close', 'sos_refer', 'sos_reopen'].contains(item.operation)) {
            // Update only fields permitted by validSosAcknowledgment in Firestore rules.
            // Never merge an entire cached SOS document into the remote record.
            final existing = await ref.get();
            if (!existing.exists || existing.data()?['_entity'] != 'emergency') {
              throw StateError('بلاغ SOS غير موجود على الخادم.');
            }
            final current = existing.data()!;
            if (item.operation == 'sos_acknowledge') {
              if (current['acknowledged'] == true &&
                  current['acknowledgedBy'] == cloudPayload['acknowledgedBy']) {
                // Already acknowledged by this coordinator.
              } else if (current['status'] == 'urgent' &&
                  current['acknowledged'] == false) {
                await ref.update({
                  'acknowledged': true,
                  'acknowledgedBy': cloudPayload['acknowledgedBy'],
                  'acknowledgedAt': cloudPayload['acknowledgedAt'],
                  'status': 'acknowledged',
                  'updatedAt': cloudPayload['updatedAt'],
                });
              } else {
                throw StateError('تغيرت حالة بلاغ SOS قبل تأكيد الاستلام.');
              }
            } else if (item.operation == 'sos_close') {
              if (current['status'] == 'closed' &&
                  current['closedBy'] == cloudPayload['closedBy'] &&
                  current['resolutionNote'] == cloudPayload['resolutionNote']) {
                // Idempotent retry after a confirmed remote close.
              } else if (current['acknowledged'] == true &&
                  const ['acknowledged', 'resolved'].contains(current['status'])) {
                await ref.update({
                  'status': 'closed',
                  'acknowledged': true,
                  'closedBy': cloudPayload['closedBy'],
                  'closedAt': cloudPayload['closedAt'],
                  'resolutionNote': cloudPayload['resolutionNote'],
                  'updatedAt': cloudPayload['updatedAt'],
                });
              } else {
                throw StateError('لا يمكن إغلاق بلاغ SOS قبل تأكيد الاستلام.');
              }
            } else if (item.operation == 'sos_refer') {
              if (current['referralDestination'] == 'هندسة المتفجرات' &&
                  current['referredBy'] == cloudPayload['referredBy']) {
                // The first successful attempt is already recorded.
              } else if (const ['urgent', 'acknowledged', 'resolved', 'secured']
                  .contains(current['status'])) {
                await ref.update({
                  'referredBy': cloudPayload['referredBy'],
                  'referredAt': cloudPayload['referredAt'],
                  'referralDestination': 'هندسة المتفجرات',
                  'updatedAt': cloudPayload['updatedAt'],
                });
              } else {
                throw StateError('حالة بلاغ SOS لا تسمح بإحالته.');
              }
            } else if (item.operation == 'sos_reopen') {
              if (current['status'] == 'reopened' &&
                  current['reopenedBy'] == cloudPayload['reopenedBy']) {
                // Idempotent retry of a previously saved transition.
              } else if (current['status'] == 'secured' &&
                  current['acknowledged'] == true) {
                await ref.update({
                  'status': 'reopened',
                  'reopenedBy': cloudPayload['reopenedBy'],
                  'reopenedAt': cloudPayload['reopenedAt'],
                  'updatedAt': cloudPayload['updatedAt'],
                });
              } else {
                throw StateError('لم يتم تأمين الموقع أو تأكيد استلام البلاغ.');
              }
            }
          } else if (item.entity == 'equipment_dispatch' &&
              item.operation == 'dispatch') {
            final actorId = FirebaseAuth.instance.currentUser?.uid ?? '';
            final equipmentId = '${payload['equipmentId'] ?? ''}'.trim();
            final municipality = '${payload['municipality'] ?? ''}'.trim();
            if (actorId.isEmpty || equipmentId.isEmpty || municipality.isEmpty ||
                payload['requestedBy'] != actorId) {
              throw StateError('طلب توجيه الآلية غير مكتمل أو يخص حسابًا آخر.');
            }
            final db = FirebaseFirestore.instance;
            final equipmentRef = db.collection('equipment').doc(equipmentId);
            await db.runTransaction((tx) async {
              final request = await tx.get(ref);
              final equipment = await tx.get(equipmentRef);
              if (request.exists) {
                final saved = request.data();
                if (saved?['_entity'] == 'equipment_dispatch' &&
                    saved?['equipmentId'] == equipmentId &&
                    saved?['municipality'] == municipality &&
                    saved?['requestedBy'] == actorId &&
                    saved?['status'] == 'applied') return;
                throw StateError('معرّف التوجيه مستخدم لعملية أخرى.');
              }
              final current = equipment.data();
              if (current == null || current['isDeleted'] == true ||
                  current['dispatchStatus'] == 'dispatched' ||
                  const ['cart', 'كارة'].contains(
                    '${current['type'] ?? current['category'] ?? ''}'.toLowerCase()) ||
                  const ['out_of_service', 'maintenance', 'broken'].contains(
                    '${current['status'] ?? ''}'.toLowerCase())) {
                throw StateError('الآلية غير متاحة للتوجيه؛ حدّث بياناتها.');
              }
              final now = DateTime.now().toIso8601String();
              tx.update(equipmentRef, {
                'dispatchStatus': 'dispatched',
                'dispatchMunicipality': municipality,
                'dispatchRequestId': docId,
                'dispatchBy': actorId,
                'dispatchAt': now,
              });
              tx.set(ref, {
                ...cloudPayload,
                'id': docId,
                '_entity': 'equipment_dispatch',
                'requestedBy': actorId,
                'equipmentId': equipmentId,
                'municipality': municipality,
                'status': 'applied',
                'updatedAt': now,
              });
            });
          } else if (item.entity == 'attendance_checkout') {
            await FirebaseFunctions.instance.httpsCallable('recordAttendanceCheckout').call(<String, dynamic>{'attendanceId': docId});
          } else if (item.entity == 'work_report' || item.entity == 'report_approval') {
            // These records use a trusted callable because the deployed rules are
            // intentionally unchanged and only permit existing report workflows.
            await FirebaseFunctions.instance.httpsCallable('saveOperationalReport').call(<String, dynamic>{
              'sourceEntity': item.entity,
              'operation': item.operation,
              'report': <String, dynamic>{...cloudPayload, 'reportKind': item.entity},
            });
          } else if (item.operation == 'delete') {
            await ref.set({
              ...cloudPayload,
              'isDeleted': true,
              'updatedAt': FieldValue.serverTimestamp(),
              '_entity': item.entity
            }, SetOptions(merge: true));
          } else {
            await ref.set({
              ...cloudPayload,
              'updatedAt': FieldValue.serverTimestamp(),
              '_entity': item.entity
            }, SetOptions(merge: true));
          }

          completed++;
          if (item.entity == 'cart_redirect') {
            await _applyConfirmedCartRedirect(
              payload,
              coordinatorId: FirebaseAuth.instance.currentUser?.uid,
            );
            // The Firestore transaction committed the real cart assignment. Refresh the scoped
            // equipment cache instead of showing a synthetic local redirect record.
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid != null && payload['cartCollection'] == 'equipment') {
              try {
                final snapshot = await FirebaseFirestore.instance.collection('equipment')
                    .where('municipalityCoordinatorId', isEqualTo: uid).limit(1000).get();
                await store.saveCachedEquipmentCarts(uid, snapshot.docs.map((doc) => {
                  ...doc.data(), 'id': doc.id, '_cartCollection': 'equipment', '_entity': 'equipment',
                }).where((cart) => cart['isDeleted'] != true).toList());
              } catch (error) {
                debugPrint('Cart cache refresh deferred: $error');
              }
            }
          } else if (item.entity != 'equipment_dispatch') {
            _applyLocalOperation(item.entity == 'attendance_checkout' ? 'attendance' : item.entity, item.operation, cloudPayload);
          }
          queue = queue.where((e) => e.id != item.id).toList();
          await store.saveQueue(queue);
          if (attachmentPath != null && attachmentPath.isNotEmpty) {
            try {
              final file = File(attachmentPath);
              if (await file.exists()) await file.delete();
            } catch (error) {
              debugPrint('Unable to remove uploaded local attachment: $error');
            }
          }
        } catch (itemError) {
          lastSyncError = '$itemError';
          debugPrint('تعذر مزامنة العنصر ${item.id}: $itemError');
        }
      }

      if (queue.isEmpty) lastSyncError = null;
      if (completed > 0) {
        lastSync = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
        await store.saveLastSync(lastSync);
        await refreshOperations();
        await refreshSosInbox();
        await notifyUser('المزامنة مكتملة', 'تمت مزامنة $completed عملية بنجاح.', level: 'success');
        await addActivity('مزامنة البيانات', 'تم رفع $completed عملية إلى السحابة.', level: 'success');
      }
    } finally {
      syncing = false;
      notifyListeners();
    }
  }
}
