import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/report_ratios.dart';
import 'package:solid_waste_operations/presentation/widgets/report_ratio_panel.dart';

void main() {
  testWidgets('ratio explanations and signed values fit narrow and wide layouts in both directions', (tester) async {
    for (final width in [320.0, 1024.0]) {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      for (final english in [false, true]) {
        await tester.pumpWidget(MaterialApp(home: Directionality(
          textDirection: english ? TextDirection.ltr : TextDirection.rtl,
          child: Scaffold(body: SingleChildScrollView(child: ReportRatioPanel(english: english, ratios: const [
            ReportRatio('growth', 'تغيّر النقلات عن الفترة السابقة', 'Trip growth vs previous period', -25, 'الحالي 3؛ السابق 4.', 'Current 3; previous 4.', signed: true),
            ReportRatio('points', 'تغيّر الحضور بالنقاط المئوية', 'Attendance percentage-point change', 10, 'فرق نسبتي الحضور.', 'Difference of attendance percentages.', signed: true, points: true),
            ReportRatio('target', 'الانحراف عن المستهدف', 'Variance against target', null, 'المستهدف غير مسجل.', 'Target not recorded.'),
          ]))),
        )));
        await tester.pumpAndSettle();
        expect(find.text('-25.0%'), findsOneWidget);
        expect(find.text('+10.0'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(english ? 'Trip growth vs previous period' : 'تغيّر النقلات عن الفترة السابقة'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
