import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:solid_waste_operations/core/localization.dart';
import 'package:solid_waste_operations/core/models/core_models.dart';
import 'package:solid_waste_operations/core/services/auth_service.dart';
import 'package:solid_waste_operations/core/services/config_service.dart';
import 'package:solid_waste_operations/core/services/data_service.dart';
import 'package:solid_waste_operations/core/services/local_store.dart';
import 'package:solid_waste_operations/core/services/operations_admin_service.dart';
import 'package:solid_waste_operations/presentation/screens/ai_command_center.dart';
import 'package:solid_waste_operations/presentation/screens/notifications_screen.dart';
import 'package:solid_waste_operations/presentation/widgets/field_shortcuts.dart';

class _UnusedBox extends Fake implements Box {}

class _OfflineOperations extends Fake implements OperationsAdminService {
  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> activeCycles() =>
      Stream<QuerySnapshot<Map<String, dynamic>>>.error(StateError('offline'));

  @override
  Future<Map<String, dynamic>> liveOperationalSnapshot(AppUser actor) async => {
    'activeUsers': 0,
    'trips': 0,
    'groups': 0,
    'emergencies': 0,
  };
}

AppUser supervisor({Map<String, FeaturePolicy> policies = const {}}) => AppUser(
  id: 'supervisor',
  username: 'supervisor',
  name: 'مشرف الاختبار',
  role: 'group_supervisor',
  scope: 'بلدية',
  groupId: 'group-a',
  policies: policies,
);

void main() {
  for (final width in [320.0, 430.0]) {
    testWidgets(
      'focus retains usable field tasks and returns from notifications at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final store = LocalStore(_UnusedBox());
        final auth = AuthService(store)..currentUser = supervisor();
        final config = ConfigService(store);
        final data = DataService(store, config)
          ..operations = [
            {'_entity': 'worker', 'groupId': 'group-a', 'name': 'عامل أ'},
            {'_entity': 'worker', 'groupId': 'group-b', 'name': 'عامل ب'},
          ];
        addTearDown(auth.dispose);
        addTearDown(config.dispose);
        addTearDown(data.dispose);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthService>.value(value: auth),
              ChangeNotifierProvider<ConfigService>.value(value: config),
              ChangeNotifierProvider<DataService>.value(value: data),
              ChangeNotifierProvider(create: (_) => LocaleController()),
              Provider<OperationsAdminService>(
                create: (_) => _OfflineOperations(),
              ),
            ],
            child: MaterialApp(
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: const Scaffold(body: AICommandCenter()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byType(Switch),
          350,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(find.byTooltip('إيقاف وضع التركيز'), findsOneWidget);
        expect(find.byType(FieldTaskShortcuts), findsOneWidget);
        expect(find.byType(FieldSupportShortcuts), findsOneWidget);
        for (final feature in [
          'attendance',
          'leave',
          'trips',
          'streets',
          'containers',
          'emergency',
        ]) {
          expect(find.byKey(ValueKey('field-task-$feature')), findsOneWidget);
        }
        for (final feature in [
          'messages',
          'notifications',
          'search',
          'reports',
          'sync',
        ]) {
          expect(find.byKey(ValueKey('field-tool-$feature')), findsOneWidget);
        }
        final notifications = find.byKey(
          const ValueKey('field-tool-notifications'),
        );
        await tester.dragUntilVisible(
          notifications.hitTestable(),
          find.byType(Scrollable).first,
          const Offset(0, -250),
        );
        await tester.pumpAndSettle();
        await tester.tap(notifications);
        await tester.pumpAndSettle();
        expect(find.byType(NotificationsPage), findsOneWidget);
        expect(find.text('لا توجد إشعارات جديدة'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.dragUntilVisible(
          find.byTooltip('إيقاف وضع التركيز').hitTestable(),
          find.byType(Scrollable).first,
          const Offset(0, 300),
        );
        expect(find.byTooltip('إيقاف وضع التركيز'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('عمال مجموعتي'),
          350,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('1'), findsNWidgets(2));
        expect(find.text('تعذر تحميل الدورة'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'hidden permissions stay hidden while view-only tasks remain available',
    (tester) async {
      final user = supervisor(
        policies: const {
          'streets': FeaturePolicy(visible: false),
          'attendance': FeaturePolicy(create: false),
          'messages': FeaturePolicy(visible: false),
          'notifications': FeaturePolicy(visible: false),
        },
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<LocaleController>(
          create: (_) => LocaleController(),
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    FieldTaskShortcuts(user: user),
                    FieldSupportShortcuts(user: user),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-task-streets')), findsNothing);
      expect(find.byKey(const ValueKey('field-tool-messages')), findsNothing);
      expect(
        find.byKey(const ValueKey('field-tool-notifications')),
        findsNothing,
      );
      expect(find.text('سجل الحضور والغياب'), findsOneWidget);
      expect(find.text('سجل الإجازات والأذونات'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
