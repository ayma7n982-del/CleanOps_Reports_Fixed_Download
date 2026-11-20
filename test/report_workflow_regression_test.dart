import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:solid_waste_operations/core/models/core_models.dart';
import 'package:solid_waste_operations/core/services/config_service.dart';
import 'package:solid_waste_operations/core/services/data_service.dart';
import 'package:solid_waste_operations/core/services/local_store.dart';
import 'package:solid_waste_operations/core/services/monthly_attendance_rows.dart';
import 'package:solid_waste_operations/core/services/report_content.dart';
import 'package:solid_waste_operations/core/services/report_service.dart';
import 'package:solid_waste_operations/presentation/screens/report_approval_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LocalStore store;
  const manager = AppUser(
      id: 'manager',
      username: 'manager',
      name: 'Manager',
      role: 'donor_manager',
      scope: 'all',
      policies: {});
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('report-regression-');
    Hive.init(directory.path);
    store = LocalStore(await Hive.openBox('reports'));
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
      'calendar uses person IDs, keeps same-name workers separate and uses work day',
      () {
    final matrix = MonthlyAttendanceRows([
      for (final id in ['a', 'b']) {'id': id, 'name': 'محمد', 'role': 'worker'}
    ], [
      for (final id in ['a', 'b'])
        {
          'workerId': id,
          'workDate': '2026-11-01',
          'createdAt': '2026-11-02',
          'status': id == 'a' ? 'present' : 'absent'
        },
      {
        'id': 'old',
        'workerName': 'محمد',
        'workDate': '2026-11-01',
        'status': 'present'
      },
    ]);
    expect(matrix.labels.values.toSet(), hasLength(3));
    expect(matrix.statuses['worker:a|1'], 'present');
    expect(matrix.statuses['worker:b|1'], 'absent');
    expect(matrix.statuses['worker:a|2'], isNull);
    expect(matrix.statuses['record:old|1'], 'present');
  });

  test('exports read the reviewed copy after the operational source changes',
      () async {
    final data = DataService(store, ConfigService(store));
    data.operations = [
      for (final status in [
        'completed',
        'in_progress',
        'cancelled',
        'delivered'
      ])
        {
          'id': status,
          '_entity': 'trip',
          'status': status,
          'createdAt': '2026-11-01'
        }
    ];
    final service = ReportService(data);
    Future<ReportSnapshot> load() => service.load(
        user: manager,
        reportType: 'trips',
        reportId: 'scope',
        startDate: DateTime(2026, 11, 1),
        endDate: DateTime(2026, 11, 1));
    final first = await load();
    final id = ReportArchive.documentId(first, 'town');
    expect(first.completedTrips, 2);
    final row = {
      'id': id,
      'reportKind': 'report_approval',
      'status': 'approved',
      ...ReportArchive.submission(first)
    };
    data.operations.add({
      'id': 'unrelated',
      '_entity': 'trip',
      'status': 'completed',
      'createdAt': '2026-11-12'
    });
    expect(ReportArchive.documentId(await load(), 'town'), id);
    data.operations.removeWhere((r) => r['id'] == 'completed');
    final live = await load();
    expect(live.trips, 3);
    final archived = ReportArchive.read(row);
    expect(archived.trips, 4);
    expect(archived.completedTrips, 2);
    expect(archived.tripRecords, hasLength(4));
    expect(archived.generatedAt, first.generatedAt);
    expect(
        utf8.decode(
            service.buildOperationalCsvBytes(archived, languageCode: 'en')),
        contains('"Registered trips","4"'));
    final legacy = ReportArchive.read({
      'id': 'legacy',
      'createdAt': '2026-10-01',
      'snapshot': {'trips': 6}
    });
    expect(ReportContent.metrics(legacy).map((m) => m.value), ['6']);
    expect(ReportContent.ratios(legacy), isEmpty);
  });

  for (final rejected in [false, true]) {
    test('queued review stays unconfirmed across restart, rejection=$rejected',
        () async {
      final data = DataService(store, ConfigService(store),
          syncItemOverride: (item, payload) async {
        if (rejected)
          throw FirebaseFunctionsException(
              code: 'failed-precondition', message: 'Outdated revision');
      });
      final row = {
        'id': 'r',
        '_entity': 'report',
        'reportKind': 'report_approval',
        'status': 'submitted'
      };
      data.operations = [row];
      await data.enqueue('report_approval', 'update',
          {'id': 'r', 'status': 'approved', '_expectedRevision': 1});
      expect(data.operations.single['status'], 'submitted');
      data.queue = store.queue();
      expect(data.pendingReport('r'), isNotNull);
      expect(
          ReportApprovalScreen.canExport(
              {...row, 'status': 'approved'}, manager, data),
          isFalse);
      data.online = true;
      await data.sync();
      expect(data.operations.firstWhere((e) => e['id'] == 'r')['status'],
          rejected ? 'submitted' : 'approved');
      if (rejected) {
        expect(store.queue().single.reportError, contains('Outdated'));
      } else {
        expect(data.pendingReport('r'), isNull);
        expect(
            ReportApprovalScreen.canExport(
                data.operations.firstWhere((e) => e['id'] == 'r'),
                manager,
                data),
            isTrue);
      }
    });
  }
}
