import 'package:cloud_firestore/cloud_firestore.dart';

/// Normalizes confirmed operational timestamps from Firestore and local caches.
/// Source records can contain Timestamp, DateTime, ISO-8601 text or epoch time.
class OperationalActivity {
  const OperationalActivity._();

  static DateTime? asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) {
      // Some legacy records store epoch seconds rather than milliseconds.
      final milliseconds = value.abs() < 100000000000
          ? value * 1000 : value;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
    if (value is String) return DateTime.tryParse(value.trim());
    return null;
  }

  static DateTime? timestamp(Map<String, dynamic> operation) {
    for (final key in const [
      'createdAt', 'workDate', 'date', 'timestamp', 'updatedAt'
    ]) {
      final value = asDate(operation[key]);
      if (value != null) return value;
    }
    return null;
  }

  static List<Map<String, dynamic>> ordered(
    Iterable<Map<String, dynamic>> records,
  ) {
    final dated = records.where((row) => timestamp(row) != null).toList();
    dated.sort((a, b) => timestamp(b)!.compareTo(timestamp(a)!));
    return dated;
  }

  static int countOnDate(
    Iterable<Map<String, dynamic>> records, DateTime localDay,
  ) {
    return records.where((row) {
      final moment = timestamp(row)?.toLocal();
      return moment != null &&
          moment.year == localDay.year &&
          moment.month == localDay.month &&
          moment.day == localDay.day;
    }).length;
  }

  static String label(Map<String, dynamic> operation) {
    final date = timestamp(operation)?.toLocal();
    if (date == null) return 'بدون تاريخ';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }
}
