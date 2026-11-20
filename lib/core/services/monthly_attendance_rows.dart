import 'package:cloud_firestore/cloud_firestore.dart';
import 'work_report_summary.dart';

class MonthlyAttendanceRows {
  final Map<String, String> labels = {};
  final Map<String, String> statuses = {};

  MonthlyAttendanceRows(
      List<Map<String, dynamic>> roster, List<Map<String, dynamic>> records) {
    String label(Object? name, Object? role) {
      final suffix = role == 'worker'
          ? ' (عامل)'
          : role == 'group_supervisor'
              ? ' (مشرف)'
              : '';
      return "${name ?? 'غير محدد'}$suffix";
    }

    for (final person in roster) {
      final id = '${person['id'] ?? ''}'.trim();
      if (id.isNotEmpty)
        labels['worker:$id'] = label(person['name'] ?? person['username'] ?? id,
            person['workerRole'] ?? person['role']);
    }
    var index = 0;
    for (final record in records) {
      index++;
      final date = workDay(record);
      if (date == null) continue;
      final workerId = '${record['workerId'] ?? ''}'.trim();
      final id = workerId.isEmpty
          ? "record:${record['id'] ?? index}"
          : 'worker:$workerId';
      labels.putIfAbsent(
          id,
          () => label(record['workerName'] ?? record['name'] ?? workerId,
              record['workerRole']));
      final key = '$id|${date.day}';
      final status = '${record['status'] ?? ''}';
      statuses.update(key, (old) => old == status ? old : 'conflict',
          ifAbsent: () => status);
    }
    final counts = <String, int>{};
    for (final name in labels.values) {
      counts[name] = (counts[name] ?? 0) + 1;
    }
    labels.updateAll((id, name) => counts[name] == 1
        ? name
        : '$name · ${id.substring(id.indexOf(':') + 1)}');
  }

  List<String> get ids =>
      labels.keys.toList()..sort((a, b) => labels[a]!.compareTo(labels[b]!));
  static DateTime? workDay(Map<String, dynamic> r) {
    final value = r['workDate'] ??
        r['attendanceDate'] ??
        r['date'] ??
        r['createdAt'] ??
        r['timestamp'];
    return value is Timestamp ? value.toDate() : WorkReportSummary.date(value);
  }
}
