import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/core_models.dart';

/// Apply a signed-in group's current route directive to new trips only.
Future<Map<String, String>> resolveDecisionRoute(AppUser user, String requested,
    {FirebaseFirestore? firestore}) async {
  final db = firestore ?? FirebaseFirestore.instance;
  final group = user.groupId ?? '';
  if (group.isEmpty) return {'landfill': requested};
  final snapshot = await db.collection('strategic_decisions')
      .where('groupId', isEqualTo: group).limit(200).get();
  if (snapshot.docs.length == 200) {
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
  var landfill = requested;
  final used = <String>[], visited = <String>{requested};
  for (var step = 0; step < routes.length; step++) {
    QueryDocumentSnapshot<Map<String, dynamic>>? match;
    for (final r in routes) {
      final detail = r.data()['details'];
      if (detail is Map && [detail['sourceName'], detail['sourceId']].contains(landfill)) {
        match = r; break;
      }
    }
    if (match == null) break;
    final details = match.data()['details'] as Map;
    final next = '${details['alternativeName'] ?? ''}'.trim();
    if (next.isEmpty || !visited.add(next)) {
      throw StateError('يوجد تعارض في توجيهات المكبات. راجع المنسق قبل تسجيل النقلة.');
    }
    landfill = next; used.add(match.id);
  }
  return {'landfill': landfill, if (used.isNotEmpty) 'routeDecisionId': used.join(',')};
}
