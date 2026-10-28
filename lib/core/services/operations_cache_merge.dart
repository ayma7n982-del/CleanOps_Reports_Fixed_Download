/// Merge a fresh server snapshot with locally stored operational records.
///
/// Server values are authoritative once an operation is synchronized.
/// Only records still waiting in the durable offline queue may override
/// corresponding server fields. Cached records missing from a limited server
/// snapshot remain available for offline use.
class OperationsCacheMerge {
  static List<Map<String, dynamic>> merge(
    Iterable<Map<String, dynamic>> server,
    Iterable<Map<String, dynamic>> cached, {
    required Set<String> pendingIds,
  }) {
    final merged = <String, Map<String, dynamic>>{};
    for (final record in server) {
      final id = '${record['id'] ?? ''}'.trim();
      if (id.isNotEmpty) merged[id] = Map<String, dynamic>.from(record);
    }
    for (final record in cached) {
      final id = '${record['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      final remote = merged[id];
      if (remote == null || pendingIds.contains(id)) {
        merged[id] = {...?remote, ...record};
      }
    }
    return merged.values.toList()
      ..sort((a, b) => '${b['createdAt'] ?? ''}'
          .compareTo('${a['createdAt'] ?? ''}'));
  }
}
