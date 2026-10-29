import 'dart:math' as math;

/// Pure deterministic analytics; the Firestore adapter normalizes timestamps.
typedef DecisionRow = Map<String, dynamic>;

DateTime? decisionDate(Object? value) {
  if (value is DateTime) return value.toLocal();
  return DateTime.tryParse('$value')?.toLocal();
}
double? decisionNumber(Object? value) {
  final n = value is num ? value.toDouble() : double.tryParse('$value');
  return n != null && n.isFinite ? n : null;
}
bool decisionActive(DecisionRow row) => row['isDeleted'] != true &&
    row['isActive'] != false &&
    !const ['frozen', 'deleted', 'inactive'].contains(row['status']);

class DecisionShift {
  final DateTime start, end;
  final String label;
  const DecisionShift(this.start, this.end, this.label);
  bool contains(DateTime value) => !value.isBefore(start) && value.isBefore(end);
  bool activeAt(DateTime now) => contains(now);
  static DecisionShift parse(DateTime now, String text) {
    final times = RegExp(r'(\d{1,2}):(\d{2})').allMatches(text).toList();
    DateTime at(int i) => DateTime(now.year, now.month, now.day,
        int.parse(times[i].group(1)!), int.parse(times[i].group(2)!));
    if (times.length != 2) return DecisionShift(
        DateTime(now.year, now.month, now.day, 8),
        DateTime(now.year, now.month, now.day, 16), '08:00 - 16:00');
    var start = at(0), end = at(1);
    if (!end.isAfter(start)) {
      end = end.add(const Duration(days: 1));
      if (now.isBefore(start)) {
        start = start.subtract(const Duration(days: 1));
        end = end.subtract(const Duration(days: 1));
      }
    }
    return DecisionShift(start, end, text);
  }
}

