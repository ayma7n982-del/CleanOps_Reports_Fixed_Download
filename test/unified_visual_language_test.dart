import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/presentation/widgets/assistant_shortcut_grid.dart';
import 'package:solid_waste_operations/presentation/widgets/creative_shortcuts.dart';
import 'package:solid_waste_operations/presentation/widgets/eco_shortcuts.dart';

void main() {
  testWidgets('every role uses one compact card geometry in RTL',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 840));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var leadershipTap = 0;
    var assistantTap = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  CreativeShortcutGrid(items: [
                    CreativeShortcut(
                      title: 'المجموعات والعمال',
                      subtitle: 'الفرق والمشرفون والحالة',
                      feature: 'workers',
                      onTap: () => leadershipTap++,
                    ),
                    CreativeShortcut(
                      title: 'سجل الترحيلات',
                      subtitle: 'النقل والفعالية',
                      feature: 'trips',
                      onTap: () {},
                    ),
                  ]),
                  AssistantShortcutGrid(
                    title: 'اسأل المساعد',
                    subtitle: 'نتائج التشغيل',
                    sectionIcon: Icons.auto_awesome_rounded,
                    actions: [
                      AssistantShortcutAction(
                        title: 'تحليل المخاطر',
                        description: 'حالات تحتاج المتابعة',
                        icon: Icons.warning_amber_rounded,
                        onTap: () => assistantTap++,
                      ),
                      AssistantShortcutAction(
                        title: 'حالة المكبات',
                        description: 'السعة والامتلاء',
                        icon: Icons.delete_sweep_rounded,
                        onTap: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final tiles = find.byType(EcoShortcutCard);
    expect(tiles, findsNWidgets(4));
    final h1 = tester.getSize(tiles.at(0)).height;
    final h2 = tester.getSize(tiles.at(2)).height;
    expect(h1, closeTo(h2, 1));
    expect(h1, lessThan(140));
    await tester.tap(find.text('المجموعات والعمال'));
    await tester.pump();
    await tester.tap(find.text('تحليل المخاطر'));
    await tester.pump();
    expect(leadershipTap, 1);
    expect(assistantTap, 1);
  });

  testWidgets('long Arabic labels and larger text fit 320px without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.5),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: EcoShortcutGrid(
              cards: [
                EcoShortcutCard(
                  title: 'المجموعات والعمال والمشرفون',
                  subtitle: 'مؤشرات ومتابعة التشغيل',
                  feature: 'workers',
                  icon: Icons.groups_rounded,
                  onTap: () {},
                ),
                EcoShortcutCard(
                  title: 'التنبيهات والبلاغات',
                  subtitle: 'الطوارئ والتنبيهات الحرجة',
                  feature: 'emergency',
                  icon: Icons.warning_amber_rounded,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(EcoShortcutCard), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a selected report card remains tappable and visibly selected',
      (tester) async {
    var selected = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 160,
            height: 125,
            child: EcoShortcutCard(
              title: 'كل التقارير',
              subtitle: 'مؤشرات وملخصات',
              feature: 'reports',
              icon: Icons.dashboard_customize_rounded,
              selected: true,
              onTap: () => selected = true,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('كل التقارير'));
    await tester.pump();
    expect(selected, isTrue);
  });
}
