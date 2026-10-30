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
    } finally {
      data.dispose();
      await box.close();
      await directory.delete(recursive: true);
    }
  });
}
