import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:solid_waste_operations/core/models/core_models.dart';
import 'package:solid_waste_operations/core/services/config_service.dart';
import 'package:solid_waste_operations/core/services/data_service.dart';
import 'package:solid_waste_operations/core/services/local_store.dart';
import 'package:solid_waste_operations/core/services/report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a 89-day cycle includes every dated trip, excluding out-of-range and undated records',
      () async {
    final directory = await Directory.systemTemp.createTemp('cleanops_long_period_');
    Hive.init(directory.path);
    final box = await Hive.openBox('long_period');
    final store = LocalStore(box);
    final data = DataService(store, ConfigService(store));
    final manager = AppUser(
      id: 'manager-long-report',
      username: 'manager-long-report',
      name: 'Manager',
      role: 'donor_manager',
      scope: 'all',
      policies: const {},
    );
    try {
      data.online = false;
      final start = DateTime(2026, 8, 1);
      final end = DateTime(2026, 10, 28);
      data.operations = [
        for (var i = 0; i < 155; i++)
          {
            'id': 'trip-$i',
            '_entity': 'trip',
            'groupId': 'g1',
            'municipalityName': 'Test Municipality',
            'createdAt': start.add(Duration(days: i % 89))
                .toIso8601String(),
          },
        {
          'id': 'outside',
          '_entity': 'trip',
          'groupId': 'g1',
          'createdAt': DateTime(2026, 7, 31).toIso8601String(),
        },
        {'id': 'missing-date', '_entity': 'trip', 'groupId': 'g1'},
      ];
      final snapshot = await ReportService(data).load(
        startDate: start,
        endDate: end,
        user: manager,
      );
      expect(ReportPeriodPresets.custom(start, end).inclusiveDays, 89);
      expect(snapshot.trips, 155);
      expect(snapshot.tripsByGroup['g1'], 155);
      expect(snapshot.periodLabel, contains('2026-08-01'));
      expect(snapshot.periodLabel, contains('2026-10-28'));
      expect(snapshot.sourceMayBeIncomplete, isFalse);
      // Cycle totals use source operations, not saved report snapshots as well.
      data.operations = [
        {'id': 'jan-2027', '_entity': 'trip', 'cycleId': 'c1', 'groupId': 'g1', 'createdAt': '2027-01-02'},
        {'id': 'jan-2026', '_entity': 'trip', 'cycleId': 'c1', 'groupId': 'g1', 'createdAt': '2026-01-02'},
        {'id': 'present', '_entity': 'attendance', 'cycleId': 'c1', 'groupId': 'g1', 'createdAt': '2026-01-02', 'status': 'present'},
        {'id': 'absent', '_entity': 'attendance', 'cycleId': 'c1', 'groupId': 'g1', 'createdAt': '2026-01-02', 'status': 'absent'},
        {'id': 'other-cycle', '_entity': 'trip', 'cycleId': 'c2', 'groupId': 'g1', 'createdAt': '2026-01-02'},
        {'id': 'saved-summary', '_entity': 'report', 'reportKind': 'work_report', 'cycleId': 'c1', 'cycleName': 'Cycle One', 'workDate': '2026-01-02', 'trips': 2, 'attendance': 1},
      ];
      final cycle = await ReportService(data).load(
        user: manager, reportType: 'cycles', cycle: 'c1',
        startDate: DateTime(2026, 1, 1), endDate: DateTime(2027, 1, 31),
      );
      expect(cycle.trips, 2);
      expect(cycle.attendance, 1);
      expect(cycle.absence, 1);
      expect(cycle.cycleCount, 1);
      expect(cycle.tripsByDay.keys.toList(), ['2026-01-02', '2027-01-02']);
      final byName = await ReportService(data).load(user: manager, reportType: 'cycles', cycle: 'Cycle One', startDate: DateTime(2026), endDate: DateTime(2027, 1, 31));
      expect(byName.trips, cycle.trips);
      data.online = true;
      data.operations = [
        for (var i = 0; i < 4; i++) {'id':'previous-$i', '_entity':'trip', 'groupId':'g1', 'createdAt':'2026-11-09', 'status':'completed'},
        {'id':'now-1', '_entity':'trip', 'groupId':'g1', 'createdAt':'2026-11-10', 'status':'completed'},
        {'id':'now-2', '_entity':'trip', 'groupId':'g1', 'createdAt':'2026-11-11', 'status':'completed'},
        {'id':'other-group', '_entity':'trip', 'groupId':'g2', 'createdAt':'2026-11-10', 'status':'completed'},
        {'id':'deleted', '_entity':'trip', 'groupId':'g1', 'createdAt':'2026-11-10', 'status':'completed', 'isDeleted':true},
      ];
      final compared = await ReportService(data).load(user: manager, group:'g1', reportType:'trips',
        startDate:DateTime(2026, 11, 10), endDate:DateTime(2026, 11, 11));
      expect(compared.trips, 2);
      expect(compared.ratioInsights.firstWhere((r) => r.id == 'growth').value, -50);
      expect(compared.ratioInsights.firstWhere((r) => r.id == 'completion').value, 100);
      final today = DateTime.now();
      data.operations = [
        {'id':'g1', '_entity':'group', 'dailyTargetTrips':2},
        {'id':'today-g1', '_entity':'trip', 'groupId':'g1', 'createdAt':today.toIso8601String(), 'status':'completed'},
      ];
      final withTarget = await ReportService(data).load(user:manager, reportType:'trips', startDate:today, endDate:today);
      expect(withTarget.ratioInsights.firstWhere((r) => r.id == 'achievement').value, 50);
      data.operations.add({'id':'uncovered-group', '_entity':'trip', 'groupId':'g2', 'createdAt':today.toIso8601String(), 'status':'completed'});
      final uncovered = await ReportService(data).load(user:manager, reportType:'trips', startDate:today, endDate:today);
      expect(uncovered.ratioInsights.firstWhere((r) => r.id == 'achievement').value, isNull);


      expect(cycle.tripsByMunicipality.values.fold<int>(0, (a, b) => a + b), 2);

    } finally {
      data.dispose();
      await box.close();
      await directory.delete(recursive: true);
    }
  });
}
