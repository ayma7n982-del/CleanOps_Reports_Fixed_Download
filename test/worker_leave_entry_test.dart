import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:solid_waste_operations/core/localization.dart';
import 'package:solid_waste_operations/core/models/core_models.dart';
import 'package:solid_waste_operations/core/services/attendance_entry_service.dart';
import 'package:solid_waste_operations/core/services/auth_service.dart';
import 'package:solid_waste_operations/core/services/config_service.dart';
import 'package:solid_waste_operations/core/services/data_service.dart';
import 'package:solid_waste_operations/core/services/local_store.dart';
import 'package:solid_waste_operations/presentation/screens/level1_supervisor.dart';
import 'package:solid_waste_operations/presentation/widgets/worker_leave_form.dart';

const workerA = {'id': 'a', 'name': 'عامل أ', 'groupId': 'g1', 'group': 'g1'};
const workerB = {'id': 'b', 'name': 'عامل ب', 'groupId': 'g1', 'group': 'g1'};
AppUser actor({
  String role = 'group_supervisor',
  Map<String, FeaturePolicy> policies = const {},
}) =>
    AppUser(
      id: 's1',
      username: 's1',
      name: 'مشرف',
      role: role,
      scope: 'بلدية',
      groupId: 'g1',
      policies: policies,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Box box;
  late LocalStore store;
  late ConfigService config;
  late DataService data;
  late AttendanceEntryService service;
  final day = DateTime(2026, 11, 2);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cleanops_leave_');
    Hive.init(dir.path);
    box = await Hive.openBox('leave');
    store = LocalStore(box);
    config = ConfigService(store);
    data = DataService(store, config);
    service = AttendanceEntryService(data);
  });
  tearDown(() async {
    data.dispose();
    config.dispose();
    await box.close();
    await dir.delete(recursive: true);
  });
  Future<bool> save({
    Map<String, String> worker = workerA,
    AppUser? user,
    String status = 'leave',
    String reason = '',
    int? from,
    int? to,
    Future<bool> Function(Map<String, dynamic>)? confirm,
  }) =>
      service.saveLeave(
        actor: user ?? actor(),
        worker: worker,
        status: status,
        day: day,
        reason: reason,
        fromMinute: from,
        toMinute: to,
        confirmReplacement: confirm ?? (_) async => false,
      );

  test(
    'leave queues only selected worker, preserves colleagues, survives restart and syncs once',
    () async {
      final other = {
        'id': AttendanceEntryService.recordId('g1', config.shift, day, 'b'),
        '_entity': 'attendance',
        'workerId': 'b',
        'groupId': 'g1',
        'status': 'present',
        'reportedBy': 's1',
      };
      data.operations = [Map.of(other)];
      expect(await save(reason: 'موعد طبي'), isTrue);
      expect(data.queue, hasLength(1));
      expect(data.operations.singleWhere((r) => r['workerId'] == 'b'), other);
      final record = await service.record(
        actor: actor(),
        workerId: 'a',
        day: day,
      );
      expect(record!['status'], 'leave');
      expect(record['leaveReason'], 'موعد طبي');
      expect(DateTime.parse(record['createdAt']).day, day.day);
      expect(await save(reason: 'موعد طبي'), isTrue);
      expect(
        data.queue,
        hasLength(1),
        reason: 'Repeated save cannot enqueue an identical write',
      );
      final sent = <Map<String, dynamic>>[];
      final restored = DataService(
        store,
        config,
        syncItemOverride: (item, payload) async {
          expect(item.entity, 'attendance');
          sent.add(payload);
        },
      )
        ..queue = store.queue()
        ..operations = store.cachedOperations()
        ..online = true;
      try {
        await restored.sync();
        await restored.sync();
        expect(sent, hasLength(1));
        expect(sent.single['workerId'], 'a');
        expect(restored.queue, isEmpty);
        expect(store.queue(), isEmpty);
      } finally {
        restored.dispose();
      }
    },
  );

  test(
    'existing presence requires confirmation; cancellation writes nothing',
    () async {
      data.operations = [
        {
          'id': AttendanceEntryService.recordId('g1', config.shift, day, 'a'),
          '_entity': 'attendance',
          'workerId': 'a',
          'workerName': 'عامل أ',
          'groupId': 'g1',
          'reportedBy': 's1',
          'status': 'present',
          'createdAt': '2026-11-02T08:00:00',
          'checkInAt': '2026-11-02T08:00:00',
          'ppeComplete': true,
        },
      ];
      var asked = 0;
      expect(
        await save(
          confirm: (previous) async {
            asked++;
            expect(previous['status'], 'present');
            return false;
          },
        ),
        isFalse,
      );
      expect(asked, 1);
      expect(data.queue, isEmpty);
      expect(await save(confirm: (_) async => true), isTrue);
      final record = await service.record(
        actor: actor(),
        workerId: 'a',
        day: day,
      );
      expect(record!['checkInAt'], isNull);
      expect(record['ppeComplete'], isFalse);
      expect(record['createdAt'], '2026-11-02T08:00:00');
      expect(
        record['id'],
        AttendanceEntryService.recordId('g1', config.shift, day, 'a'),
      );
      expect(data.operations, hasLength(1));
    },
  );

  test(
    'permission requires a valid interval and retains it in the same attendance record',
    () async {
      for (final interval in [(null, null), (600, 550), (-1, 20), (0, 1500)]) {
        await expectLater(
          save(status: 'permission', from: interval.$1, to: interval.$2),
          throwsArgumentError,
        );
      }
      expect(data.queue, isEmpty);
      expect(
        await save(status: 'permission', from: 600, to: 660, reason: 'مراجعة'),
        isTrue,
      );
      var record = await service.record(
        actor: actor(),
        workerId: 'a',
        day: day,
      );
      expect(record!['permissionFromMinute'], 600);
      expect(record['permissionToMinute'], 660);
      expect(await save(status: 'leave', confirm: (_) async => true), isTrue);
      record = await service.record(actor: actor(), workerId: 'a', day: day);
      expect(record!['permissionFromMinute'], isNull);
      expect(record['permissionToMinute'], isNull);
      expect(data.operations, hasLength(1));
    },
  );

  test(
    'role, permissions, worker scope, frozen stage and another reporter fail without writes',
    () async {
      await expectLater(
        save(user: actor(role: 'municipality_coordinator')),
        throwsStateError,
      );
      await expectLater(
        save(user: actor(policies: {'leave': FeaturePolicy(create: false)})),
        throwsStateError,
      );
      await expectLater(
        save(worker: {...workerA, 'groupId': 'g2'}),
        throwsStateError,
      );
      config.stageFrozen = true;
      await expectLater(save(), throwsStateError);
      config.stageFrozen = false;
      data.operations = [
        {
          'id': AttendanceEntryService.recordId('g1', config.shift, day, 'a'),
          '_entity': 'attendance',
          'workerId': 'a',
          'groupId': 'g1',
          'reportedBy': 'someone-else',
          'status': 'present',
        },
      ];
      await expectLater(save(confirm: (_) async => true), throwsStateError);
      expect(data.queue, isEmpty);
    },
  );

  test(
    'a stage frozen while confirmation is open prevents the pending save',
    () async {
      data.operations = [
        {
          'id': AttendanceEntryService.recordId('g1', config.shift, day, 'a'),
          '_entity': 'attendance',
          'workerId': 'a',
          'groupId': 'g1',
          'reportedBy': 's1',
          'status': 'present',
        },
      ];
      await expectLater(
        save(
          confirm: (_) async {
            config.stageFrozen = true;
            return true;
          },
        ),
        throwsStateError,
      );
      expect(data.queue, isEmpty);
    },
  );

  test('day, group and shift identities cannot collide', () {
    final first = AttendanceEntryService.recordId('g1', config.shift, day, 'a');
    expect(
      AttendanceEntryService.recordId('g2', config.shift, day, 'a'),
      isNot(first),
    );
    expect(
      AttendanceEntryService.recordId('g1', '16:00 - 00:00', day, 'a'),
      isNot(first),
    );
    expect(
      AttendanceEntryService.recordId(
        'g1',
        config.shift,
        day.add(const Duration(days: 1)),
        'a',
      ),
      isNot(first),
    );
  });

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    double width = 320,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = AuthService(store)..currentUser = actor();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: config),
          ChangeNotifierProvider.value(value: data),
          ChangeNotifierProvider(create: (_) => LocaleController()),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'quick form saves one selected worker at narrow mobile width without full attendance or PPE',
    (tester) async {
      WorkerLeaveSelection? saved;
      await mount(
        tester,
        WorkerLeaveForm(
          workers: const [workerA, workerB],
          shift: config.shift,
          onSave: (selection) async {
            saved = selection;
            return true;
          },
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('leave-search')),
        'عامل أ',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('leave-worker-b')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('leave-worker-a')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('save-worker-leave')),
      );
      await tester.tap(find.byKey(const ValueKey('save-worker-leave')));
      await tester.pumpAndSettle();
      expect(saved?.worker['id'], 'a');
      expect(saved?.status, 'leave');
      expect(find.text('حفظ كشف حضور مجموعتي'), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'form restores permission details and blocks duplicate taps during a save',
    (tester) async {
      final pending = Completer<bool>();
      var saves = 0;
      await mount(
        tester,
        WorkerLeaveForm(
          workers: const [workerA, workerB],
          shift: config.shift,
          onLoad: (worker, selectedDay) async => {
            'status': 'permission',
            'leaveReason': 'طبيب',
            'permissionFromMinute': 600,
            'permissionToMinute': 660,
          },
          onSave: (selection) {
            saves++;
            expect(selection.reason, 'طبيب');
            expect(selection.fromMinute, 600);
            return pending.future;
          },
        ),
      );
      await tester.tap(find.byKey(const ValueKey('leave-worker-a')));
      await tester.pumpAndSettle();
      expect(find.text('الحالة المسجلة: إذن خاص'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('save-worker-leave')),
      );
      await tester.tap(find.byKey(const ValueKey('save-worker-leave')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-worker-leave')));
      await tester.pump();
      expect(saves, 1);
      pending.complete(true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shortcut opens quick leave form, saves one row and full sheet restores it',
    (tester) async {
      data.operations = [
        for (final w in [workerA, workerB]) {...w, '_entity': 'worker'},
      ];
      await mount(
        tester,
        const Level1SupervisorScreen(initialAction: 'leave'),
        width: 430,
      );
      expect(find.byType(WorkerLeaveForm), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('leave-worker-a')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('leave-reason')));
      await tester.enterText(
          find.byKey(const ValueKey('leave-reason')), 'إجازة طبية');
      await tester.ensureVisible(
        find.byKey(const ValueKey('save-worker-leave')),
      );
      await tester.tap(find.byKey(const ValueKey('save-worker-leave')));
      await tester.pumpAndSettle();
      expect(
        data.queue.where((item) => item.entity == 'attendance'),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await mount(
        tester,
        const Level1SupervisorScreen(initialAction: 'attendance'),
        width: 430,
      );
      await tester.scrollUntilVisible(
        find.text('عمال مجموعتي'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final statuses = tester
          .widgetList<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .map((w) => w.initialValue);
      expect(statuses, contains('leave'));
      expect(statuses, contains('unset'));
      final unset = find.byWidgetPredicate((w) =>
          w is DropdownButtonFormField<String> && w.initialValue == 'unset');
      await tester.ensureVisible(unset);
      await tester.tap(unset);
      await tester.pumpAndSettle();
      await tester.tap(find.text('غياب').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('حفظ كشف حضور مجموعتي'));
      await tester.tap(find.text('حفظ كشف حضور مجموعتي'));
      await tester.pumpAndSettle();
      expect(data.queue.where((item) => item.entity == 'attendance'),
          hasLength(2));
      final leave = data.operations.singleWhere(
          (r) => r['_entity'] == 'attendance' && r['workerId'] == 'a');
      expect(leave['status'], 'leave');
      expect(leave['leaveReason'], 'إجازة طبية');
      expect(
          data.operations.singleWhere((r) =>
              r['_entity'] == 'attendance' && r['workerId'] == 'b')['status'],
          'absent');
      expect(tester.takeException(), isNull);
    },
  );
}
