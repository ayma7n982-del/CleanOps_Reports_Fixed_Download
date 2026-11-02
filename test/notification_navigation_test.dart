import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:solid_waste_operations/core/models/core_models.dart';
import 'package:solid_waste_operations/core/services/auth_service.dart';
import 'package:solid_waste_operations/core/services/config_service.dart';
import 'package:solid_waste_operations/core/services/data_service.dart';
import 'package:solid_waste_operations/core/services/local_store.dart';
import 'package:solid_waste_operations/core/services/notification_target_policy.dart';
import 'package:solid_waste_operations/presentation/screens/notifications_screen.dart';

class _Box extends Fake implements Box {
  @override
  Future<void> put(dynamic key, dynamic value) async {}
}

AppUser actor(String role, {Map<String, FeaturePolicy> policies = const {}}) =>
    AppUser(
      id: 'person',
      username: 'person',
      name: 'مستخدم',
      role: role,
      scope: 'بلدية الاختبار',
      groupId: 'g1',
      policies: policies,
    );

NotificationItem notice({
  String id = 'notice',
  String? sourceId = 'case-42',
  String? recipient,
  String? role,
}) => NotificationItem(
  id: id,
  title: 'بلاغ مطلوب',
  body: 'تفاصيل التنبيه',
  level: 'urgent',
  createdAt: '2026-11-02',
  sourceEntity: 'emergency',
  sourceId: sourceId,
  targetUserId: recipient,
  targetRole: role,
);

Map<String, dynamic> record({String group = 'g1', bool deleted = false}) => {
  'id': 'case-42',
  '_entity': 'emergency',
  'street': 'موقع البلاغ المحدد',
  'municipalityCoordinatorId': 'person',
  'groupId': group,
  'status': 'closed',
  'isDeleted': deleted,
};

void main() {
  test('source metadata survives persistence and read-state updates', () {
    final n = NotificationItem.fromJson(
      notice(recipient: 'person', role: 'municipality_coordinator').toJson(),
    ).copyWith(read: true);
    expect(n.sourceId, 'case-42');
    expect(n.sourceEntity, 'emergency');
    expect(n.targetUserId, 'person');
    expect(n.targetRole, 'municipality_coordinator');
    expect(n.read, isTrue);
  });

  test('legacy SOS links recover without parsing free-form message text', () {
    for (final id in [
      'sos-emergency-case-42',
      'case-42_L2',
      'case-42_L3',
      'case-42_UNICEF',
    ]) {
      final n = NotificationItem.fromJson({'id': id});
      expect(n.sourceId, 'case-42');
      expect(n.sourceEntity, 'emergency');
    }
    expect(
      NotificationItem.fromJson({
        'id': 'random',
        'body': 'بلاغ case-42',
      }).sourceId,
      isNull,
    );
  });

  test('hidden, deleted, unrelated and wrong-entity targets remain closed', () {
    expect(
      NotificationTargetPolicy.canOpen(
        actor('worker'),
        notice(),
        record(group: 'other'),
      ),
      isFalse,
    );
    expect(
      NotificationTargetPolicy.canOpen(
        actor('donor_manager'),
        notice(),
        record(deleted: true),
      ),
      isFalse,
    );
    expect(
      NotificationTargetPolicy.canOpen(
        actor('donor_manager'),
        notice(recipient: 'other'),
        record(),
      ),
      isFalse,
    );
    expect(
      NotificationTargetPolicy.canOpen(actor('donor_manager'), notice(), {
        ...record(),
        '_entity': 'trip',
      }),
      isFalse,
    );
    expect(
      NotificationTargetPolicy.canOpen(
        actor(
          'donor_manager',
          policies: const {'emergency': FeaturePolicy(visible: false)},
        ),
        notice(),
        record(),
      ),
      isFalse,
    );
  });

  for (final role in [
    'worker',
    'group_supervisor',
    'municipality_coordinator',
    'jsc_coordinator',
    'donor_manager',
  ]) {
    testWidgets(
      '$role opens the exact linked closed record and can reopen read notices',
      (tester) async {
        final store = LocalStore(_Box());
        final auth = AuthService(store)..currentUser = actor(role);
        final data = DataService(store, ConfigService(store))
          ..notifications = [notice()]
          ..operations = [record()];
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: auth),
              ChangeNotifierProvider.value(value: data),
            ],
            child: const MaterialApp(home: NotificationsPage()),
          ),
        );
        await tester.tap(find.text('بلاغ مطلوب'));
        await tester.pumpAndSettle();
        expect(find.text('موقع البلاغ المحدد'), findsOneWidget);
        expect(find.text('case-42'), findsOneWidget);
        expect(data.notifications.single.read, isTrue);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('بلاغ مطلوب'));
        await tester.pumpAndSettle();
        expect(find.text('case-42'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        data.dispose();
        auth.dispose();
      },
    );
  }

  testWidgets(
    'offline missing record explains recovery and retains unread status',
    (tester) async {
      final store = LocalStore(_Box());
      final auth = AuthService(store)..currentUser = actor('worker');
      final data = DataService(store, ConfigService(store))
        ..notifications = [notice()];
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: data),
          ],
          child: const MaterialApp(home: NotificationsPage()),
        ),
      );
      await tester.tap(find.text('بلاغ مطلوب'));
      await tester.pumpAndSettle();
      expect(find.textContaining('السجل غير محفوظ'), findsOneWidget);
      expect(data.notifications.single.read, isFalse);
      data.operations = [record()];
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle();
      expect(find.text('case-42'), findsOneWidget);
      expect(data.notifications.single.read, isTrue);
      await tester.pumpWidget(const SizedBox());
      data.dispose();
      auth.dispose();
    },
  );
}
