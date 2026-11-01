import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:solid_waste_operations/core/constants/app_constants.dart';
import 'package:solid_waste_operations/core/models/core_models.dart';
import 'package:solid_waste_operations/core/services/auth_service.dart';
import 'package:solid_waste_operations/core/services/local_store.dart';
import 'package:solid_waste_operations/core/services/feature_route_policy.dart';
import 'package:solid_waste_operations/presentation/feature_navigation.dart';
import 'package:solid_waste_operations/presentation/screens/attendance_reports_home_screen.dart';
import 'package:solid_waste_operations/presentation/screens/level1_supervisor.dart';
import 'package:solid_waste_operations/presentation/screens/scoped_operation_records.dart';
import 'package:solid_waste_operations/presentation/widgets/app_navigation_bar.dart';

class _UnusedBox extends Fake implements Box {}

AppUser actor(String role, {Map<String, FeaturePolicy> policies = const {}}) =>
    AppUser(id: 'person-1', username: 'person', name: 'مستخدم', role: role,
        scope: 'بلدية الاختبار', groupId: 'group-1', policies: policies);

void main() {
  test('the four approved job names keep their existing authorization IDs', () {
    expect(roleNames['donor_manager'], 'مدير اليونسيف');
    expect(roleNames['jsc_coordinator'], 'منسق مجلس الخدمات');
    expect(roleNames['municipality_coordinator'], 'منسق البلدية');
    expect(roleNames['group_supervisor'], 'مشرف ميداني');
  });

  test('field shortcuts open the requested form rather than the workspace', () {
    final user = actor('group_supervisor');
    for (final feature in ['attendance', 'leave', 'trips', 'streets', 'emergency']) {
      final page = appFeaturePage(user, feature);
      expect(page, isA<Level1SupervisorScreen>());
      expect((page as Level1SupervisorScreen).initialAction, feature);
    }
  });

  test('worker and management shortcuts do not open supervisor entry forms', () {
    for (final role in ['worker', 'municipality_coordinator', 'jsc_coordinator', 'donor_manager']) {
      final user = actor(role);
      expect(appFeaturePage(user, 'attendance'), isA<AttendanceReportsHomeScreen>());
      expect(appFeaturePage(user, 'trips'), isA<ScopedOperationRecordsScreen>());
      final leave = appFeaturePage(user, 'leave') as AttendanceReportsHomeScreen;
      expect(leave.leavesOnly, isTrue);
    }
  });

  test('view-only attendance uses the record viewer and hidden tasks stay closed', () {
    final user = actor('group_supervisor', policies: const {
      'attendance': FeaturePolicy(create: false),
      'trips': FeaturePolicy(visible: false),
    });
    expect(FeatureRoutePolicy.resolve(user, 'attendance'), FeatureDestination.attendanceReport);
    expect(appFeaturePage(user, 'leave'), isA<AttendanceReportsHomeScreen>());
    expect(appFeaturePage(user, 'trips'), isNull);
    expect(appFeaturePage(actor('worker'), 'workers'), isNull);
    expect(appFeaturePage(actor('worker'), 'cycle'), isNull);
    expect(appFeaturePage(user, 'unknown-task'), isNull);
  });

  for (final width in [320.0, 360.0, 430.0]) {
    testWidgets('manager has four usable destinations at width $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = AuthService(LocalStore(_UnusedBox()))
        ..currentUser = actor('donor_manager');
      await tester.pumpWidget(ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: MaterialApp(builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!), home: Scaffold(appBar: AppBar(
            title: const Text('مدير اليونسيف'), bottom: const AppNavigationBar()))),
      ));
      await tester.pumpAndSettle();
      for (final label in ['الرئيسية', 'البحث', 'الرسائل', 'الإشعارات']) {
        expect(find.text(label), findsOneWidget);
        final button = find.ancestor(of: find.text(label), matching: find.byType(TextButton));
        expect(tester.widget<TextButton>(button).onPressed, isNotNull);
      }
      expect(tester.takeException(), isNull);
      auth.dispose();
    });
  }

  testWidgets('home leaves the workspace and clears the legacy route stack', (tester) async {
    await tester.pumpWidget(MaterialApp(
      routes: {'/home': (_) => const Scaffold(body: Text('actual home'))},
      home: Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('workspace'), bottom: const AppNavigationBar()),
          body: const Text('workspace content')))),
        child: const Text('open workspace')))),
    ));
    await tester.tap(find.text('open workspace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الرئيسية'));
    await tester.pumpAndSettle();
    expect(find.text('actual home'), findsOneWidget);
    expect(find.text('workspace content'), findsNothing);
    expect(Navigator.of(tester.element(find.text('actual home'))).canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });
}
