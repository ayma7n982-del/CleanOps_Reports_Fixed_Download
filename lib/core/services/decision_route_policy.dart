import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/core_models.dart';
import 'trip_dumpsite.dart';

/// Apply a signed-in group's current route directive to new trips only.
Future<Map<String, String>> resolveDecisionRoute(AppUser user, String requested,
    {FirebaseFirestore? firestore, String requestedDumpsiteId = ''}) async {
  final db = firestore ?? FirebaseFirestore.instance;
  final group = user.groupId ?? '';
  if (group.isEmpty) return applyDumpsiteRoutes(requested, requestedDumpsiteId, []);
  final snapshot = await db.collection('strategic_decisions')
      .where('groupId', isEqualTo: group).limit(20000).get();
  if (snapshot.docs.length == 20000) {
    throw StateError('تجاوز سجل القرارات حد القراءة. اطلب مراجعة المسار من المنسق.');
  }
  final now = DateTime.now();
  final routes = snapshot.docs.where((d) {
    final x = d.data(), expiry = x['expiresAt'];
    return x['kind'] == 'dumpsite_redirect' &&
      const ['issued', 'acknowledged', 'completed'].contains(x['status']) &&
      expiry is Timestamp && expiry.toDate().isAfter(now);
  }).toList()..sort((a, b) {
    final at = a.data()['createdAt'], bt = b.data()['createdAt'];
    return (bt is Timestamp ? bt.millisecondsSinceEpoch : 0)
      .compareTo(at is Timestamp ? at.millisecondsSinceEpoch : 0);
  });
  return applyDumpsiteRoutes(requested, requestedDumpsiteId,
      routes.map((doc) => {...doc.data(), 'id': doc.id}).toList());
}

/// Temporary additions to today's roster; the worker's permanent group remains
/// unchanged. Names originate from the authorized operational worker record.
Future<List<Map<String, String>>> temporaryDecisionWorkers(AppUser user,
    {FirebaseFirestore? firestore}) async {
  if ((user.groupId ?? '').isEmpty) return [];
  final snapshot = await (firestore ?? FirebaseFirestore.instance)
      .collection('strategic_decisions').where('groupId', isEqualTo: user.groupId)
      .limit(20000).get();
  if (snapshot.docs.length == 20000) {
    throw StateError('سجل التكليفات كبير؛ يلزم أرشفته قبل حساب كشف مؤقت كامل.');
  }
  final result = <String, Map<String, String>>{};
  for (final doc in snapshot.docs) {
    final d = doc.data(), detail = d['details'], expires = d['expiresAt'];
    if (d['kind'] != 'temporary_coverage' || detail is! Map ||
        detail['assignmentType'] != 'worker' || expires is! Timestamp ||
        !expires.toDate().isAfter(DateTime.now())) continue;
    final id = '${detail['assignmentId']}';
    result[id] = {'id': id, 'name': '${detail['workerName'] ?? id}',
      'job': '${detail['workerJob'] ?? ''}', 'role': 'worker',
      'groupId': user.groupId!, 'group': user.groupId!,
      'groupName': user.groupId!, 'temporaryDecisionId': doc.id};
  }
  return result.values.toList();
}
