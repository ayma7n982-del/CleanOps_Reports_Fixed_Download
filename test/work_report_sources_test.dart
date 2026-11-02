import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:solid_waste_operations/core/services/config_service.dart';
import 'package:solid_waste_operations/core/services/data_service.dart';
import 'package:solid_waste_operations/core/services/local_store.dart';
import 'package:solid_waste_operations/core/services/work_report_sources.dart';
import 'package:solid_waste_operations/core/services/work_report_summary.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('pending durable corrections overlay once and stay provisional after restart', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cleanops_report_sources_',
    );
    Hive.init(directory.path);
    final box = await Hive.openBox('report_sources');
    final store = LocalStore(box);
    final data = DataService(store, ConfigService(store)),
        restarted = DataService(store, ConfigService(store));
    final day = DateTime(2026, 11, 2);
    final a = <String, dynamic>{
      'id': 'a1',
      '_entity': 'attendance',
      'groupId': 'g1',
      'workerId': 'w1',
      'shift': 'morning',
      'createdAt': day.toIso8601String(),
      'status': 'present',
    };
    final t = <String, dynamic>{
      'id': 't1',
      '_entity': 'trip',
      'groupId': 'g1',
      'shift': 'morning',
      'startedAt': day.toIso8601String(),
      'status': 'in_progress',
    };
    try {
      data.online = false;
      await data.enqueue('attendance', 'update', {...a, 'status': 'absent'});
      await data.enqueue('trip', 'update', {...t, 'status': 'completed'});
      restarted.queue = store.queue();
      final rows = WorkReportSources.overlay(restarted, [
        a,
        t,
        {...a, 'id': 'other', 'groupId': 'g2'},
      ], 'g1');
      final summary = WorkReportSummary.build(
        records: rows,
        groupId: 'g1',
        day: day,
        shift: 'morning',
        serverConfirmed: true,
        now: day,
      );
      expect(rows.length, 2);
      expect(summary.present, 0);
      expect(summary.absent, 1);
      expect(summary.completedTrips, 1);
      expect(summary.readyForSubmission, isFalse);
      restarted.queue = [];
      final confirmed = WorkReportSummary.build(
        records: WorkReportSources.overlay(restarted, [
          {...a, 'status': 'absent'},
          {...t, 'status': 'completed'},
        ], 'g1'),
        groupId: 'g1',
        day: day,
        shift: 'morning',
        serverConfirmed: true,
        now: day,
      );
      expect(confirmed.readyForSubmission, isTrue);
      expect(confirmed.counts, summary.counts);
    } finally {
      data.dispose();
      restarted.dispose();
      await box.close();
      await directory.delete(recursive: true);
    }
  });
}
