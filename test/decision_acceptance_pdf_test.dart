import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/decision_analytics.dart';
import 'package:solid_waste_operations/core/services/decision_pdf_export.dart';

List<DecisionRow> rows(dynamic value) => (value as List? ?? [])
    .map((r) => Map<String, dynamic>.from(r as Map)).toList();

DecisionAnalytics denseData() {
  final operations = <DecisionRow>[];
  final containers = <DecisionRow>[];
  for (var g = 0; g < 24; g++) {
    final id = 'stress-group-$g';
    operations.add({'id':id,'_entity':'group',
      'name':'منطقة الاختبار الاصطناعي رقم $g - الأحياء الشرقية والغربية '
        'ومحيط السوق المركزي ومرافق الخدمات العامة والطرق الفرعية الممتدة حتى حدود البلدية',
      'municipalityCoordinatorId':'stress-owner','targetTrips':6,'targetTons':3});
    for (var w = 0; w < 12; w++) {
      operations.add({'id':'w-$g-$w','_entity':'worker','groupId':id});
      operations.add({'id':'a-$g-$w','_entity':'attendance','groupId':id,
        'workerId':'w-$g-$w','createdAt':'2026-10-30T08:30:00',
        'status': w < 9 ? 'present' : 'absent'});
    }
    for (var day = 1; day <= 30; day++) {
      operations.add({'id':'trip-$g-$day','_entity':'trip','groupId':id,
        'createdAt':'2026-10-${day.toString().padLeft(2,'0')}T09:00:00',
        'status':day % 4 == 0 ? 'pending' : 'completed',
        'weightTons':.5 + g / 20,'tripPpe':{'boots':true,'gloves':g % 2 == 0}});
    }
    containers.add({'id':'c-$g','groupId':id,'status':g % 3 == 0 ? 'empty':'full',
      'fullSince':'2026-10-28T09:00:00',
      'locationName':'موقع اختبار اصطناعي طويل الاسم في محيط المدارس والمراكز الصحية '
        'والأحياء السكنية المتفرعة من الشارع الرئيسي للمجموعة $g'});
  }
  return DecisionAnalytics.calculate(operations:operations,users:[],
    containers:containers,dumpsites:[for(var d=0;d<6;d++) {
      'id':'dump-$d','nameAr':'مكب اختبار اصطناعي ذو اسم طويل لخدمة المناطق '
        'الشمالية والجنوبية والامتدادات الميدانية التابعة للمجلس المشترك رقم $d',
      'capacity':100,'fillPercentage':40+d*10,
    }],trips:[],cycles:[],now:DateTime(2026,10,30,10),shiftText:'08:00 - 16:00');
}

Future<void> saveReport(DecisionAnalytics data, String name, String section,
    {required String quality, List<DecisionRow> decisions=const []}) async {
  final bytes = await buildDecisionPdf(data:data,decisions:decisions,
    coordinator:'مراجعة جودة التقارير - بيانات منزوعة الأسماء أو اصطناعية حسب عنوان الملف',
    quality:quality,section:section);
  expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  expect(bytes.length,greaterThan(10000));
  final directory=Directory('build/decision-acceptance/reports')..createSync(recursive:true);
  File('${directory.path}/$name.pdf').writeAsBytesSync(bytes);
}

void main() {
  testWidgets('dense Arabic names and 24 groups render multi-page chart reports', (tester) async {
    final data=denseData();
    expect(data.groups.length,24);
    expect(data.workers,288);
    expect(data.present,216);
    expect(data.attendanceRate,.75);
    await tester.runAsync(() async {
      final decisions=[for(var i=0;i<24;i++) <String,dynamic>{
        'id':'stress-$i','kind':'collection','status':'acknowledged',
        'title':'عنوان قرار اختبار طويل للمجموعة $i - تفريغ الحاويات ومتابعة الجمع '
          'والتطهير وتوثيق التنفيذ وفق اختصاص المشرف المسؤول عن المنطقة',
        'body':List.filled(4,'هذا وصف اختبار اصطناعي لتدقيق التفاف النص العربي '
          'وعدم انقسام البطاقة أو اختفاء معلومات القرار في التقرير.').join(' '),
        'coordinatorName':'مسؤول اختبار اصطناعي','groupId':'stress-group-$i',
        'createdAt':'2026-10-30T09:00:00','acknowledgedAt':'2026-10-30T09:05:00',
      }];
      for (final section in ['all','supply']) {
        await saveReport(data,'STRESS_SYNTHETIC_$section',section,
          quality:'ضغط اصطناعي - ليس سجلات تشغيل فعلية',decisions:decisions);
      }
    });
  },timeout:const Timeout(Duration(minutes:10)));

  final source=Platform.environment['DECISION_PRODUCTION_SNAPSHOT'];
  testWidgets('read-only sanitized production snapshot renders all five reports', (tester) async {
    final snapshot=jsonDecode(File(source!).readAsStringSync()) as Map<String,dynamic>;
    expect(snapshot['source'],'production-read-only-sanitized');
    final c=snapshot['collections'] as Map<String,dynamic>;
    final data=DecisionAnalytics.calculate(operations:rows(c['operations']),
      users:rows(c['users']),containers:rows(c['containers']),dumpsites:rows(c['dumpsites']),
      trips:rows(c['trips']),cycles:[...rows(c['work_cycles']),...rows(c['cycles'])],
      now:DateTime.parse(snapshot['now'] as String).toLocal(),
      shiftText:snapshot['shiftText'] as String);
    // Empty production remains empty; do not substitute synthetic rows or claim
    // the production itself was dense. The independent stress test covers that.
    final groupRows=rows(c['operations']).where((r)=>
      r['_entity']=='group' && decisionActive(r)).length;
    expect(data.groups.length,groupRows);
    final capped=(snapshot['capped'] as List).isNotEmpty;
    await tester.runAsync(() async {
      for(final section in ['all','operations','strategic','health','supply']) {
        await saveReport(data,'PRODUCTION_SANITIZED_$section',section,
          quality:capped ? 'إنتاج منزوعة الأسماء - قراءة جزئية محدودة' :
            'إنتاج منزوعة الأسماء - دون تاريخ حالات الحاويات - وردية 08:00 إلى 16:00');
      }
    });
    // Counts only, never document IDs, contact fields, original names or secrets.
    // ignore: avoid_print
    print('Production PDF coverage: groups=${data.groups.length}, workers=${data.workers}, '
      'containers=${data.containers.length}, dumpsites=${data.dumpsites.length}, capped=$capped');
  },skip:source==null,timeout:const Timeout(Duration(minutes:10)));
}
