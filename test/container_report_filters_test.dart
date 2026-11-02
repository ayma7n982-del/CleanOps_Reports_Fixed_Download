import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:solid_waste_operations/core/models/core_models.dart';
import 'package:solid_waste_operations/core/services/config_service.dart';
import 'package:solid_waste_operations/core/services/container_service.dart';
import 'package:solid_waste_operations/core/services/data_service.dart';
import 'package:solid_waste_operations/core/services/local_store.dart';
import 'package:solid_waste_operations/core/services/messaging_service.dart';
import 'package:solid_waste_operations/core/services/report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box box;
  late LocalStore store;
  late DataService data;
  final supervisor = AppUser(
    id: 's1',
    username: 's1',
    name: 'Supervisor',
    role: 'group_supervisor',
    scope: 'assigned_only',
    groupId: 'g1',
    municipalityCoordinatorId: 'm1',
    policies: const {},
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('container_reports_');
    Hive.init(directory.path);
    box = await Hive.openBox('container_reports');
    store = LocalStore(box);
    data = DataService(store, ConfigService(store));
  });
  tearDown(() async {
    data.dispose();
    await box.close();
    await directory.delete(recursive: true);
  });

  test('creation persists explicitly chosen status; status update never creates a trip', () async {
    final messaging = MessagingService(store, ConfigService(store));
    final service = ContainerService(store, data, messaging);
    try {
      await service.attachUser(supervisor);
      await service.createContainer(
        locationName: 'Site A',
        latitude: 31,
        longitude: 34,
        municipalityId: 'm1',
        groupId: 'g1',
        status: 'partial',
      );
      expect(service.containers.single.status, 'partial');
      expect(jsonDecode(data.queue.single.payload)['status'], 'partial');
      await service.updateDailyStatus(service.containers.single, 'empty');
      expect(store.cachedContainers().single['status'], 'empty');
      expect(data.queue.every((q) => q.entity == 'container'), isTrue);
      await expectLater(
        service.createContainer(
          locationName: 'B',
          latitude: 31,
          longitude: 34,
          municipalityId: 'm1',
          groupId: 'g1',
          status: 'invalid',
        ),
        throwsArgumentError,
      );
    } finally {
      service.dispose();
      messaging.dispose();
    }
  });

  test('latest container snapshot ignores creation period but respects status, search and group scope', () async {
    await store.saveCachedContainers([
      {
        'id': 'c1',
        'locationName': 'Main street',
        'status': 'full',
        'municipalityId': 'm1',
        'groupId': 'g1',
        'createdAt': '2020-01-01',
        'updatedAt': '2026-10-01',
      },
      {
        'id': 'c2',
        'locationName': 'Main street',
        'status': 'empty',
        'municipalityId': 'm1',
        'groupId': 'g1',
      },
      {
        'id': 'c3',
        'locationName': 'Main street',
        'status': 'full',
        'municipalityId': 'm2',
        'groupId': 'g2',
      },
    ]);
    final report = ReportService(data);
    final snapshot = await report.load(
      user: supervisor,
      reportType: 'containers',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 1),
      search: 'MAIN',
      containerStatus: 'full',
      reportId: 'base',
    );
    expect(snapshot.containerRecords.map((r) => r['id']), ['c1']);
    expect(snapshot.containersTotal, 1);
    expect(snapshot.containersFull, 1);
    expect(snapshot.availableMunicipalities, ['m1']);
    final csv = utf8.decode(report.buildOperationalCsvBytes(snapshot));
    expect(csv, contains('MAIN'));
    expect(csv, contains('ممتلئة'));
    expect(snapshot.periodLabel, contains('آخر حالة'));
    final other = await report.load(
      user: supervisor,
      reportType: 'containers',
      containerStatus: 'empty',
      reportId: 'base',
    );
    expect(other.reportId, isNot(snapshot.reportId));
  });

  test(
    'trip filters use date, search, municipality and role scope together',
    () async {
      data.operations = [
        {
          'id': 't1',
          '_entity': 'trip',
          'location': 'Main',
          'groupId': 'g1',
          'municipalityId': 'm1',
          'createdAt': '2026-11-01T10:00:00',
        },
        {
          'id': 't2',
          '_entity': 'trip',
          'location': 'Main',
          'groupId': 'g1',
          'municipalityId': 'm1',
          'createdAt': '2026-10-31T10:00:00',
        },
        {
          'id': 't3',
          '_entity': 'trip',
          'location': 'Main',
          'groupId': 'g2',
          'municipalityId': 'm2',
          'createdAt': '2026-11-01T10:00:00',
        },
      ];
      final snapshot = await ReportService(data).load(
        user: supervisor,
        reportType: 'trips',
        startDate: DateTime(2026, 11, 1),
        endDate: DateTime(2026, 11, 1),
        search: 'main',
        municipality: 'm1',
      );
      expect(snapshot.trips, 1);
      expect(snapshot.tripRecords.single['id'], 't1');
    },
  );

  test('not updated today and month-to-date presets have clear boundaries', () {
    final now = DateTime(2026, 11, 2, 12);
    expect(
      ReportRecordFilters.matchesContainerStatus(
        {'updatedAt': '2026-11-02T00:00:00'},
        'stale',
        now,
      ),
      isFalse,
    );
    expect(
      ReportRecordFilters.matchesContainerStatus(
        {'updatedAt': '2026-11-01T23:59:59'},
        'stale',
        now,
      ),
      isTrue,
    );
    expect(
      ReportRecordFilters.matchesContainerStatus({}, 'stale', now),
      isTrue,
    );
    expect(ReportPeriodPresets.monthly(now).startDate, DateTime(2026, 11, 1));
    expect(ReportPeriodPresets.monthly(now).endDate, DateTime(2026, 11, 2));
  });
}