class DecisionGroup {
  final DecisionRow row;
  final List<DecisionRow> workers, attendance, historyAttendance, trips,
      historyTrips, containers;
  final DateTime now;
  final DecisionShift shift;
  DecisionGroup({required this.row, required this.workers,
    required this.attendance, required this.historyAttendance,
    required this.trips, required this.historyTrips, required this.containers,
    required this.now, required this.shift});
  String get id => '${row['id']}';
  String get name => '${row['name'] ?? row['groupName'] ?? row['number'] ?? id}';
  String get owner => '${row['municipalityCoordinatorId'] ?? ''}';
  int get present => attendance.where((a) => a['status'] == 'present').length;
  int get absent => attendance.where((a) => const [
    'absent', 'excused_absence', 'unexcused_absence', 'sick',
  ].contains(a['status'])).length;
  int get unknown => math.max(0, workers.length - attendance.length);
  double? get attendanceRate => workers.isEmpty ? null : present / workers.length;
  double? get absenceRate => workers.isEmpty ? null : absent / workers.length;
  double? get historicalAttendance => historyAttendance.isEmpty ? null :
      historyAttendance.where((a) => a['status'] == 'present').length /
      historyAttendance.length;
  int get full => containers.where((c) => c['status'] == 'full').length;
  int get empty => containers.where((c) => c['status'] == 'empty').length;
  double? get fullRate => containers.isEmpty ? null : full / containers.length;
  double? get emptyRate => containers.isEmpty ? null : empty / containers.length;
  List<DecisionRow> get completedTrips => trips.where(
      (t) => const ['completed', 'delivered'].contains(t['status'])).toList();
  static double? tonsOf(DecisionRow t) {
    final explicit = decisionNumber(t['weightTons'] ?? t['tons']);
    if (explicit != null) return explicit >= 0 ? explicit : null;
    final q = decisionNumber(t['estimatedQuantity'] ?? t['quantity']);
    if (q == null || q < 0) return null;
    final unit = '${t['quantityUnit'] ?? t['unit'] ?? ''}'.toLowerCase();
    if (const ['ton', 'tons', 'طن'].contains(unit)) return q;
    if (const ['kg', 'kilogram', 'كغ'].contains(unit)) return q / 1000;
    return null; // Missing units and cubic volume cannot be treated as tons.
  }
  double? get tons {
    final known = completedTrips.map(tonsOf).whereType<double>().toList();
    return known.isEmpty ? null : known.fold<double>(0, (a, b) => a + b);
  }
  bool get estimatedTons => completedTrips.any((t) =>
      t['weightTons'] == null && t['tons'] == null && tonsOf(t) != null);
  double? get targetTons => decisionNumber(row['targetTons'] ?? row['dailyTargetTons']);
  double? get targetTrips => decisionNumber(row['targetTrips'] ?? row['dailyTargetTrips']);
  double? get ppeRate {
    final checks = trips.map((t) => t['tripPpe'] ?? t['ppe'])
        .whereType<Map>().where((m) => m.isNotEmpty).toList();
    if (checks.isEmpty) return null;
    final total = checks.fold<int>(0, (n, m) => n + m.length);
    final compliant = checks.fold<int>(0,
        (n, m) => n + m.values.where((v) => v == true).length);
    return compliant / total;
  }
  double? get sicknessRate => attendance.isEmpty ? null :
      attendance.where((a) => a['status'] == 'sick' ||
          a['absenceReason'] == 'sick' || a['leaveType'] == 'sick').length /
      attendance.length;
  bool get stagnant => shift.activeAt(now) &&
      now.difference(shift.start).inMinutes >= 60 && trips.isEmpty;
  bool get bottleneck {
    final timed = historyTrips.where((t) {
      final start = decisionDate(t['startedAt']), end = decisionDate(t['completedAt']);
      final target = decisionNumber(t['targetDurationMinutes']);
      return start != null && end != null && end.isAfter(start) &&
          target != null && target > 0;
    }).toList();
    final delayed = timed.where((t) =>
        decisionDate(t['completedAt'])!.difference(
            decisionDate(t['startedAt'])!).inMinutes >
        decisionNumber(t['targetDurationMinutes'])! * 1.25).length;
    final distances = historyTrips.map((t) =>
        decisionNumber(t['distanceKm'])).whereType<double>().toList();
    return (timed.length >= 3 && delayed / timed.length > .3) ||
        (distances.length >= 3 &&
            distances.reduce((a, b) => a + b) / distances.length > 15);
  }
  int get cartWorkers => workers.where((w) =>
      '${w['job'] ?? w['type'] ?? ''}'.contains('كارة') ||
      '${w['job'] ?? w['type'] ?? ''}'.toLowerCase().contains('cart')).length;
  double? get historicalFullRate {
    final statuses = <String>[];
    for (final c in containers) {
      final events = c['statusHistory'];
      if (events is List) {
        for (final event in events.whereType<Map>()) {
          if (event['status'] is String) statuses.add(event['status'] as String);
        }
      }
    }
    return statuses.length < 5 ? null :
        statuses.where((s) => s == 'full').length / statuses.length;
  }
  bool get earlyCompletion {
    final days = <String>{};
    for (final t in historyTrips) {
      final completed = decisionDate(t['completedAt']);
      if (completed != null) days.add(completed.toIso8601String().substring(0, 10));
    }
    // An early last trip alone is not evidence of finishing the whole shift.
    final done = decisionDate(row['shiftCompletedAt']);
    return done != null && shift.contains(done) &&
        shift.end.difference(done).inMinutes >= 60 && days.length >= 3;
  }
}

class DecisionRecommendation {
  final String kind, title, reason;
  final DecisionGroup group;
  final int delta;
  final double confidence;
  const DecisionRecommendation({required this.kind, required this.title,
    required this.reason, required this.group, required this.delta,
    required this.confidence});
  String get key => '${group.id}_$kind';
  DecisionRow toMap() => {'kind': kind, 'groupId': group.id,
    'groupName': group.name, 'municipalityCoordinatorId': group.owner,
    'title': title, 'reason': reason, 'delta': delta,
    'confidence': confidence, 'workers': group.workers.length,
    'cartWorkers': group.cartWorkers};
}

class DecisionAnalytics {
  final List<DecisionGroup> groups;
  final List<DecisionRow> containers, dumpsites;
  final DateTime now, historyStart;
  final DecisionShift shift;
  final String cycleId, cycleName;
  DecisionAnalytics._(this.groups, this.containers, this.dumpsites, this.now,
      this.historyStart, this.shift, this.cycleId, this.cycleName);

