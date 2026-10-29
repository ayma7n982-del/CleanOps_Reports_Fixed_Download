import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/presentation/widgets/assistant_shortcut_grid.dart';

void main() {
  testWidgets('assistant shortcuts stay readable and tappable on narrow phones',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var tapped = '';

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: AssistantShortcutGrid(
              title: 'انتقال سريع',
              subtitle: 'اختصارات حقيقية',
              sectionIcon: Icons.dashboard_rounded,
              actions: [
                AssistantShortcutAction(
                  icon: Icons.groups_rounded,
                  title: 'المجموعات والعمال',
                  onTap: () => tapped = 'workers',
                ),
                AssistantShortcutAction(
                  icon: Icons.picture_as_pdf_rounded,
                  title: 'تقرير PDF لفترة محددة',
                  onTap: () => tapped = 'pdf',
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('المجموعات والعمال'), findsOneWidget);
    expect(find.text('تقرير PDF لفترة محددة'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('المجموعات والعمال'));
    await tester.pump();
    expect(tapped, 'workers');
  });

  testWidgets('two columns remain balanced on standard phone widths',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: AssistantShortcutGrid(
              title: 'اسأل المساعد',
              subtitle: 'مؤشرات حقيقية',
              suggestions: true,
              sectionIcon: Icons.auto_awesome,
              actions: [
                for (final name in const [
                  'ملخص اليوم',
                  'تحليل المخاطر',
                  'التنبيهات',
                  'حالة المكبات',
                ])
                  AssistantShortcutAction(
                    title: name,
                    icon: Icons.analytics_outlined,
                    onTap: () {},
                  ),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('ملخص اليوم'), findsOneWidget);
    expect(find.text('تحليل المخاطر'), findsOneWidget);
    expect(find.text('التنبيهات'), findsOneWidget);
    expect(find.text('حالة المكبات'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Arabic labels may use one or two text lines, so compare the tile
    // surfaces rather than the text baselines.
    final firstTile = find.ancestor(
      of: find.text('ملخص اليوم'),
      matching: find.byType(InkWell),
    );
    final secondTile = find.ancestor(
      of: find.text('تحليل المخاطر'),
      matching: find.byType(InkWell),
    );
    expect(firstTile, findsOneWidget);
    expect(secondTile, findsOneWidget);
    final first = tester.getTopLeft(firstTile);
    final second = tester.getTopLeft(secondTile);
    expect((first.dy - second.dy).abs(), lessThan(1));
  });
}
