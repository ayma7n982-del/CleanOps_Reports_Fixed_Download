import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:solid_waste_operations/core/localization.dart';
import 'package:solid_waste_operations/presentation/widgets/container_status_picker.dart';

void main() {
  testWidgets(
    'no default status, explicit choice, and disabled state during save',
    (tester) async {
      String? status;
      var enabled = true;
      late StateSetter rebuild;
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleController(),
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return ContainerStatusPicker(
                    value: status,
                    enabled: enabled,
                    onChanged: (v) => setState(() => status = v),
                  );
                },
              ),
            ),
          ),
        ),
      );
      expect(
        tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .every((c) => !c.selected),
        isTrue,
      );
      await tester.tap(find.text('نصف ممتلئة'));
      await tester.pumpAndSettle();
      expect(status, 'partial');
      expect(find.text('اختر الحالة قبل الحفظ.'), findsNothing);
      rebuild(() => enabled = false);
      await tester.pump();
      expect(
        tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .every((c) => c.onSelected == null),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
