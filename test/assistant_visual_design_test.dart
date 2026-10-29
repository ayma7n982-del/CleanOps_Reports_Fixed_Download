import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/presentation/widgets/assistant_hero_banner.dart';
import 'package:solid_waste_operations/presentation/widgets/assistant_shortcut_grid.dart';

void main() {
  testWidgets('original illustrated hero remains readable at narrow widths', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 670));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: EdgeInsets.all(12),
              child: AssistantHeroBanner(),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AssistantHeroBanner), findsOneWidget);
    expect(find.text('مساعدك الذكي لإدارة عمليات النظافة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('featured PDF action remains a real clickable shortcut', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AssistantFeaturedPdfShortcut(
            action: AssistantShortcutAction(
              title: 'تقرير PDF لفترة محددة',
              icon: Icons.picture_as_pdf_rounded,
              description: 'إنشاء تقرير مخصص',
              onTap: () => calls++,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('تقرير PDF لفترة محددة'), findsOneWidget);
    await tester.tap(find.text('تقرير PDF لفترة محددة'));
    await tester.pump();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('visual grid does not add shortcuts not supplied by role policy', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AssistantShortcutGrid(
          title: 'انتقال سريع',
          subtitle: 'حسب الصلاحيات',
          sectionIcon: Icons.grid_view_rounded,
          actions: [
            AssistantShortcutAction(
              title: 'الرسائل',
              icon: Icons.message_rounded,
              onTap: () {},
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('الرسائل'), findsOneWidget);
    expect(find.text('التقارير'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
