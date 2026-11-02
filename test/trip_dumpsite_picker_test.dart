import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/localization.dart';
import 'package:solid_waste_operations/core/services/trip_dumpsite.dart';
import 'package:solid_waste_operations/presentation/widgets/trip_dumpsite_picker.dart';
import 'package:provider/provider.dart';

void main() {
  Future<void> showPicker(
    WidgetTester tester, {
    List<TripDumpsite> sites = const [],
    String? selectedId,
    bool fromCache = false,
    String? error,
    ValueChanged<String>? onSelected,
  }) => tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => LocaleController(),
      child: MaterialApp(
        home: Scaffold(
          body: TripDumpsitePicker(
            sites: sites,
            selectedId: selectedId,
            enabled: true,
            loading: false,
            fromCache: fromCache,
            error: error,
            onSelected: onSelected ?? (_) {},
            onRetry: () {},
          ),
        ),
      ),
    ),
  );

  testWidgets('empty list has clear guidance and no invented destination', (
    tester,
  ) async {
    await showPicker(tester);
    expect(
      find.text('لا توجد مكبات متاحة. يُرجى إضافتها من إدارة المكبات.'),
      findsOneWidget,
    );
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    expect(find.text('المكب المركزي'), findsNothing);
  });
  testWidgets(
    'cached sites remain selectable offline; searching returns actual ID',
    (tester) async {
      String? selected;
      await showPicker(
        tester,
        fromCache: true,
        sites: const [
          TripDumpsite('first', 'المكب أ', 'الشمال'),
          TripDumpsite('second', 'المكب ب', 'الجنوب'),
        ],
        onSelected: (id) => selected = id,
      );
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'الجنوب');
      await tester.pump();
      expect(find.text('المكب أ'), findsNothing);
      await tester.tap(find.text('المكب ب'));
      await tester.pumpAndSettle();
      expect(selected, 'second');
    },
  );
  testWidgets(
    'permission failure blocks using stale cached list and offers retry',
    (tester) async {
      await showPicker(
        tester,
        selectedId: 'a',
        error: 'تعذر الوصول إلى المكبات.',
        sites: const [TripDumpsite('a', 'مكب', 'موقع')],
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(find.text('إعادة تحميل المكبات'), findsOneWidget);
    },
  );
  testWidgets(
    'removed selection is not silently replaced by another destination',
    (tester) async {
      await showPicker(
        tester,
        selectedId: 'removed',
        sites: const [TripDumpsite('a', 'مكب متاح', 'موقع')],
      );
      expect(find.text('اختر المكب / نقطة التجميع'), findsOneWidget);
      expect(find.text('مكب متاح'), findsNothing);
    },
  );
}
