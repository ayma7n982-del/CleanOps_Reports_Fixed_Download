import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/core_models.dart';
import 'decision_analytics.dart';

Object? normalizeDecisionValue(Object? value) {
  if (value is Timestamp) return value.toDate().toIso8601String();
  if (value is Map) return value.map((k, v) => MapEntry('$k', normalizeDecisionValue(v)));
  if (value is List) return value.map(normalizeDecisionValue).toList();
  return value;
}

class DecisionHubService extends ChangeNotifier {
  final FirebaseFirestore db;
  final AppUser user;
  final String shiftText;
  final _subscriptions = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
  final _rows = <String, List<DecisionRow>>{};
  final _cached = <String, bool>{};
  final errors = <String, String>{};
  final capped = <String>{};
  final submitted = <String>{};
  final writeErrors = <String, String>{};
  final int pageLimit;
  Timer? _clock;
  bool _disposed = false;
  DecisionHubService({required this.user, required this.shiftText,
      FirebaseFirestore? firestore, this.pageLimit = 2000})
      : db = firestore ?? FirebaseFirestore.instance;
  static bool allowed(AppUser? u) => u != null && u.isActive && u.can('operations', 'view') &&
      const ['municipality_coordinator', 'jsc_coordinator', 'donor_manager'].contains(u.role);
  bool get localOnly => _cached.values.any((c) => c);
  bool get loaded => ['group', 'worker', 'attendance', 'trip', 'containers',
    'dumpsites', 'users', 'work_cycles', 'trips', 'cycles', 'strategic_decisions', 'status_events']
      .every(_rows.containsKey);
  bool get complete => loaded && errors.isEmpty && capped.isEmpty && !localOnly;
  List<DecisionRow> get decisions => _rows['strategic_decisions'] ?? [];
  List<DecisionRow> get plans => _rows['strategic_plans'] ?? [];
  List<DecisionRow> get operations => ['group', 'worker', 'attendance', 'trip']
      .expand((s) => _rows[s] ?? <DecisionRow>[]).toList();
  DecisionAnalytics get analytics => DecisionAnalytics.calculate(
      operations: operations, users: _rows['users'] ?? [],
      containers: (_rows['containers'] ?? <DecisionRow>[]).map((c) => <String, dynamic>{
        ...c, 'statusHistory': (_rows['status_events'] ?? <DecisionRow>[])
          .where((e) => e['containerId'] == c['id']).toList(),
      }).toList(), dumpsites: _rows['dumpsites'] ?? [],
      trips: _rows['trips'] ?? [],
      cycles: [...?_rows['work_cycles'], ...?_rows['cycles']],
      now: DateTime.now(), shiftText: shiftText);

