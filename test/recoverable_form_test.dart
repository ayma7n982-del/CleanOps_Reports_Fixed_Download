import 'package:solid_waste_operations/core/services/config_service.dart';
import 'package:solid_waste_operations/core/localization.dart';
import 'package:solid_waste_operations/presentation/screens/work_entry_form_screen.dart';
import 'package:solid_waste_operations/core/services/data_service.dart';
import 'package:solid_waste_operations/presentation/screens/cycle_manual_attendance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solid_waste_operations/core/models/core_models.dart';
import 'package:solid_waste_operations/core/services/auth_service.dart';
import 'package:solid_waste_operations/presentation/widgets/recoverable_form.dart';

class DraftAuth extends ChangeNotifier implements AuthService {
  DraftAuth(this.id);
  final String id;
  @override
  AppUser? get currentUser => AppUser(
    id: id,
    username: id,
    name: id,
    role: 'group_supervisor',
    scope: 'assigned_only',
    groupId: 'g',
    policies: {},
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class DraftConfig extends ChangeNotifier implements ConfigService {
  @override String get shift => '08:00 - 16:00';
  @override dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class DraftData extends ChangeNotifier implements DataService {
  @override List<SyncItem> get queue => [];
  @override bool get online => false;
  @override List<NotificationItem> get notifications => [];
  @override List<Map<String, dynamic>> get operations => [];
  @override dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class DraftForm extends StatefulWidget {
  const DraftForm({super.key});
  @override
  State<DraftForm> createState() => DraftFormState();
}

class DraftFormState extends State<DraftForm> with RecoverableForm<DraftForm> {
  final text = TextEditingController();
  String status = 'absent';
  @override
  String get draftId => 'test-form';
  @override
  Map<String, TextEditingController> get draftFields => {'text': text};
  @override
  Map<String, dynamic> get draftValues => {'status': status};
  @override
  void restoreDraftValues(Map<String, dynamic> v) {
    status = v['status'] as String;
  }

  @override
  Widget build(BuildContext context) => protectDraft(
    Scaffold(
      body: Column(
        children: [
          TextField(controller: text),
          Switch(
            value: status == 'present',
            onChanged: (v) => setState(() => status = v ? 'present' : 'absent'),
          ),
          TextButton(
            onPressed: clearFormDraft,
            child: const Text('Successful save'),
          ),
          TextButton(onPressed: () {}, child: const Text('Failed save')),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }
}

Widget surface(DraftAuth auth) => ChangeNotifierProvider<AuthService>.value(
  value: auth,
  child: MaterialApp(home: DraftForm(key: ValueKey(auth.id))),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('text and selections survive immediate disposal and reopening', (
    tester,
  ) async {
    final auth = DraftAuth('a');
    await tester.pumpWidget(surface(auth));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'نص غير مكتمل');
    await tester.tap(find.byType(Switch));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(surface(auth));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'نص غير مكتمل',
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(
      find.text('استُعيدت مدخلاتك السابقة. راجعها قبل الحفظ.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('a different account never sees the previous account draft', (
    tester,
  ) async {
    await tester.pumpWidget(surface(DraftAuth('a')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'private draft');
    await tester.pumpWidget(surface(DraftAuth('b')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });
  testWidgets(
    'failed save preserves input and successful save clears recovery',
    (tester) async {
      final auth = DraftAuth('a');
      await tester.pumpWidget(surface(auth));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'keep me');
      await tester.tap(find.text('Failed save'));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(surface(auth));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'keep me',
      );
      await tester.tap(find.text('Successful save'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(surface(auth));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('compact recovery fits a small dialog and restores after close', (
    tester,
  ) async {
    final auth = DraftAuth('a');
    final text = TextEditingController();
    Widget dialog() => ChangeNotifierProvider<AuthService>.value(
      value: auth,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 260,
              child: RecoverableDraftPanel(
                id: 'dialog',
                fields: {'text': text},
                values: () => {},
                restore: (_) {},
                builder: (context, change, clear) =>
                    Material(child: TextField(controller: text)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(dialog());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'modal draft');
    await tester.pumpWidget(const SizedBox());
    text.clear();
    await tester.pumpWidget(dialog());
    await tester.pumpAndSettle();
    expect(text.text, 'modal draft');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    text.dispose();
  });

  testWidgets('daily report restores narrative and keeps automatic counts', (tester) async {
    final data = DraftData();
    final config = DraftConfig();
    Widget report() => MultiProvider(providers: [
      ChangeNotifierProvider<AuthService>.value(value: DraftAuth('reporter')),
      ChangeNotifierProvider<DataService>.value(value: data),
      ChangeNotifierProvider<ConfigService>.value(value: config),
      ChangeNotifierProvider(create: (_) => LocaleController()),
    ], child: const MaterialApp(home: WorkEntryFormScreen()));
    final tasks = find.widgetWithText(TextField, 'المهام المنفذة / المخطط لها');
    await tester.pumpWidget(report());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(tasks, 300, scrollable: find.byType(Scrollable).first);
    await tester.enterText(tasks, 'عمل غير مكتمل');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(report());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(tasks, 300, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<TextField>(tasks).controller!.text, 'عمل غير مكتمل');
    expect(find.widgetWithText(TextField, 'عدد النقلات'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('manual attendance recovers existing edits when a worker is added', (tester) async {
    final auth = DraftAuth('manual-reporter');
    final data = DraftData();
    Widget manual(List<Map<String, dynamic>> people) => MultiProvider(providers: [
      ChangeNotifierProvider<AuthService>.value(value: auth),
      ChangeNotifierProvider<DataService>.value(value: data),
      ChangeNotifierProvider(create: (_) => LocaleController()),
    ], child: MaterialApp(home: CycleManualAttendanceScreen(people: people)));
    await tester.pumpWidget(manual([{'id': 'w1', 'name': 'First'}]));
    await tester.pumpAndSettle();
    final first = tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>).first);
    first.onChanged!('present');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(manual([{'id': 'w1', 'name': 'First'}, {'id': 'w2', 'name': 'New'}]));
    await tester.pumpAndSettle();
    expect(tester.widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>)).where((w) => w.value == 'present').length, 1);
    expect(tester.takeException(), isNull);
  });

}
