import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:solid_waste_operations/core/localization.dart';
import 'package:solid_waste_operations/main.dart' show CardSection;
import 'package:solid_waste_operations/presentation/widgets/app_design.dart';

void main() {
  Future<void> pumpNarrowSection(WidgetTester tester, double width) async {
    await tester.binding.setSurfaceSize(Size(width, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<LocaleController>(
        create: (_) => LocaleController(),
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: CardSection(
                    title: 'التحكم الديناميكي Zero-Hardcoding',
                    icon: const AiFeatureIcon('settings', size: 20),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('التسجيل الصوتي'),
                          value: true,
                          onChanged: (_) {},
                        ),
                        ListTile(
                          title: const Text('تجميد المرحلة'),
                          subtitle: const Text(
                            'المرحلة مجمدة — التعديلات التشغيلية مقفلة'),
                          trailing: FilledButton.tonalIcon(
                            onPressed: null,
                            icon: const Icon(Icons.lock_outline),
                            label: const Text('تجميد'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('CardSection long mixed-language title never overflows 320px',
      (tester) async {
    await pumpNarrowSection(tester, 320);
    expect(find.text('التحكم الديناميكي Zero-Hardcoding'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CardSection long mixed-language title never overflows 360px',
      (tester) async {
    await pumpNarrowSection(tester, 360);
    expect(tester.takeException(), isNull);
  });

  test('direct and SMS recipient pickers show names and localized roles', () {
    final source = File('lib/presentation/screens/messages_center.dart')
        .readAsStringSync();
    expect(source, contains('Future<String?> _chooseDirectRecipient('));
    expect(source, contains('roleNames[role] ?? role'));
    expect(source, contains('ابحث بالاسم أو الدور'));
    expect(source, contains('لا يوجد مستلم مطابق'));
    expect(source, contains("entry.\u00241 == selectedRecipient"));
    expect(source, contains("setSheetState(() => recipientId = id)"));
    expect(source, contains("setSheetState(() => selectedRecipient = id)"));
  });

  test('settings retains actual controls and responsive title', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains("title:'التحكم الديناميكي'"));
    expect(source, contains("config.freezeStage()"));
    expect(source, contains("setOperationalFeature(key,v)"));
    expect(source, contains("maxLines: 2,"));
    expect(source, contains("Expanded("));
  });

  test('obsolete brand shield is not used by any Flutter header', () {
    for (final file in [
      'lib/main.dart',
      'lib/presentation/widgets/eco_boot_splash.dart',
      'lib/presentation/widgets/app_design.dart',
      'lib/presentation/screens/ai_command_center.dart',
      'lib/presentation/screens/enterprise_login.dart',
    ]) {
      final code = File(file).readAsStringSync();
      expect(code, isNot(contains("Image.asset('assets/app_icon.png'")),
          reason: file);
      expect(code, isNot(contains("'assets/brand/cleanops_icon_new.png'")),
          reason: file);
      expect(code, contains("'assets/brand/cleanops_logo_new.png'"),
          reason: file);
    }
  });
}
