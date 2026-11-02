import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/presentation/widgets/eco_boot_splash.dart';

void main() {
  Future<void> pumpBoot(
    WidgetTester tester, {
    required Size size,
    required double progress,
    bool reduceMotion = false,
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              size: size,
              disableAnimations: reduceMotion,
              textScaler: TextScaler.linear(textScale),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: EcoBootSplash(progress: progress),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('branded launch stays readable on a small Samsung phone', (
    tester,
  ) async {
    await pumpBoot(tester, size: const Size(320, 640), progress: .6);
    expect(find.text('CleanOps'), findsOneWidget);
    expect(find.text('منظومة ذكية لإدارة عمليات النظافة'), findsOneWidget);
    expect(find.text('تهيئة مساحة العمل...'), findsOneWidget);
    expect(find.text('التشغيل'), findsOneWidget);
    expect(find.text('التحليلات'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('branded launch adapts on larger phones without overflow', (
    tester,
  ) async {
    await pumpBoot(tester, size: const Size(430, 900), progress: 1);
    expect(find.byType(EcoBootSplash), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('boot screen renders before any login providers exist', (
    tester,
  ) async {
    await pumpBoot(tester, size: const Size(360, 700), progress: 0);
    expect(find.text('CleanOps'), findsOneWidget);
    final brand = tester.widget<Image>(find.byType(Image).first);
    expect(
      (brand.image as AssetImage).assetName,
      'assets/brand/cleanops_icon_new.png',
    );
    final fade = tester.widgetList<Opacity>(find.byType(Opacity));
    expect(fade.every((widget) => widget.opacity > 0), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'logo lighting changes with launch progress and respects reduced motion',
    (tester) async {
      double glowBlur() =>
          (tester
                      .widget<Container>(
                        find.byKey(const ValueKey('boot-logo-glow')),
                      )
                      .decoration
                  as BoxDecoration)
              .boxShadow!
              .single
              .blurRadius;

      await pumpBoot(tester, size: const Size(360, 700), progress: 0);
      final initialBlur = glowBlur();
      await pumpBoot(tester, size: const Size(360, 700), progress: .25);
      expect(glowBlur(), greaterThan(initialBlur));

      await pumpBoot(
        tester,
        size: const Size(360, 700),
        progress: 0,
        reduceMotion: true,
      );
      final staticBlur = glowBlur();
      await pumpBoot(
        tester,
        size: const Size(360, 700),
        progress: .25,
        reduceMotion: true,
      );
      expect(glowBlur(), staticBlur);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'developer credit stays at the bottom with large text and landscape',
    (tester) async {
      for (final size in [const Size(320, 640), const Size(640, 320)]) {
        await pumpBoot(tester, size: size, progress: .6, textScale: 2);
        final credit = find.byKey(const ValueKey('boot-developer-credit'));
        final bounds = tester.getRect(credit);
        expect(bounds.bottom, lessThanOrEqualTo(size.height));
        expect(bounds.top, greaterThan(size.height * .75));
        expect(tester.widget<Text>(credit).style!.fontSize, 10);
        expect(find.text('Developed by @Eman Al-Qahwaji'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  test('Android 12+ must have its own branded splash window', () {
    final file = File('android/app/src/main/res/values-v31/styles.xml');
    expect(file.existsSync(), isTrue);
    final xml = file.readAsStringSync();
    expect(xml, contains('android:windowSplashScreenBackground'));
    expect(xml, contains('android:windowSplashScreenAnimatedIcon'));
    expect(xml, contains('@mipmap/ic_launcher'));
    expect(xml, isNot(contains('@drawable/cleanops_splash_logo')));
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec,
      contains('adaptive_icon_foreground: assets/brand/cleanops_icon_new.png'),
    );
    expect(xml, contains('android:windowSplashScreenBackground">#E8F7EF'));
  });

  test('older Android launch and Flutter share the same light palette', () {
    final xml = File('android/app/src/main/res/drawable/launch_background.xml')
        .readAsStringSync();
    expect(xml, contains('#F8FCFA'));
    expect(xml, contains('#D9F0E6'));
    expect(xml, isNot(contains('cleanops_splash_logo')));
    expect(xml, contains('@mipmap/ic_launcher'));
    expect(File('assets/brand/cleanops_icon_new.png').existsSync(), isTrue);
    expect(
      File('lib/presentation/widgets/eco_boot_splash.dart').readAsStringSync(),
      contains('assets/brand/cleanops_icon_new.png'),
    );
  });
}