  static List<DecisionRow> latestAttendance(Iterable<DecisionRow> rows) {
    final result = <String, DecisionRow>{};
    for (final r in rows) {
      final worker = '${r['workerId'] ?? r['userId'] ?? ''}';
      final time = decisionDate(r['createdAt'] ?? r['date']);
      if (worker.isEmpty || time == null) continue;
      final key = '${r['groupId']}_${time.toIso8601String().substring(0, 10)}_${r['shift'] ?? ''}_$worker';
      final old = result[key];
      final updated = decisionDate(r['updatedAt']) ?? time;
      if (old == null || !updated.isBefore(
          decisionDate(old['updatedAt'] ?? old['createdAt']) ?? time)) result[key] = r;
    }
    return result.values.toList();
  }

  factory DecisionAnalytics.calculate({required List<DecisionRow> operations,
    required List<DecisionRow> users, required List<DecisionRow> containers,
    required List<DecisionRow> dumpsites, required List<DecisionRow> trips,
    required List<DecisionRow> cycles, required DateTime now, required String shiftText}) {
    final shift = DecisionShift.parse(now, shiftText);
    final activeCycles = cycles.where((c) {
      final start = decisionDate(c['startDate']), end = decisionDate(c['endDate']);
      return c['status'] == 'active' && start != null && end != null &&
          !now.isBefore(start) && now.isBefore(end);
    }).toList()..sort((a, b) => decisionDate(b['startDate'])!.compareTo(
        decisionDate(a['startDate'])!));
    final cycle = activeCycles.isEmpty ? <String, dynamic>{} : activeCycles.first;
    final start = decisionDate(cycle['startDate']) ?? now.subtract(const Duration(days: 30));
    final ops = operations.where(decisionActive).toList();
    final groupRows = ops.where((r) => r['_entity'] == 'group').toList();
    final allWorkers = <String, DecisionRow>{};
    for (final w in [...users.where((u) => u['role'] == 'worker'),
      ...ops.where((r) => r['_entity'] == 'worker')]) {
      if (decisionActive(w)) allWorkers['${w['workerId'] ?? w['id']}'] = w;
    }
    final allTrips = <String, DecisionRow>{};
    for (final t in [...ops.where((r) => r['_entity'] == 'trip'), ...trips]) {
      if (decisionActive(t)) allTrips['${t['id']}'] = t;
    }
    final attendance = latestAttendance(ops.where((r) => r['_entity'] == 'attendance'));
    final activeContainers = containers.where(decisionActive).toList();
    final groups = <DecisionGroup>[];
    for (final g in groupRows) {
      final aliases = ['id', 'number', 'groupId', 'name', 'groupName']
          .map((k) => '${g[k] ?? ''}').where((s) => s.isNotEmpty).toSet();
      bool belongs(DecisionRow r) {
        final owner = '${r['municipalityCoordinatorId'] ?? r['municipalityId'] ?? ''}';
        if (owner.isNotEmpty && owner != '${g['municipalityCoordinatorId'] ?? ''}') return false;
        final linked = '${r['groupId'] ?? r['groupNumber'] ?? r['group'] ?? ''}';
        if (groupRows.any((other) => other['id'] == linked)) return linked == g['id'];
        return aliases.contains(linked);
      }
      bool historical(DecisionRow r) {
        final time = decisionDate(r['startedAt'] ?? r['createdAt'] ?? r['date']);
        return time != null && !time.isBefore(start) && !time.isAfter(now);
      }
      final workers = allWorkers.values.where(belongs).toList();
      final ids = workers.map((w) => '${w['workerId'] ?? w['id']}').toSet();
      final today = attendance.where((a) {
        final time = decisionDate(a['createdAt'] ?? a['date']);
        return belongs(a) && ids.contains('${a['workerId'] ?? a['userId']}') &&
            time != null && shift.contains(time) && !time.isAfter(now) &&
            (a['shift'] == null || a['shift'] == shiftText);
      }).toList();
      final historicalContainers = activeContainers.where(belongs).map((c) {
        final events = c['statusHistory'];
        return <String, dynamic>{...c, if (events is List)
          'statusHistory': events.whereType<Map>().where((e) {
            final time = decisionDate(e['at']);
            return time != null && !time.isBefore(start) && !time.isAfter(now);
          }).toList()};
      }).toList();
      groups.add(DecisionGroup(row: g, workers: workers, attendance: today,
        historyAttendance: attendance.where((a) => belongs(a) && historical(a)).toList(),
        trips: allTrips.values.where((t) {
          final time = decisionDate(t['startedAt'] ?? t['createdAt']);
          return belongs(t) && time != null && shift.contains(time) && !time.isAfter(now);
        }).toList(),
        historyTrips: allTrips.values.where((t) => belongs(t) && historical(t)).toList(),
        containers: historicalContainers, now: now, shift: shift));
    }
    groups.sort((a, b) => a.name.compareTo(b.name));
    return DecisionAnalytics._(groups, activeContainers,
      dumpsites.where(decisionActive).toList(), now, start, shift,
      '${cycle['id'] ?? ''}', '${cycle['name'] ?? cycle['title'] ?? 'آخر 30 يومًا'}');
  }

