import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  test('all screens inherit a single green Material design system', () {
    final main = source('lib/main.dart');
    expect(main, contains('theme: ThemeData('));
    expect(main, contains('cardTheme: CardThemeData('));
    expect(main, contains('chipTheme: ChipThemeData('));
    expect(main, contains('inputDecorationTheme: InputDecorationTheme('));
    expect(main, contains('bottomSheetTheme: const BottomSheetThemeData('));
    expect(main, contains('appBarTheme: const AppBarTheme('));
    expect(main, contains('Color(0xFF087F6B)'));
    expect(main, contains('home: const SplashScreen()'));
  });

  test('every role shortcut uses the same actual EcoShortcutCard', () {
    const consumers = <String, String>{
      'lib/presentation/widgets/creative_shortcuts.dart':
          'EcoShortcutGrid(',
      'lib/presentation/widgets/workspace_overview.dart':
          'EcoShortcutGrid(',
      'lib/presentation/widgets/assistant_shortcut_grid.dart':
          'EcoShortcutGrid(',
      'lib/presentation/screens/ai_command_center.dart':
          'EcoShortcutCard(',
      'lib/presentation/screens/reports_center.dart':
          'EcoShortcutCard(',
      'lib/presentation/screens/level1_supervisor.dart':
          'EcoShortcutCard(',
    };
    for (final entry in consumers.entries) {
      expect(File(entry.key).existsSync(), isTrue, reason: entry.key);
      expect(source(entry.key), contains(entry.value), reason: entry.key);
    }
  });

  test('approved shortcuts retain click actions and original permission gates',
      () {
    final assistant = source('lib/presentation/screens/ai_bot_screen.dart');
    for (final key in [
      'messages', 'operations', 'trips', 'workers',
      'alerts', 'reports', 'dumpsites', 'live_map', 'report_pdf',
    ]) {
      expect(assistant, contains("shortcuts.contains('$key')"));
    }
    expect(assistant, contains('onTap: _exportPeriodPdf'));
    expect(assistant, contains("input.text = '"));

    final supervisor = source('lib/presentation/screens/level1_supervisor.dart');
    expect(supervisor, contains("user.can('emergency', 'create')"));
    expect(supervisor, contains("user.can('attendance','create')"));
    expect(supervisor, contains('onTap: () => _openAction('));

    final reports = source('lib/presentation/screens/reports_center.dart');
    expect(reports, contains("item.\$1 == 'absence'"));
    expect(reports, contains("item.\$1 == 'work'"));
  });

  test('native and Flutter splash use the same brand and keep auth routing',
      () {
    final main = source('lib/main.dart');
    expect(main, contains('EcoBootSplash(progress: controller.value)'));
    expect(main, contains('Future.delayed(const Duration(milliseconds: 2450)'));
    expect(main, contains('Navigator.pushReplacement('));

    final v31 = source('android/app/src/main/res/values-v31/styles.xml');
    expect(v31, contains('windowSplashScreenAnimatedIcon'));
    expect(v31, contains('windowSplashScreenBackground'));
    expect(v31, contains('@drawable/cleanops_splash_logo'));
  });

  test('all 27 registered screens remain present and readable by the audit',
      () {
    final folder = Directory('lib/presentation/screens');
    final screens = folder.listSync().whereType<File>()
        .where((file) => file.path.endsWith('.dart')).toList();
    expect(screens.length, greaterThanOrEqualTo(27));
    for (final screen in screens) {
      final content = screen.readAsStringSync();
      expect(content.trim().isNotEmpty, isTrue, reason: screen.path);
      expect(
        content.contains('package:flutter/material.dart') ||
            content.contains("export '"),
        isTrue,
        reason: screen.path,
      );
    }
  });
}
