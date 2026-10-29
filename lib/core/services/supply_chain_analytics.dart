import 'decision_analytics.dart';

class SupplyPoint {
  final DateTime day;
  int recorded = 0, completed = 0, weighed = 0;
  double tons = 0;
  SupplyPoint(this.day);
}

class SupplyGroup {
  final String id, name;
  int current = 0, previous = 0, weighed = 0;
  double tons = 0;
  SupplyGroup(this.id, this.name);
  double? get change => previous == 0 ? null : (current - previous) / previous;
}

/// Read-only projection of the already authorized, deduplicated hub snapshot.
/// Compare complete calendar days; never compare a partial today to a full day.
class SupplyChainAnalytics {
  final DateTime start, end, previousStart;
  final int days;
  final String? groupId;
  final List<SupplyPoint> trend;
  final List<SupplyGroup> groups;
  final Map<String, int> distribution;
  final bool historyCovered;
  SupplyChainAnalytics._(this.start, this.end, this.previousStart, this.days,
    this.groupId, this.trend, this.groups, this.distribution, this.historyCovered);
  factory SupplyChainAnalytics.from(DecisionAnalytics data,
      {int days = 7, String? groupId}) {
    if (![7, 14, 30].contains(days)) throw ArgumentError.value(days, 'days');
    final end = DateTime(data.now.year, data.now.month, data.now.day);
    final start = DateTime(end.year, end.month, end.day - days);
    final previous = DateTime(end.year, end.month, end.day - days * 2);
    final points = List.generate(days, (i) => SupplyPoint(
      DateTime(start.year, start.month, start.day + i)));
    final selected = data.groups.where((g) => groupId == null || g.id == groupId);
    final rows = <SupplyGroup>[];
    final distribution = {'empty': 0, 'full': 0, 'partial': 0, 'unknown': 0};
    final seen = <String>{};
    for (final g in selected) {
      final row = SupplyGroup(g.id, g.name);
      for (final t in g.historyTrips) {
        final id = '${t['id']}';
        if (id == 'null' || !seen.add(id)) continue;
        // Count all trips by registration/start day, completed status on that cohort.
        final date = decisionDate(t['startedAt'] ?? t['createdAt']);
        if (date == null || date.isBefore(previous) || !date.isBefore(end)) continue;
        final completed = ['completed', 'delivered'].contains(t['status']);
        if (date.isBefore(start)) {
          if (completed) row.previous++;
          continue;
        }
        final index = points.indexWhere((p) => p.day.year == date.year &&
          p.day.month == date.month && p.day.day == date.day);
        if (index < 0) continue;
        final p = points[index];
        p.recorded++;
        if (completed) {
          row.current++; p.completed++;
          final tons = DecisionGroup.tonsOf(t);
          if (tons != null) {
            row.tons += tons; p.tons += tons; row.weighed++; p.weighed++;
          }
        }
      }
      rows.add(row);
    }
    final containers = groupId == null ? data.containers :
        selected.expand((g) => g.containers);
    for (final c in containers) {
      final key = distribution.containsKey(c['status']) ? '${c['status']}' : 'unknown';
      distribution[key] = distribution[key]! + 1;
    }
    return SupplyChainAnalytics._(start, end, previous, days, groupId, points,
      rows, distribution, !data.historyStart.isAfter(previous));
  }
  int get recorded => trend.fold(0, (n, p) => n + p.recorded);
  int get completed => groups.fold(0, (n, g) => n + g.current);
  int get previous => groups.fold(0, (n, g) => n + g.previous);
  int get weighed => groups.fold(0, (n, g) => n + g.weighed);
  double? get tons => weighed == 0 ? null : groups.fold<double>(0, (n, g) => n + g.tons);
  double? get completion => recorded == 0 ? null : completed / recorded;
  double? get change => !historyCovered || previous == 0 ? null : (completed - previous) / previous;
  String get scope => groupId == null ? 'جميع المجموعات ضمن صلاحياتك' :
      groups.isEmpty ? 'مجموعة غير متاحة' : groups.first.name;
  String get period => '${start.day}/${start.month}/${start.year} - '
      '${DateTime(end.year, end.month, end.day - 1).day}/'
      '${DateTime(end.year, end.month, end.day - 1).month}/'
      '${DateTime(end.year, end.month, end.day - 1).year}';
}