  void start() {
    if (!allowed(user)) return;
    for (final entity in ['group', 'worker', 'attendance', 'trip']) {
      Query<Map<String, dynamic>> q = db.collection('operations')
          .where('_entity', isEqualTo: entity);
      if (user.role == 'municipality_coordinator') {
        q = q.where('municipalityCoordinatorId', isEqualTo: user.id);
      }
      _listen(entity, q);
    }
    for (final collection in ['users', 'containers', 'dumpsites', 'work_cycles',
        'trips', 'cycles', 'strategic_decisions', 'strategic_plans']) {
      Query<Map<String, dynamic>> q = db.collection(collection);
      if (user.role == 'municipality_coordinator' &&
          !const ['dumpsites', 'work_cycles', 'cycles'].contains(collection)) {
        q = q.where(collection == 'containers' ? 'municipalityId' :
            'municipalityCoordinatorId', isEqualTo: user.id);
      }
      _listen(collection, q);
    }
    Query<Map<String, dynamic>> events = db.collectionGroup('status_events');
    if (user.role == 'municipality_coordinator') {
      events = events.where('municipalityId', isEqualTo: user.id);
    }
    _listen('status_events', events);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => _notify());
  }
  void _listen(String name, Query<Map<String, dynamic>> query) {
    _subscriptions.add(query.limit(pageLimit).snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      _rows[name] = snapshot.docs.map((doc) => <String, dynamic>{
        ...Map<String, dynamic>.from(normalizeDecisionValue(doc.data()) as Map),
        'id': doc.id, '_pending': doc.metadata.hasPendingWrites,
      }).toList();
      _cached[name] = snapshot.metadata.isFromCache;
      if (snapshot.docs.length >= pageLimit) { capped.add(name); } else { capped.remove(name); }
      errors.remove(name);
      _notify();
    }, onError: (Object error) {
      errors[name] = '$error';
      _rows.putIfAbsent(name, () => []);
      _notify();
    }));
  }
  String key(String kind, String target, {String? cycleId}) {
    final day = DecisionShift.parse(DateTime.now(), shiftText).start
        .toIso8601String().substring(0, 10);
    return Uri.encodeComponent('${cycleId ?? day}_${user.id}_${kind}_$target')
        .replaceAll('.', '%2E');
  }
  DecisionRow? existing(String id) {
    for (final d in [...decisions, ...plans]) {
      if (d['id'] == id) return d;
    }
    return null;
  }

  /// Native Firestore persistence queues the write on Android. A timeout only
  /// changes the UI to "pending"; it does not cancel or resubmit the write.
  Future<bool> _write(String collection, String id, DecisionRow payload) async {
    if (!allowed(user) || !user.can('operations', 'create')) throw StateError('الدور الحالي لا يملك صلاحية القرار.');
    if (submitted.contains(id) || existing(id) != null) return false;
    submitted.add(id);
    writeErrors.remove(id);
    _notify();
    final future = db.collection(collection).doc(id).set({
      ...payload, 'id': id, 'createdBy': user.id, 'coordinatorName': user.name,
      'createdAt': FieldValue.serverTimestamp(), 'schemaVersion': 1,
    }).then((_) {
      if (!_disposed) { writeErrors.remove(id); _notify(); }
      return true;
    }, onError: (Object error, StackTrace stack) {
      if (!_disposed) {
        submitted.remove(id);
        writeErrors[id] = '$error';
        _notify();
      }
      Error.throwWithStackTrace(error, stack);
    });
    return future.timeout(const Duration(seconds: 3), onTimeout: () => false);
  }

  Future<bool> issue({required String kind, required String title, required String body,
      required String groupId, required String owner, String targetId = '',
      DecisionRow details = const {}}) {
    final kinds = ['stagnation', 'collection', 'temporary_coverage', 'health',
      'ppe', 'dumpsite_redirect', 'broadcast'];
    if (!kinds.contains(kind) || title.trim().isEmpty || body.trim().isEmpty) {
      throw ArgumentError('تفاصيل القرار غير مكتملة.');
    }
    if (kind != 'broadcast' && groupId.isEmpty) throw StateError('اختر مجموعة مستلمة.');
    if (kind != 'broadcast' && !analytics.groups.any((g) =>
        g.id == groupId && g.owner == owner)) throw StateError('المجموعة خارج النطاق.');
    if (user.role == 'municipality_coordinator' && owner != user.id) {
      throw StateError('القرار خارج نطاق البلدية.');
    }
    final shift = DecisionShift.parse(DateTime.now(), shiftText);
    return _write('strategic_decisions', key(kind, targetId.isEmpty ? groupId : targetId), {
      'kind': kind, 'title': title, 'body': body, 'groupId': groupId,
      'municipalityCoordinatorId': owner, 'targetId': targetId,
      'scopeKey': kind == 'broadcast' && user.role != 'municipality_coordinator'
          ? 'global' : 'municipality:$owner',
      'status': 'issued', 'priority': kind == 'health' ? 'critical' : 'urgent',
      'shiftDate': shift.start.toIso8601String().substring(0, 10),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24))),
      'details': details,
    });
  }

  Future<bool> approve(DecisionRecommendation recommendation, String targetCycleId) {
    if (targetCycleId.isEmpty) throw ArgumentError('اسم الدورة القادمة مطلوب.');
    final g = recommendation.group;
    if (!complete || !analytics.groups.any((x) => x.id == g.id)) {
      throw StateError('يلزم اكتمال بيانات الخادم قبل اعتماد التوصية.');
    }
    return _write('strategic_decisions',
      key(recommendation.kind, g.id, cycleId: targetCycleId), {
        'kind': recommendation.kind, 'title': recommendation.title,
        'body': recommendation.reason, 'groupId': g.id,
        'municipalityCoordinatorId': g.owner, 'scopeKey': 'municipality:${g.owner}',
        'targetId': targetCycleId, 'targetCycleId': targetCycleId,
        'status': 'approved', 'priority': 'planning',
        'details': recommendation.toMap(),
      });
  }

  Future<bool> savePlan(String targetCycleId, List<DecisionRow> approved) {
    if (targetCycleId.trim().isEmpty || approved.isEmpty || approved.length > 100) {
      throw ArgumentError('اختر من 1 إلى 100 توصية معتمدة للدورة القادمة.');
    }
    if (approved.any((r) => r['_pending'] == true || r['status'] != 'approved' ||
        r['targetCycleId'] != targetCycleId)) {
      throw StateError('انتظر تأكيد الخادم لجميع التوصيات.');
    }
    // The plan references immutable approved decision documents. No workforce
    // assignment is changed until its scheduled cycle is explicitly activated.
    return _write('strategic_plans', key('plan', 'master', cycleId: targetCycleId), {
      'targetCycleId': targetCycleId, 'status': 'approved',
      'municipalityCoordinatorId': user.role == 'municipality_coordinator' ? user.id : '',
      'decisionIds': approved.map((r) => r['id']).toList(),
      'recommendations': approved.map((r) => {'decisionId': r['id'],
        'title': r['title'], 'groupId': r['groupId'],
        'municipalityCoordinatorId': r['municipalityCoordinatorId'],
        'details': r['details']}).toList(),
      'sourceCycleId': analytics.cycleId,
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _clock?.cancel();
    for (final sub in _subscriptions) { sub.cancel(); }
    super.dispose();
  }
  void _notify() { if (!_disposed) notifyListeners(); }
}
