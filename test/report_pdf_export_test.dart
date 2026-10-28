import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solid_waste_operations/core/models/core_models.dart';
import 'package:solid_waste_operations/core/services/config_service.dart';
import 'package:solid_waste_operations/core/services/data_service.dart';
import 'package:solid_waste_operations/core/services/local_store.dart';
import 'package:solid_waste_operations/core/services/report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('operational PDF export builds a real PDF document from a fixed snapshot',
      () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('cleanops_pdf_');
    Hive.init(directory.path);
    final box = await Hive.openBox('pdf_test');
    final store = LocalStore(box);
    final data = DataService(store, ConfigService(store));
    final reports = ReportService(data);
    final user = AppUser(
      id: 'manager-test',
      username: 'manager-test',
      name: 'Manager Test',
      role: 'donor_manager',
      scope: 'all',
      policies: const {},
    );
    final snapshot = ReportSnapshot(
      trips: 12,
      alternativeTrips: 2,
      attendance: 18,
      absence: 2,
      ppeCompliant: 17,
      emergencies: 2,
      emergencyOpen: 1,
      emergencySecured: 1,
      landfillCapacity: 62.5,
      heavyMachineryHours: 4.5,
      tripsByGroup: const {'Group A': 7, 'Group B': 5},
      tripsByDay: const {'10/27': 5, '10/28': 7},
      attendanceByGroup: const {'Group A': 10, 'Group B': 8},
      ppeByGroup: const {'Group A': 10, 'Group B': 7},
      emergenciesByGroup: const {'Group A': 1, 'Group B': 1},
      containerByStatus: const {'full': 3, 'partial': 5, 'empty': 7},
      containersTotal: 15,
      containersFull: 3,
      containersPartial: 5,
      containersEmpty: 7,
      containerIssues: 1,
      workers: 18,
      supervisors: 2,
      groups: 2,
      municipalities: 1,
      dumpsites: 1,
      cycleCount: 1,
      municipalityNames: const ['Smoke Municipality'],
      tripsByMunicipality: const {'Smoke Municipality': 12},
      attendanceByMunicipality: const {'Smoke Municipality': 18},
      absenceByGroup: const {'Group A': 1, 'Group B': 1},
      containersByMunicipality: const {'Smoke Municipality': 15},
      containersByGroup: const {'Group A': 8, 'Group B': 7},
      cycles: const ['Cycle 1'],
      selectedMunicipality: 'Smoke Municipality',
      selectedGroup: null,
      selectedCycle: 'Cycle 1',
      reportType: 'executive',
      reportId: 'PDF-SMOKE-1',
      periodLabel: '2026-10-01 → 2026-10-28',
      generatedAt: DateTime.utc(2026, 10, 28, 9, 30),
    );

    try {
      final bytes = await reports.buildOperationalPdfBytes(
        snapshot: snapshot,
        user: user,
        title: 'تقرير CleanOps التشغيلي',
      );

      expect(bytes.length, greaterThan(1000));
      expect(bytes.take(5).toList(), <int>[37, 80, 68, 70, 45]);
    } finally {
      data.dispose();
      await box.close();
      await directory.delete(recursive: true);
    }
  });
}
