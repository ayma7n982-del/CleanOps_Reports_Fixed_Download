import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/presentation/widgets/eco_boot_splash.dart';

void main() {
  Future<void> pumpBoot(
    WidgetTester tester, {
    required Size size,
    required double progress,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: EcoBootSplash(progress: progress),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('branded launch stays readable on a small Samsung phone',
      (tester) async {
    await pumpBoot(
      tester,
      size: const Size(320, 640),
      progress: .6,
    );
    expect(find.text('CleanOps'), findsOneWidget);
    expect(find.text('منظومة ذكية لإدارة عمليات النظافة'), findsOneWidget);
    expect(find.text('تهيئة مساحة العمل...'), findsOneWidget);
    expect(find.text('التشغيل'), findsOneWidget);
    expect(find.text('التحليلات'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('branded launch adapts on larger phones without overflow',
      (tester) async {
    await pumpBoot(
      tester,
      size: const Size(430, 900),
      progress: 1,
    );
    expect(find.byType(EcoBootSplash), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('boot screen renders before any login providers exist',
      (tester) async {
    await pumpBoot(
      tester,
      size: const Size(360, 700),
      progress: 0,
    );
    expect(find.text('CleanOps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Android 12+ must have its own branded splash window', () {
    final file = File('android/app/src/main/res/values-v31/styles.xml');
    expect(file.existsSync(), isTrue);
    final xml = file.readAsStringSync();
    expect(xml, contains('android:windowSplashScreenBackground'));
    expect(xml, contains('android:windowSplashScreenAnimatedIcon'));
    expect(xml, contains('@drawable/cleanops_splash_clear'));
    expect(xml, isNot(contains('@drawable/cleanops_splash_logo')));
    expect(File('android/app/src/main/res/drawable/cleanops_splash_clear.xml').existsSync(), isTrue);
    expect(xml, contains('android:windowSplashScreenBackground">#E8F7EF'));
  });

  test('older Android launch and Flutter share the same light palette', () {
    final xml = File('android/app/src/main/res/drawable/launch_background.xml')
        .readAsStringSync();
    expect(xml, contains('#F8FCFA'));
    expect(xml, contains('#D9F0E6'));
    expect(xml, isNot(contains('cleanops_splash_logo')));
    expect(File('assets/brand/cleanops_logo_new.png').existsSync(), isTrue);
    expect(File('lib/presentation/widgets/eco_boot_splash.dart').readAsStringSync(),
        contains('assets/brand/cleanops_logo_new.png'));
  });
}