  int get workers => groups.fold<int>(0, (n, g) => n + g.workers.length);
  int get present => groups.fold<int>(0, (n, g) => n + g.present);
  int get absent => groups.fold<int>(0, (n, g) => n + g.absent);
  int get unknown => groups.fold<int>(0, (n, g) => n + g.unknown);
  double? get attendanceRate => workers == 0 ? null : present / workers;
  double? get emptyRate => containers.isEmpty ? null :
      containers.where((c) => c['status'] == 'empty').length / containers.length;
  double? get dumpsiteRate {
    var capacity = 0.0, used = 0.0;
    for (final d in dumpsites) {
      final c = decisionNumber(d['capacity']), fill = decisionNumber(d['fillPercentage']);
      if (c == null || c <= 0 || fill == null) continue;
      capacity += c;
      used += c * fill.clamp(0, 100) / 100;
    }
    return capacity == 0 ? null : used / capacity;
  }
  List<DecisionRow> get fullContainers => containers.where((c) => c['status'] == 'full').toList();
  List<DecisionRow> get healthHazards => fullContainers.where((c) {
    final fullSince = decisionDate(c['fullSince']);
    return fullSince != null && now.difference(fullSince).inMinutes > 720;
  }).toList();
  List<DecisionRecommendation> get recommendations {
    final result = <DecisionRecommendation>[];
    for (final g in groups) {
      final a = g.historicalAttendance, f = g.historicalFullRate;
      final days = g.historyAttendance.map((r) =>
          decisionDate(r['createdAt'])?.toIso8601String().substring(0, 10)).toSet();
      if (a == null || days.length < 3 || g.workers.isEmpty) continue;
      if (a > .85 && f != null && f > .4) {
        final increase = math.max(1, (g.workers.length * .2).ceil());
        result.add(DecisionRecommendation(kind: 'expand_manpower',
          title: 'زيادة عمال الجمع +$increase',
          reason: 'حضور تاريخي ${(a * 100).toStringAsFixed(1)}%، '
              'تكرار امتلاء ${(f * 100).toStringAsFixed(1)}% من رصد الحالات.',
          group: g, delta: increase, confidence: 1));
      } else if (a > .7 && g.bottleneck) {
        result.add(DecisionRecommendation(kind: 'increase_carts',
          title: 'دعم الكارات من ${g.cartWorkers} إلى ${g.cartWorkers + 2}',
          reason: 'اختناق موثق في مدة النقل أو المسافة في ثلاث نقلات على الأقل.',
          group: g, delta: 2, confidence: 1));
      } else if (g.workers.length >= 5 && g.emptyRate != null &&
          g.emptyRate! > .8 && g.earlyCompletion &&
          g.targetTons != null && g.targetTons! > 0 &&
          g.tons != null && g.tons! < g.targetTons! * .5) {
        result.add(DecisionRecommendation(kind: 'reallocate_surplus',
          title: 'تدوير فائض عاملين إلى منطقة احتياج',
          reason: 'حاويات فارغة >80%، كمية أقل من نصف الهدف وإنهاء مبكر موثق.',
          group: g, delta: -2, confidence: 1));
      }
    }
    return result;
  }
}
