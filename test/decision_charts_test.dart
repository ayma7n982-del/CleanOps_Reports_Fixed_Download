import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/decision_analytics.dart';
import 'package:solid_waste_operations/core/services/decision_pdf_export.dart';
import 'package:solid_waste_operations/presentation/widgets/decision_charts.dart';

DecisionAnalytics data() => DecisionAnalytics.calculate(
  operations: [
    {'id': 'g', '_entity': 'group', 'name': 'المجموعة الأولى', 'municipalityCoordinatorId': 'm'},
    {'id': 'w', '_entity': 'worker', 'groupId': 'g'},
    {'id': 'a', '_entity': 'attendance', 'groupId': 'g', 'workerId': 'w',
      'createdAt': '2026-10-29T08:30:00', 'status': 'present'},
    for (var day = 24; day <= 28; day++)
      {'id': 'a$day', '_entity': 'attendance', 'groupId': 'g', 'workerId': 'w',
        'createdAt': '2026-10-$day' 'T08:30:00', 'status': 'present'},
    {'id': 't', '_entity': 'trip', 'groupId': 'g', 'status': 'completed',
      'createdAt': '2026-10-29T09:00:00', 'estimatedQuantity': 2, 'quantityUnit': 'ton',
      'ppe': {'boots': true, 'gloves': false}},
  ],
  users: [], containers: [{'id': 'c', 'status': 'full', 'groupId': 'g',
    'fullSince': '2026-10-28T00:00:00',
    'statusHistory':[for(var day=24;day<=28;day++)
      {'status':'full','at':'2026-10-$day' 'T09:00:00'}]}],
  dumpsites: [{'id': 'd', 'nameAr': 'المكب المركزي', 'capacity': 100,
    'fillPercentage': 90}], trips: [], cycles: [],
  now: DateTime(2026, 10, 29, 10), shiftText: '08:00 - 16:00');

void main() {
  testWidgets('Arabic charts remain scrollable at phone width and large font',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(size: Size(320, 800), textScaler: TextScaler.linear(1.5)),
      child: Directionality(textDirection: TextDirection.rtl,
        child: Scaffold(body: SingleChildScrollView(child: Column(children: [
          DecisionExecutiveCharts(data: data()),
          const DecisionComparisonBar(actual: 2, target: 5,
            label: 'النقلات المنجزة', unit: 'نقلة'),
        ])))))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('every report section renders real chart images into a valid Arabic PDF',
      (tester) async {
    await tester.runAsync(() async {
      for (final section in ['all', 'operations', 'strategic', 'health']) {
        final bytes = await buildDecisionPdf(data: data(), decisions: [
          {'id': 'd', 'title': 'توجيه عاجل', 'body': 'تفريغ الحاوية الحرجة',
            'kind': 'collection', 'groupId': 'g', 'status': 'issued',
            'coordinatorName': 'منسق البلدية', 'createdAt': '2026-10-29T10:00:00'},
        ], coordinator: 'منسق البلدية', quality: 'اختبار', section: section);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length, greaterThan(10000));
        final output = Directory('build/decision-previews')..createSync(recursive: true);
        File('${output.path}/CleanOps_Decisions_$section.pdf').writeAsBytesSync(bytes);
      }
    });
  });
}
