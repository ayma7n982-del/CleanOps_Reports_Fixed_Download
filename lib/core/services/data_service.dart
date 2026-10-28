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
      if (syncing || queue.isEmpty) return;
      final connections = await Connectivity().checkConnectivity();
      online = !connections.contains(ConnectivityResult.none);
      if (online) unawaited(sync());
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

  Future<void> enqueue(String entity, String operation, Map<String, dynamic> payload) async {
    final safePayload = Map<String, dynamic>.from(_toJsonSafe(payload) as Map);
    final item = SyncItem(
      id: uuid.v4(),
      entity: entity,
      operation: operation,
      payload: jsonEncode(safePayload),
      createdAt: DateTime.now().toIso8601String(),
    );
    queue = [...queue, item];
    await store.saveQueue(queue);
    if (entity != 'cart_redirect') {
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
          item.entity == 'cart_redirect') continue;
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

  Future<void> _uploadAttachment(Map<String, dynamic> payload) async {
    final localPath = '${payload['localAttachmentPath'] ?? ''}';
    if (localPath.isEmpty) return;
    final file = File(localPath);
    if (!await file.exists()) {
      payload['attachmentWarning'] = 'ملف المرفق المحلي مفقود';
      payload.remove('localAttachmentPath');
      return;
    }
    final kind = '${payload['attachmentType'] ?? ''}';
    final userId = '${payload['userId'] ?? payload['reportedBy'] ?? 'unknown'}';
    final operationId = '${payload['id'] ?? uuid.v4()}';
    late final String url;
    if (kind == 'audio') {
      final ref = FirebaseStorage.instance.ref('audio/$userId/$operationId/emergency.m4a');
      await ref.putFile(file, SettableMetadata(contentType: 'audio/mp4'));
      url = await ref.getDownloadURL();
    } else {
      final ref = FirebaseStorage.instance.ref('photos/$userId/$operationId/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      url = await ref.getDownloadURL();
    }
    payload['attachmentUrl'] = url;
    payload.remove('localAttachmentPath');
    payload.remove('attachmentType');
    try {
      await file.delete();
    } catch (_) {}
  }

  Future<void> sync() async {
    if (!online || syncing || queue.isEmpty ||
        (Firebase.apps.isEmpty && _syncItemOverride == null)) {
      return;
    }
    syncing = true;
    notifyListeners();
    var completed = 0;

    try {
      for (final item in List.from(queue)) {
        try {
          final payload = Map<String, dynamic>.from(jsonDecode(item.payload));

          // Deterministic test seam for the complete offline -> online queue
          // lifecycle. Production never supplies this override.
          if (_syncItemOverride != null) {
            await _syncItemOverride!(item, payload);
            completed++;
            _applyLocalOperation(
              item.entity == 'attendance_checkout' ? 'attendance' : item.entity,
              item.operation,
              payload,
            );
            queue = queue.where((e) => e.id != item.id).toList();
            await store.saveQueue(queue);
            continue;
          }

          if (payload['localAttachmentPath'] != null && '${payload['localAttachmentPath']}'.isNotEmpty) {
            try {
              await _uploadAttachment(payload);
            } catch (attErr) {
              debugPrint('تعذر رفع المرفق للعنصر ${item.id}: $attErr');
            }
          }

          final collection = item.entity == 'audit' ? 'audit' : (item.entity == 'container' ? 'containers' : 'operations');
          final docId = payload['id']?.toString() ?? item.id;
          final ref = FirebaseFirestore.instance.collection(collection).doc(docId);

          if (item.entity == 'audit') {
            await ref.set({
              ...payload,
              'timestamp': FieldValue.serverTimestamp(),
              'immutable': true,
              '_entity': item.entity
            });
          } else if (item.entity == 'container') {
            // Containers have their own Firestore collection and strict field-level rules.
            // Do not inject the generic _entity marker into this collection.
            await ref.set({
              ...payload,
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
                ...payload,
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
          } else if (item.entity == 'attendance_checkout') {
            await FirebaseFunctions.instance.httpsCallable('recordAttendanceCheckout').call(<String, dynamic>{'attendanceId': docId});
          } else if (item.entity == 'work_report' || item.entity == 'report_approval') {
            // These records use a trusted callable because the deployed rules are
            // intentionally unchanged and only permit existing report workflows.
            await FirebaseFunctions.instance.httpsCallable('saveOperationalReport').call(<String, dynamic>{
              'sourceEntity': item.entity,
              'operation': item.operation,
              'report': <String, dynamic>{...payload, 'reportKind': item.entity},
            });
          } else if (item.operation == 'delete') {
            await ref.set({
              ...payload,
              'isDeleted': true,
              'updatedAt': FieldValue.serverTimestamp(),
              '_entity': item.entity
            }, SetOptions(merge: true));
          } else {
            await ref.set({
              ...payload,
              'updatedAt': FieldValue.serverTimestamp(),
              '_entity': item.entity
            }, SetOptions(merge: true));
          }

          completed++;
          if (item.entity == 'cart_redirect') {
            // Commit is confirmed: update the local assignment immediately even if
            // the subsequent equipment query cannot reach Firestore.
            final cartId = '${payload['cartId'] ?? ''}';
            final destinationId = '${payload['toGroupId'] ?? ''}';
            if (payload['cartCollection'] == 'operations') {
              operations = operations.map((entry) =>
                '${entry['id']}' == cartId && entry['_entity'] != 'cart_redirect'
                    ? {...entry, 'groupId': destinationId}
                    : entry).toList();
            } else {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) {
                final cached = store.cachedEquipmentCarts(uid);
                await store.saveCachedEquipmentCarts(uid, cached.map((entry) =>
                    '${entry['id']}' == cartId
                        ? {...entry, 'groupId': destinationId}
                        : entry).toList());
              }
            }
            operations = operations.where((entry) =>
                !(entry['_entity'] == 'cart_redirect' && '${entry['id']}' == docId)).toList();
            await store.saveCachedOperations(operations.take(1000).toList());
            notifyListeners();
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
          } else {
            _applyLocalOperation(item.entity == 'attendance_checkout' ? 'attendance' : item.entity, item.operation, payload);
          }
          queue = queue.where((e) => e.id != item.id).toList();
          await store.saveQueue(queue);
        } catch (itemError) {
          debugPrint('تعذر مزامنة العنصر ${item.id}: $itemError');
        }
      }

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
