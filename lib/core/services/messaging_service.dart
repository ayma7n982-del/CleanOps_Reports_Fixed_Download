import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/core_models.dart';
import 'local_store.dart';
import 'config_service.dart';

class MessageItem {
  final String messageId;
  final String senderId;
  final String? targetUserId;
  final String? targetGroupId;
  final String? replyToMessageId;
  final String content;
  final DateTime timestamp;
  final String type;
  final bool isRead;
  final String senderName;
  final String senderRole;
  /// Local send state: pending, sent (server-acknowledged), or failed.
  final String deliveryStatus;

  const MessageItem({
    required this.messageId,
    required this.senderId,
    required this.content,
    required this.timestamp,
    required this.type,
    required this.isRead,
    this.targetUserId,
    this.targetGroupId,
    this.replyToMessageId,
    this.senderName = '',
    this.senderRole = '',
    this.deliveryStatus = 'sent',
  });

  bool isForUser(String uid, String? groupId) =>
      senderId == uid || targetUserId == uid ||
      (targetGroupId != null && targetGroupId!.isNotEmpty && targetGroupId == groupId) ||
      targetGroupId == MessagingService.allMunicipalitiesGroup;

  Map<String, dynamic> toLocalJson() => {
        'messageId': messageId,
        'senderId': senderId,
        'targetUserId': targetUserId,
        'targetGroupId': targetGroupId,
        'replyToMessageId': replyToMessageId,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'type': type,
        'isRead': isRead,
        'senderName': senderName,
        'senderRole': senderRole,
        'deliveryStatus': deliveryStatus,
      };

  factory MessageItem.fromLocal(Map<String, dynamic> json) => MessageItem(
        messageId: '${json['messageId'] ?? json['id'] ?? ''}',
        senderId: '${json['senderId'] ?? ''}',
        targetUserId: json['targetUserId']?.toString(),
        targetGroupId: json['targetGroupId']?.toString(),
        replyToMessageId: json['replyToMessageId']?.toString(),
        content: '${json['content'] ?? ''}',
        timestamp: DateTime.tryParse('${json['timestamp'] ?? ''}') ?? DateTime.now(),
        type: '${json['type'] ?? 'info'}',
        isRead: json['isRead'] == true,
        senderName: '${json['senderName'] ?? ''}',
        senderRole: '${json['senderRole'] ?? ''}',
        deliveryStatus: '${json['deliveryStatus'] ?? 'sent'}',
      );

  factory MessageItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final rawTs = data['timestamp'];
    final timestamp = rawTs is Timestamp ? rawTs.toDate() : (DateTime.tryParse('${rawTs ?? ''}') ?? DateTime.now());
    return MessageItem(
      messageId: '${data['messageId'] ?? doc.id}',
      senderId: '${data['senderId'] ?? ''}',
      targetUserId: data['targetUserId']?.toString(),
      targetGroupId: data['targetGroupId']?.toString(),
      replyToMessageId: data['replyToMessageId']?.toString(),
      content: '${data['content'] ?? ''}',
      timestamp: timestamp,
      type: '${data['type'] ?? 'info'}',
      isRead: data['isRead'] == true,
      senderName: '${data['senderName'] ?? ''}',
      senderRole: '${data['senderRole'] ?? ''}',
      deliveryStatus: doc.metadata.hasPendingWrites ? 'pending' : 'sent',
    );
  }
}

class MessagingService extends ChangeNotifier {
  static const allMunicipalitiesGroup = '__ALL_MUNICIPALITIES__';
  final LocalStore store;
  final ConfigService config;
  final Uuid _uuid = const Uuid();
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _subscriptions = [];
  final Set<String> _inFlightWrites = <String>{};
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  AppUser? _user;
  String? _uid;
  String? _groupId;
  List<MessageItem> messages = [];
  bool syncing = false;
  String? lastError;

  MessagingService(this.store, this.config);

