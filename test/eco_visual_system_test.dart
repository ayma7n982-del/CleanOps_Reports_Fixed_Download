import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:solid_waste_operations/core/localization.dart';
import 'package:solid_waste_operations/presentation/widgets/app_design.dart';
import 'package:solid_waste_operations/presentation/widgets/creative_shortcuts.dart';

void main() {
  testWidgets('shared eco cards fit an Android width of 320 pixels',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 730));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var activated = '';
    await tester.pumpWidget(ChangeNotifierProvider<LocaleController>(
      create: (_) => LocaleController(),
      child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                const AiSectionCard(
                  title: 'مركز التقارير والتحليلات',
                  subtitle: 'مؤشرات تشغيلية من واقع الصلاحيات',
                  feature: 'reports',
                  child: Text('بيانات تجريبية للواجهة فقط'),
                ),
                const SizedBox(height: 14),
                CreativeShortcutGrid(
                  items: [
                    CreativeShortcut(
                      title: 'المجموعات والعمال',
                      subtitle: 'التوزيع وإدارة الأفراد',
                      feature: 'workers',
                      onTap: () => activated = 'workers',
                    ),
                    CreativeShortcut(
                      title: 'التقارير',
                      subtitle: 'تقارير تفصيلية',
                      feature: 'reports',
                      onTap: () => activated = 'reports',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('مركز التقارير والتحليلات'), findsOneWidget);
    expect(find.text('المجموعات والعمال'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('المجموعات والعمال'));
    await tester.pump();
    expect(activated, 'workers');
  });

  testWidgets('two illustrated shortcuts remain aligned on standard phones',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: CreativeShortcutGrid(
              items: [
                CreativeShortcut(
                  title: 'مكبات النفايات',
                  subtitle: 'تفاصيل مواقع الامتلاء',
                  feature: 'dumpsite',
                  onTap: () {},
                ),
                CreativeShortcut(
                  title: 'الترحيلات',
                  subtitle: 'عرض عمليات النقل',
                  feature: 'trips',
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('مكبات النفايات'), findsOneWidget);
    expect(find.text('الترحيلات'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final first = find.ancestor(
      of: find.text('مكبات النفايات'),
      matching: find.byType(InkWell),
    );
    final second = find.ancestor(
      of: find.text('الترحيلات'),
      matching: find.byType(InkWell),
    );
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect((tester.getTopLeft(first).dy - tester.getTopLeft(second).dy).abs(),
        lessThan(1));
    // Approved design: picture and caption are side by side on normal phones,
    // never a tall card with a large vertical empty gap.
    expect(tester.getSize(first).height, lessThanOrEqualTo(145));
    final icon = find.byType(EcoPictorialIcon).first;
    final iconCenter = tester.getCenter(icon);
    final titleCenter = tester.getCenter(find.text('مكبات النفايات'));
    expect((titleCenter.dx - iconCenter.dx).abs(), greaterThan(35));
    expect((titleCenter.dy - iconCenter.dy).abs(), lessThan(40));
  });

  testWidgets('eco pictorial icon does not require a repository image asset',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: EcoPictorialIcon(
            feature: 'emergency',
            icon: Icons.notification_important_rounded,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(EcoPictorialIcon), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
