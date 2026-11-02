import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:solid_waste_operations/core/localization.dart';
import 'package:solid_waste_operations/core/services/work_report_summary.dart';
import 'package:solid_waste_operations/presentation/widgets/work_report_summary_card.dart';

void main() {
  Widget surface(WorkReportSummary s) => ChangeNotifierProvider(
    create: (_) => LocaleController(),
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: WorkReportSummaryCard(summary: s)),
      ),
    ),
  );
  testWidgets('mobile summary wraps and opens its source rows', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 11, 2);
    await tester.pumpWidget(
      surface(
        WorkReportSummary.build(
          groupId: 'g1',
          day: day,
          shift: 'morning',
          serverConfirmed: true,
          now: day,
          records: [
            {
              'id': 'attendance-1',
              '_entity': 'attendance',
              'groupId': 'g1',
              'workerId': 'w1',
              'workerName': 'محمد أحمد',
              'shift': 'morning',
              'status': 'present',
              'createdAt': day.toIso8601String(),
            },
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('الحضور: 1'));
    await tester.pumpAndSettle();
    expect(find.text('محمد أحمد'), findsOneWidget);
    expect(find.textContaining('attendance-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('empty offline sources show incomplete rather than fake zeros', (
    tester,
  ) async {
    await tester.pumpWidget(
      surface(
        WorkReportSummary.build(
          records: [],
          groupId: 'g1',
          day: DateTime(2026, 11, 2),
          shift: 'morning',
          serverConfirmed: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('الحضور: غير مكتمل'), findsOneWidget);
    expect(find.text('نقلات مكتملة: غير مكتمل'), findsOneWidget);
    expect(find.text('الحضور: 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