  Future<void> init(AppUser? user) async {
    await attachUser(user);
    _connectivitySub ??= Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) {
        unawaited(retryPendingWrites());
      }
    });
  }

  Future<void> attachUser(AppUser? user) async {
    await _cancelStreams();
    _user = user;
    _uid = user?.id;
    _groupId = user?.groupId;
    messages = (user == null || !config.localMessagingEnabled) ? [] : store.cachedMessages(user.id).map(MessageItem.fromLocal).toList();
    _applyLocalReadState();
    notifyListeners();
    if (user == null || !config.onlineMessagingEnabled || Firebase.apps.isEmpty) return;
    await _subscribe();
    unawaited(retryPendingWrites());
  }

  Future<void> _subscribe() async {
    final uid = _uid;
    if (uid == null) return;
    final firestore = FirebaseFirestore.instance;
    final queries = <Query<Map<String, dynamic>>>[
      firestore.collection('messages').where('targetGroupId', isEqualTo: '__USER__:$uid'),
      firestore.collection('messages').where('senderId', isEqualTo: uid),
    ];
    if ((_groupId ?? '').isNotEmpty) {
      queries.add(firestore.collection('messages').where('targetGroupId', isEqualTo: _groupId));
    }
    if (_user?.role == 'municipality_coordinator') {
      queries.add(firestore.collection('messages').where('targetGroupId', isEqualTo: allMunicipalitiesGroup));
    }
    if (_user?.role == 'jsc_coordinator') {
      queries.add(firestore.collection('messages').where('targetGroupId', isEqualTo: '__JSC__'));
    }
    for (final query in queries) {
      _subscriptions.add(query.snapshots(includeMetadataChanges: true).listen((snapshot) {
        for (final doc in snapshot.docs) {
          _mergeMessage(MessageItem.fromFirestore(doc));
        }
        unawaited(_saveCache());
      }, onError: (Object error, StackTrace stack) {
        lastError = error.toString();
        debugPrint('Messaging stream error: $error');
        notifyListeners();
      }));
    }
  }

  Future<void> _cancelStreams() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }

  void _mergeMessage(MessageItem message) {
    final index = messages.indexWhere((m) => m.messageId == message.messageId);
    if (index >= 0) {
      final local = messages[index];
      messages[index] = MessageItem(
        messageId: message.messageId,
        senderId: message.senderId,
        targetUserId: message.targetUserId,
        targetGroupId: message.targetGroupId,
        replyToMessageId: message.replyToMessageId,
        content: message.content,
        timestamp: message.timestamp,
        type: message.type,
        isRead: local.isRead || message.isRead,
        senderName: message.senderName,
        senderRole: message.senderRole,
        deliveryStatus: message.deliveryStatus,
      );
    } else {
      messages.add(message);
    }
    messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (messages.length > 500) messages = messages.take(500).toList();
    _applyLocalReadState();
    notifyListeners();
  }

  void _applyLocalReadState() {
    final uid = _uid;
    if (uid == null) return;
    final readIds = store.messageReadIds(uid).toSet();
    messages = messages.map((m) => readIds.contains(m.messageId) ? MessageItem(
      messageId: m.messageId,
      senderId: m.senderId,
      targetUserId: m.targetUserId,
      targetGroupId: m.targetGroupId,
      replyToMessageId: m.replyToMessageId,
      content: m.content,
      timestamp: m.timestamp,
      type: m.type,
      isRead: true,
      senderName: m.senderName,
      senderRole: m.senderRole,
      deliveryStatus: m.deliveryStatus,
    ) : m).toList();
  }

  Future<void> _saveCache() async {
    final uid = _uid;
    if (uid == null) return;
    await store.saveCachedMessages(uid, messages.map((m) => m.toLocalJson()).toList());
  }

  int get unreadCount => messages.where((m) => m.senderId != _uid && !m.isRead).length;

  bool canSend(String type) {
    switch (_user?.role) {
      case 'donor_manager':
      case 'jsc_coordinator':
        return true;
      case 'municipality_coordinator':
        return true;
      case 'group_supervisor':
        return type == 'info' || type == 'emergency';
      default:
        return false;
    }
  }

  Future<void> sendBroadcast({required String content, required String type, String? groupId}) async {
    final user = _user;
    if (user == null || !canSend(type)) throw StateError('ليس لديك صلاحية إرسال هذا النوع من الرسائل.');
    final requestedGroup = (groupId ?? '').trim();
    if (user.role == 'group_supervisor' &&
        (user.groupId == null || user.groupId!.isEmpty ||
         (requestedGroup.isNotEmpty && requestedGroup != user.groupId))) {
      throw StateError('رئيس المجموعة يستطيع الإرسال إلى مجموعته المرتبطة فقط.');
    }
    final targetGroup = user.role == 'donor_manager' || user.role == 'jsc_coordinator'
        ? allMunicipalitiesGroup
        : (user.role == 'group_supervisor' ? user.groupId! : (groupId ?? _groupId ?? ''));
    if (targetGroup.isEmpty) throw StateError('لم يتم تحديد المجموعة المستهدفة.');
    await _send(
      content: content,
      type: type,
      targetGroupId: targetGroup,
    );
  }

  Future<void> sendContainerAlert(dynamic container, String event) async {
    final user = _user;
    if (user == null) return;
    final municipalityId = '${container.municipalityId ?? ''}';
    final location = '${container.locationName ?? ''}';
    final groupId = '${container.groupId ?? ''}';
    final status = '${container.status ?? ''}';
    final issue = '${container.issueStatus ?? ''}';
    String text;
    String type = 'warning';
    switch (event) {
      case 'full':
        text = 'حاوية ممتلئة: $location • الحالة: ممتلئة${groupId.isEmpty ? '' : ' • المجموعة $groupId'}';
        type = 'emergency';
        break;
      case 'emptied':
        text = 'تم تفريغ الحاوية: $location • عادت إلى حالة فارغة.';
        type = 'info';
        break;
      case 'issue':
        text = 'مشكلة حاوية مسجلة: $location • ${container.feedbackNotes ?? ''}';
        type = 'warning';
        break;
      case 'resolving':
        text = 'إجراء تصحيحي قيد المعالجة للحاوية: $location.';
        type = 'warning';
        break;
      case 'resolved':
        text = 'تم تأكيد حل مشكلة الحاوية: $location.';
        type = 'info';
        break;
      default:
        text = 'تحديث حالة الحاوية: $location • $status • $issue';
    }
    // Container alerts are delivered to the municipality coordinator and JSC.
    final municipalityTarget = (user.municipalityCoordinatorId ?? '').isNotEmpty
        ? user.municipalityCoordinatorId! : municipalityId;
    if (municipalityTarget.isNotEmpty && (user.role == 'group_supervisor' || user.role == 'worker')) {
      await _send(content: text, type: type, targetUserId: municipalityTarget);
      // Field workers escalate only genuine emergency-class alerts. Other
      // operational updates go to their municipality coordinator first.
      if (user.role == 'group_supervisor' || type == 'emergency') {
        await _send(content: text, type: type, targetGroupId: '__JSC__');
      }
    } else if (user.role == 'municipality_coordinator') {
      await _send(content: text, type: type, targetGroupId: '__JSC__');
    } else if (user.role == 'jsc_coordinator') {
      await _send(content: text, type: type, targetGroupId: '__ALL_MUNICIPALITIES__');
    }
  }

  Future<void> sendToUser({required String targetUserId, required String content, required String type, String? replyToMessageId}) async {
    final user = _user;
    if (user == null || !canSend(type)) throw StateError('ليس لديك صلاحية إرسال الرسائل.');
    if (targetUserId.trim().isEmpty) throw ArgumentError('المرسل إليه غير محدد.');
    if (user.role == 'group_supervisor' && targetUserId.trim() != user.municipalityCoordinatorId) {
      throw StateError('رئيس المجموعة يستطيع إرسال رسالة مباشرة إلى منسق بلديته فقط.');
    }
    await _send(content: content, type: type, targetUserId: targetUserId.trim(), replyToMessageId: replyToMessageId);
  }

  /// Add up to five compressed photos only after the parent message reaches
  /// Firestore. Attachment uploads require network; they are never mislabeled
  /// as offline-synchronized message text.
  Future<void> addMessageImages(String messageId, List<Uint8List> images) async {
    final actor = _user;
    if (actor == null || Firebase.apps.isEmpty || !config.onlineMessagingEnabled) {
      throw StateError('رفع الصور يحتاج اتصال Firebase.');
    }
    final matches = messages.where((m) => m.messageId == messageId &&
        m.senderId == actor.id && m.deliveryStatus == 'sent');
    if (matches.isEmpty) {
      throw StateError('انتظر تأكيد حفظ الرسالة على الخادم قبل إرفاق الصور.');
    }
    if (images.isEmpty || images.length > 5) {
      throw ArgumentError('اختر من صورة واحدة إلى خمس صور.');
    }
    for (final original in images) {
      Uint8List compressed = original;
      for (final quality in const [75, 60, 45, 30, 20]) {
        compressed = await FlutterImageCompress.compressWithList(
          original, quality: quality, format: CompressFormat.jpeg,
          minWidth: 1280, minHeight: 1280,
        );
        if (compressed.length <= 500 * 1024) break;
      }
      if (compressed.isEmpty || compressed.length > 500 * 1024) {
        throw StateError('الصورة كبيرة جدًا حتى بعد الضغط؛ اختر صورة أصغر.');
      }
      final attachmentId = _uuid.v4();
      final path = 'message_attachments/$messageId/$attachmentId.jpg';
      final object = FirebaseStorage.instance.ref().child(path);
      await object.putData(compressed, SettableMetadata(contentType: 'image/jpeg'));
      try {
        await FirebaseFirestore.instance.collection('messages').doc(messageId)
            .collection('attachments').doc(attachmentId).set({
          'attachmentId': attachmentId,
          'path': path,
          'contentType': 'image/jpeg',
          'sizeBytes': compressed.length,
          'senderId': actor.id,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Never leave an uploaded object publicly accessible or orphaned when
        // the authoritative attachment metadata cannot be persisted.
        try { await object.delete(); } catch (_) {}
        rethrow;
      }
    }
  }

  Future<String> scheduleInternalMessage({
    required String content,
    required String type,
    required DateTime sendAt,
    String? targetGroupId,
    String? targetUserId,
  }) async {
    final user = _user;
    if (user == null || !canSend(type)) {
      throw StateError('ليس لديك صلاحية جدولة هذه الرسالة.');
    }
    if (Firebase.apps.isEmpty || !config.onlineMessagingEnabled) {
      throw StateError('جدولة الرسائل تتطلب اتصال Firebase.');
    }
    final text = content.trim();
    if (text.isEmpty || text.length > 3000) {
      throw ArgumentError('نص الرسالة مطلوب وبحد أقصى 3000 حرف.');
    }
    if (targetGroupId == null && targetUserId == null) {
      throw ArgumentError('يجب تحديد وجهة الرسالة.');
    }
    try {
      final response = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('scheduleInternalMessage')
          .call<Map<String, dynamic>>({
        'requestId': _uuid.v4(),
        'content': text,
        'type': type,
        'scheduledAt': sendAt.toUtc().toIso8601String(),
        if (targetGroupId != null) 'targetGroupId': targetGroupId,
        if (targetUserId != null) 'targetUserId': targetUserId,
      });
      return '${response.data['status'] ?? 'unknown'}';
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? 'تعذر تسجيل جدولة الرسالة.');
    }
  }

  Future<void> cancelScheduledMessage(String scheduleId) async {
    if (Firebase.apps.isEmpty) throw StateError('Firebase غير متاح.');
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('cancelScheduledMessage')
          .call<Map<String, dynamic>>({'id': scheduleId});
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? 'تعذر إلغاء الجدولة.');
    }
  }

  Future<String> sendExternalSms({
    required String targetUserId,
    required String content,
  }) async {
    final actor = _user;
    if (actor == null ||
        !const ['donor_manager', 'jsc_coordinator', 'municipality_coordinator'].contains(actor.role)) {
      throw StateError('هذه القناة مخصصة للإدارة.');
    }
    if (Firebase.apps.isEmpty || !config.onlineMessagingEnabled) {
      throw StateError('تحتاج الرسائل الخارجية لاتصال فعّال بخادم Firebase.');
    }
    final text = content.trim();
    if (text.isEmpty || text.length > 500 || targetUserId.trim().isEmpty) {
      throw ArgumentError('حدد المستلم واكتب نصًا من 1 إلى 500 حرف.');
    }
    // The server resolves the phone number from the recipient's Firestore
    // profile and enforces municipality and role scope.
    try {
      final response = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('sendExternalSms')
          .call<Map<String, dynamic>>({
        'targetUserId': targetUserId.trim(),
        'content': text,
        'requestId': _uuid.v4(),
      });
      return '${response.data['status'] ?? 'unknown'}';
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? 'تعذر تأكيد إرسال SMS من الخادم.');
    }
  }

  Future<void> _send({required String content, required String type, String? targetUserId, String? targetGroupId, String? replyToMessageId}) async {
    final user = _user;
    if (user == null) throw StateError('لا توجد جلسة مستخدم.');
    final body = content.trim();
    if (body.isEmpty) throw ArgumentError('محتوى الرسالة مطلوب.');
    if (!const ['info', 'warning', 'emergency'].contains(type)) throw ArgumentError('نوع الرسالة غير صالح.');
    final id = _uuid.v4();
    final message = MessageItem(
      messageId: id,
      senderId: user.id,
      targetUserId: targetUserId,
      targetGroupId: targetGroupId,
      replyToMessageId: replyToMessageId,
      content: body,
      timestamp: DateTime.now(),
      type: type,
      isRead: true,
      senderName: user.name,
      senderRole: user.role,
      deliveryStatus: 'pending',
    );
    _mergeMessage(message);
    if (config.localMessagingEnabled && config.saveSentMessagesLocally) await _saveCache();
    lastError = null;
    notifyListeners();

    if (!config.onlineMessagingEnabled || Firebase.apps.isEmpty) {
      lastError = 'الاتصال بالخادم غير جاهز. الرسالة معلّقة محليًا، وليست مُرسلة.';
      notifyListeners();
      return;
    }
    // Do not await a Firestore write here: offline .set() can wait until
    // reconnection. The UI returns immediately with an explicit PENDING state.
    unawaited(_writeMessage(message));
  }

  void _setDeliveryState(String messageId, String userId, String status) {
    if (_uid != userId) return; // A different user may have signed in.
    final index = messages.indexWhere((m) => m.messageId == messageId);
    if (index < 0) return;
    final m = messages[index];
    messages[index] = MessageItem(
      messageId: m.messageId,
      senderId: m.senderId,
      content: m.content,
      timestamp: m.timestamp,
      type: m.type,
      isRead: m.isRead,
      targetUserId: m.targetUserId,
      targetGroupId: m.targetGroupId,
      senderName: m.senderName,
      senderRole: m.senderRole,
      deliveryStatus: status,
    );
    unawaited(_saveCache());
    notifyListeners();
  }

  Future<void> _writeMessage(MessageItem message) async {
    if (!_inFlightWrites.add(message.messageId)) return;
    try {
      final target = message.targetUserId != null
          ? '__USER__:${message.targetUserId}' : message.targetGroupId;
      await FirebaseFirestore.instance.collection('messages')
          .doc(message.messageId).set({
        'messageId': message.messageId,
        'senderId': message.senderId,
        'targetGroupId': target,
        if (message.targetUserId != null) 'targetUserId': message.targetUserId,
        if (message.replyToMessageId != null) 'replyToMessageId': message.replyToMessageId,
        'content': message.content,
        'timestamp': Timestamp.fromDate(message.timestamp),
        'type': message.type,
        'isRead': false,
      });
      _setDeliveryState(message.messageId, message.senderId, 'sent');
      if (_uid == message.senderId) {
        lastError = null;
        notifyListeners();
      }
    } on FirebaseException catch (e) {
      final permanent = const {
        'permission-denied', 'unauthenticated', 'invalid-argument',
        'failed-precondition',
      }.contains(e.code);
      _setDeliveryState(
        message.messageId, message.senderId, permanent ? 'failed' : 'pending');
      if (_uid == message.senderId) {
        lastError = permanent
            ? 'رفض Firebase الرسالة: ${e.message ?? e.code}'
            : 'تعذر الاتصال حاليًا؛ الرسالة بانتظار المزامنة.';
        notifyListeners();
      }
      debugPrint('Messaging write ${permanent ? "rejected" : "pending"}: $e');
    } catch (e) {
      _setDeliveryState(message.messageId, message.senderId, 'failed');
      if (_uid == message.senderId) {
        lastError = 'فشل إرسال الرسالة: $e';
        notifyListeners();
      }
      debugPrint('Messaging write failed: $e');
    } finally {
      _inFlightWrites.remove(message.messageId);
    }
  }

  Future<void> retryFailedMessage(String messageId) async {
    final message = messages.where((m) =>
        m.messageId == messageId && m.senderId == _uid &&
        m.deliveryStatus == 'failed').firstOrNull;
    if (message == null) return;
    if (!config.onlineMessagingEnabled || Firebase.apps.isEmpty) {
      throw StateError('Firebase غير متاح حاليًا.');
    }
    _setDeliveryState(message.messageId, message.senderId, 'pending');
    unawaited(_writeMessage(message));
  }

  Future<void> markRead(String messageId, {bool recordReceipt = true}) async {
    final uid = _uid;
    if (uid == null) return;
    final readIds = store.messageReadIds(uid).toSet()..add(messageId);
    await store.saveMessageReadIds(uid, readIds.toList());
    final index = messages.indexWhere((m) => m.messageId == messageId);
    if (index >= 0) {
      final m = messages[index];
      messages[index] = MessageItem(
        messageId: m.messageId,
        senderId: m.senderId,
        targetUserId: m.targetUserId,
        targetGroupId: m.targetGroupId,
        replyToMessageId: m.replyToMessageId,
        content: m.content,
        timestamp: m.timestamp,
        type: m.type,
        isRead: true,
        senderName: m.senderName,
        senderRole: m.senderRole,
        deliveryStatus: m.deliveryStatus,
      );
      await _saveCache();
      notifyListeners();
    }
    if (recordReceipt && config.onlineMessagingEnabled && config.readReceiptsEnabled && Firebase.apps.isNotEmpty) {
      // Each recipient writes their own receipt; a group message's shared
      // isRead field must never be changed by one member reading it.
      unawaited(_writeReceipt(messageId, uid, 'read'));
      final message = messages.firstWhere((m) => m.messageId == messageId, orElse: () => throw StateError('Message not found'));
      if (message.targetGroupId == '__USER__:$uid' || message.targetUserId == uid) {
        try {
          await FirebaseFirestore.instance.collection('messages').doc(messageId).update({'isRead': true});
        } catch (_) {}
      }
    }
  }

  Future<void> _writeReceipt(String messageId, String uid, String status) async {
    if (!config.onlineMessagingEnabled || Firebase.apps.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('messages').doc(messageId)
          .collection('receipts').doc(uid).set({
        'userId': uid,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      debugPrint('Message receipt not yet synchronized: $e');
      // A receipt may legitimately wait for the message document to sync.
      // Never claim that an offline acknowledgement reached the server.
    } catch (e) {
      debugPrint('Message receipt failed: $e');
    }
  }

  Future<void> acknowledgeMessage(String messageId) async {
    final uid = _uid;
    if (uid == null) return;
    final matches = messages.where((m) => m.messageId == messageId && m.senderId != uid);
    if (matches.isEmpty) return;
    // Write a single authoritative receipt instead of racing a 'read'
    // write against the stronger 'acknowledged' state.
    await markRead(messageId, recordReceipt: false);
    if (config.readReceiptsEnabled && config.onlineMessagingEnabled && Firebase.apps.isNotEmpty) {
      unawaited(_writeReceipt(messageId, uid, 'acknowledged'));
    }
  }

  Future<void> retryPendingWrites() async {
    if (!config.autoMessageSync || !config.onlineMessagingEnabled || syncing || Firebase.apps.isEmpty || _uid == null) return;
    syncing = true;
    notifyListeners();
    try {
      // Replay locally queued writes with the original IDs (idempotent).
      // Firestore also replays its own persisted offline queue.
      for (final message in List<MessageItem>.of(messages)) {
        if (message.senderId == _uid && message.deliveryStatus == 'pending') {
          unawaited(_writeMessage(message));
        }
      }
      await _subscribeRefresh();
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> _subscribeRefresh() async {
    if (!config.onlineMessagingEnabled || Firebase.apps.isEmpty) return;
    // Rebinding streams also refreshes any locally queued Firestore writes after reconnect.
    await _cancelStreams();
    await _subscribe();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _connectivitySub?.cancel();
    super.dispose();
  }
}
