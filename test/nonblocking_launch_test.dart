import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/presentation/widgets/eco_boot_splash.dart';

void main() {
  test('Flutter splash renders before Firebase and remote service initialization', () {
    final source = File('lib/main.dart').readAsStringSync();
    final firstFrame = source.indexOf('runApp(const MaterialApp(');
    final firebase = source.indexOf('await StartupDiagnostics.initializeFirebase();');
    final fullApp = source.indexOf('child: const EnterpriseApp(),');
    final resumed = source.indexOf('unawaited(_completeOnlineStartup(auth, data, config));');
    expect(firstFrame, greaterThan(0));
    expect(firebase, greaterThan(firstFrame));
    expect(fullApp, greaterThan(firebase));
    expect(resumed, greaterThan(fullApp));
    expect(source, contains('config.seedFor(auth.currentUser!.role)'));
  });

  test('remote operations no longer block the full app first frame', () {
    final source = File('lib/main.dart').readAsStringSync();
    final helperBegin = source.indexOf('Future<void> _completeOnlineStartup(');
    final mainBegin = source.indexOf('Future<void> main() async {');
    final remoteReads = source.indexOf('await config.loadRemote();');
    final serverSync = source.indexOf('await data.refreshOperations();');
    expect(helperBegin, greaterThan(0));
    expect(mainBegin, greaterThan(helperBegin));
    expect(remoteReads, greaterThan(helperBegin));
    expect(remoteReads, lessThan(mainBegin));
    expect(serverSync, lessThan(mainBegin));
    expect(source, contains('await config.attachRole(account.role)'));
    expect(source, contains('await data.sync();'));
  });

  testWidgets('first frame remains visibly branded at Samsung mobile width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        backgroundColor: Color(0xFFF8FCFA),
        body: EcoBootSplash(progress: .65),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(EcoBootSplash), findsOneWidget);
    expect(find.text('CleanOps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
