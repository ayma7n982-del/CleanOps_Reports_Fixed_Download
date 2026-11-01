import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:solid_waste_operations/core/localization.dart';
import 'package:solid_waste_operations/presentation/widgets/assistant_snapshot_card.dart';

Widget surface(Future<Map<String, dynamic>> Function() load, {String account = 'a'}) =>
    ChangeNotifierProvider(
      create: (_) => LocaleController(),
      child: MaterialApp(home: Scaffold(body: AssistantSnapshotCard(
        key: ValueKey(account), load: load,
      ))),
    );

void main() {
  testWidgets('loading stays visible and a parent rebuild does not restart reads',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    var calls = 0;
    Future<Map<String, dynamic>> load() { calls++; return pending.future; }
    await tester.pumpWidget(surface(load));
    expect(find.text('جاري تحميل مؤشرات التشغيل...'), findsOneWidget);
    await tester.pumpWidget(surface(load));
    expect(calls, 1);
    pending.complete({'workers': 7});
    await tester.pumpAndSettle();
    expect(find.text('العمال: 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('synchronous initialization failure offers a working retry',
      (tester) async {
    var calls = 0;
    Future<Map<String, dynamic>> load() {
      if (++calls == 1) throw StateError('Firebase unavailable');
      return Future.value({'workers': 4});
    }
    await tester.pumpWidget(surface(load));
    await tester.pumpAndSettle();
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('العمال: 4'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('a stalled offline request becomes retryable after 20 seconds',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(surface(() => pending.future));
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing account discards the previous account indicators',
      (tester) async {
    await tester.pumpWidget(surface(() async => {'workers': 8}));
    await tester.pumpAndSettle();
    expect(find.text('العمال: 8'), findsOneWidget);
    await tester.pumpWidget(surface(() async => {'workers': 2}, account: 'b'));
    await tester.pumpAndSettle();
    expect(find.text('العمال: 8'), findsNothing);
    expect(find.text('العمال: 2'), findsOneWidget);
  });
}
