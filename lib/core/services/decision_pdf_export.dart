import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart' as f;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../presentation/widgets/decision_charts.dart';
import 'decision_analytics.dart';
import 'supply_chain_analytics.dart';
import '../../presentation/widgets/supply_chain_charts.dart';

const _navy = PdfColor.fromInt(0xFF12304A);
const _teal = PdfColor.fromInt(0xFF008B78);
const _light = PdfColor.fromInt(0xFFF0F7F8);

Future<Uint8List> _supplyImage(List<List<double>> series, String kind) async {
  final recorder = ui.PictureRecorder();
  final canvas = f.Canvas(recorder)..scale(3);
  canvas.drawRect(const f.Rect.fromLTWH(0, 0, 600, 190), f.Paint()..color = f.Colors.white);
  SupplyChartPainter(series, kind).paint(canvas, const f.Size(600, 190));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1800, 570);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose(); picture.dispose();
  return bytes!.buffer.asUint8List();
}

Future<Uint8List> _ringImage(double? value, {bool gauge = false,
    List<double>? portions, List<f.Color>? colors, f.Color? color}) async {
  final recorder = ui.PictureRecorder();
  final canvas = f.Canvas(recorder)..scale(3);
  canvas.drawRect(const f.Rect.fromLTWH(0, 0, 220, 220),
    f.Paint()..color = f.Colors.white);
  final chosen = color ?? decisionAttendanceColor(value);
  DecisionRingPainter(portions: portions ?? [value ?? 0],
    colors: colors ?? [chosen], gauge: gauge).paint(canvas, const f.Size(220, 220));
  final picture = recorder.endRecording();
  final image = await picture.toImage(660, 660);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose(); picture.dispose();
  return bytes!.buffer.asUint8List();
}
Future<Uint8List> _barImage(double actual, double? target) async {
  final recorder = ui.PictureRecorder();
  final canvas = f.Canvas(recorder)..scale(3);
  canvas.drawRect(const f.Rect.fromLTWH(0, 0, 640, 40),
    f.Paint()..color = f.Colors.white);
  DecisionComparisonPainter(actual, target ?? 0, 1).paint(canvas, const f.Size(640, 32));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1920, 120);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose(); picture.dispose();
  return bytes!.buffer.asUint8List();
}

String decisionReportDate(Object? value, {bool includeTime = true}) {
  final date = decisionDate(value);
  if (date == null) return 'غير موثّق';
  const months = ['يناير','فبراير','مارس','أبريل','مايو','يونيو',
    'يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'];
  final day = '${date.day} ${months[date.month - 1]} ${date.year}';
  final time = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  return includeTime ? '$day، $time' : day;
}

String decisionStatusLabel(DecisionRow d) {
  if (d['_pending'] == true) return 'بانتظار تأكيد المزامنة';
  return const {'issued': 'صدر القرار؛ التنفيذ قيد المتابعة',
    'acknowledged': 'أكد المشرف الاستلام', 'completed': 'وثّق المشرف التنفيذ',
    'approved': 'اعتماد للدورة القادمة'}['${d['status']}'] ?? 'غير محدد';
}

/// All chart images are rendered independently of scroll position and animation.
/// Uses the same pure Flutter painters as the screen, with no network font fetch.
Future<Uint8List> buildDecisionPdf({required DecisionAnalytics data,
    required List<DecisionRow> decisions, required String coordinator,
    required String quality, Uint8List? chartImage,
    List<DecisionRow> plans = const [], String section = 'all',
    SupplyChainAnalytics? supply}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));
  final doc = pw.Document(title: 'لوحة الإجراءات والقرارات الذكية',
    author: coordinator, creator: 'CleanOps 4.9.5');
  final attendance = await _ringImage(data.attendanceRate,
    portions: data.workers == 0 ? [] : [data.present / data.workers,
      data.absent / data.workers, (data.workers - data.present - data.absent) / data.workers],
    colors: [decisionAttendanceColor(data.attendanceRate), f.Colors.redAccent, f.Colors.blueGrey]);
  final container = await _ringImage(data.emptyRate,
    color: f.Colors.teal, portions: data.containers.isEmpty ? [] :
      [data.emptyRate ?? 0, data.fullContainers.length / data.containers.length,
        data.containers.where((c) => c['status'] == 'partial').length / data.containers.length],
    colors: [f.Colors.teal, f.Colors.redAccent, f.Colors.orange]);
  final dump = await _ringImage(data.dumpsiteRate, gauge: true,
    color: (data.dumpsiteRate ?? 0) >= .85 ? f.Colors.redAccent : f.Colors.cyan);
  final bars = <String, Uint8List>{}, ppe = <String, Uint8List>{}, planning = <String, Uint8List>{};
  for (final g in data.groups) {
    bars[g.id] = await _barImage(g.tons ?? g.completedTrips.length.toDouble(),
      g.tons != null ? g.targetTons : g.targetTrips);
    ppe[g.id] = await _ringImage(g.ppeRate);
  }
  for (final r in data.recommendations) {
    final actual = r.kind == 'increase_carts' ? r.group.cartWorkers : r.group.workers.length;
    planning[r.key] = await _barImage(actual.toDouble(), (actual + r.delta).toDouble());
  }
  pw.Widget text(String value, {double size = 10, bool strong = false,
      PdfColor color = _navy}) => pw.Text(value,
    style: pw.TextStyle(font: strong ? bold : regular, fontSize: size, color: color));
  pw.Widget ring(Uint8List image, double? value, {double size = 125, PdfColor color = _teal}) => pw.SizedBox(
    width: size, height: size, child: pw.Stack(alignment: pw.Alignment.center, children: [
      pw.Image(pw.MemoryImage(image), width: size, height: size),
      text(decisionPercent(value), size: size * .14, strong: true, color: color),
    ]));
  pw.Widget heading(String value) => pw.Container(
    width: double.infinity, margin: const pw.EdgeInsets.only(top: 12, bottom: 8),
    padding: const pw.EdgeInsets.all(10), color: _navy,
    child: text(value, size: 13, strong: true, color: PdfColors.white));
  pw.Widget note(String value) => pw.Container(
    width: double.infinity, margin: const pw.EdgeInsets.only(bottom: 8),
    padding: const pw.EdgeInsets.all(10), color: _light, child: text(value, size: 9));
  pw.Widget card(String title, String body, {Uint8List? image}) => pw.Wrap(children: [pw.Container(
    width: double.infinity, margin: const pw.EdgeInsets.only(bottom: 8),
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300),
      borderRadius: pw.BorderRadius.circular(8)),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      text(title, size: 11, strong: true, color: _teal), pw.SizedBox(height: 5),
      text(body, size: 9),
      if (image != null) ...[pw.SizedBox(height: 6),
        pw.Image(pw.MemoryImage(image), height: 26, fit: pw.BoxFit.fill)],
    ]))]);
  final content = <pw.Widget>[
    pw.Container(padding: const pw.EdgeInsets.all(18), color: _navy,
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        text('CLEANOPS • DECISION INTELLIGENCE', size: 10, color: PdfColors.white),
        pw.SizedBox(height: 8),
        text('لوحة الإجراءات والقرارات الذكية', size: 21, strong: true, color: PdfColors.white),
        pw.SizedBox(height: 8),
        text('المسؤول: $coordinator • الدورة: ${data.cycleName}', color: PdfColors.white),
        text('تاريخ التقرير: ${decisionReportDate(data.now)}\n'
          'الوردية: ${data.shift.label}', color: PdfColors.white),
      ])),
    pw.SizedBox(height: 10), note('جودة البيانات: $quality'),
    if (section == 'supply') note('الملخص التنفيذي أدناه يشمل نطاق لوحة القرار بالكامل. '
      'تحليل سلسلة الإمداد في الصفحات التالية يستخدم الفلاتر المختارة: '
      '${(supply ?? SupplyChainAnalytics.from(data)).scope}.'),
    heading('الملخص التنفيذي • النسب والمؤشرات'),
    pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      for (final item in [
        ['الالتزام بالحضور', attendance, data.attendanceRate, PdfColor.fromInt(decisionAttendanceColor(data.attendanceRate).value)],
        ['الحاويات الفارغة', container, data.emptyRate, _teal],
        ['استيعاب المكبات', dump, data.dumpsiteRate, (data.dumpsiteRate ?? 0) >= .85 ? PdfColors.red700 : _teal],
      ]) pw.Expanded(child: pw.Column(children: [
        text(item[0] as String, strong: true),
        ring(item[1] as Uint8List, item[2] as double?, color: item[3] as PdfColor),
      ])),
    ]),
    note('حاضر ${data.present} • غائب مثبت ${data.absent} • غير مسجّل ${data.unknown} • '
      'عمال ${data.workers}\n'
      'حاويات ممتلئة ${data.fullContainers.length} / ${data.containers.length} • '
      'مكبات نشطة ${data.dumpsites.length}\n'
      'الحضور = الحاضرين / العمال النشطين. غير المسجّل لا يُحتسب غائبًا. '
      'المكبات مرجّحة بالسعات؛ علامة الخطر عند 85%.'),
  ];
  if (section == 'all' || section == 'operations') {
    content.add(pw.NewPage());
    content.add(heading('1 • قرارات الميدان الفورية وكفاءة المجموعات'));
    content.add(note('الأخضر: المنجز • الأزرق: الهدف المسجّل. '
      'الأطنان من النقلات المكتملة فقط؛ يُذكر التقدير عند غياب الوزن الفعلي.'));
    for (final g in data.groups) {
      content.add(card(g.name,
        'الحضور ${decisionPercent(g.attendanceRate)} • الغياب ${decisionPercent(g.absenceRate)} • '
        'غير مسجّل ${g.unknown}\n'
        'نقلات مسجلة ${g.trips.length} • مكتملة ${g.completedTrips.length}\n'
        '${g.tons == null ? 'الوزن غير متاح؛ الرسم يقارن عدد النقلات' :
          '${g.estimatedTons ? 'كمية تقديرية' : 'وزن مسجّل'}: ${g.tons!.toStringAsFixed(2)} طن'}\n'
        'الهدف: ${g.tons == null ? g.targetTrips ?? 'غير مسجّل' :
          g.targetTons ?? 'غير مسجّل'}\n'
        'الحاويات الممتلئة ${decisionPercent(g.fullRate)}',
        image: bars[g.id]));
    }
    for (final c in data.fullContainers) {
      content.add(card('حاوية حرجة • ${c['locationName'] ?? c['id']}',
        'ممتلئة • المجموعة: ${c['groupId'] ?? 'غير مربوطة'}\n'
        'بدء الامتلاء: ${decisionReportDate(c['fullSince'])}'));
    }
    if (data.groups.isEmpty) content.add(note('لا توجد مجموعات متاحة ضمن نطاق التقرير.'));
  }
  if (section == 'all' || section == 'strategic') {
    content.add(pw.NewPage());
    content.add(heading('2 • التخطيط الاستراتيجي للدورة القادمة'));
    content.add(note('نافذة التحليل تبدأ ${decisionReportDate(data.historyStart, includeTime: false)}. '
      'التوصيات مشروطة بأدلة تاريخية، وتُحفظ مستقلة عن توزيع الدورة الحالية.'));
    final recommendations = data.recommendations;
    if (recommendations.isEmpty) content.add(note(
      'لا توجد توصيات مستوفية للشروط أو البيانات التاريخية غير كافية.'));
    for (final r in recommendations) {
      content.add(card('${r.group.name} • ${r.title}',
        '${r.reason}\nالعمال الحاليون ${r.group.workers.length} • '
        'عمال الكارات ${r.group.cartWorkers}\n'
        'تغيير مقترح ${r.delta} • استيفاء الشروط ${decisionPercent(r.confidence)}\n'
        'الحضور التاريخي ${decisionPercent(r.group.historicalAttendance)} • '
        'تكرار الامتلاء ${decisionPercent(r.group.historicalFullRate)}', image: planning[r.key]));
    }
    for (final p in plans) {
      content.add(card('خطة محفوظة • ${p['targetCycleId']}',
        'المعتمد: ${p['coordinatorName']} • ${decisionReportDate(p['createdAt'])}\n'
        'الحالة: ${decisionStatusLabel(p)}\n'
        'عدد التوصيات: ${(p['decisionIds'] as List? ?? []).length}'));
    }
  }
  if (section == 'all' || section == 'health') {
    content.add(pw.NewPage());
    content.add(heading('3 • القرارات الصحية والبيئية'));
    content.add(note('خطر أعلى من 12 ساعة يُثبت فقط بوقت بدء امتلاء محفوظ. '
      'نسبة المرض تعتمد على الغياب المصنّف مرضيًا ولا تثبت خلو الباقين من المرض.'));
    for (final c in data.healthHazards) {
      content.add(card('خطر صحي وبيئي عالي - أولوية قصوى',
        '${c['locationName'] ?? c['id']} • بداية الامتلاء ${decisionReportDate(c['fullSince'])}\n'
        'التوصية: إخلاء طارئ وتطهير الموقع.'));
    }
    for (final g in data.groups) {
      content.add(pw.Container(margin: const pw.EdgeInsets.only(bottom: 8),
        padding: const pw.EdgeInsets.all(8), color: _light,
        child: pw.Row(children: [
          ring(ppe[g.id]!, g.ppeRate, size: 75,
            color: PdfColor.fromInt(decisionAttendanceColor(g.ppeRate).value)),
          pw.SizedBox(width: 12),
          pw.Expanded(child: text('${g.name}\n'
            'الوقاية المهنية: ${decisionPercent(g.ppeRate)}\n'
            'الغياب المرضي المصنّف: ${decisionPercent(g.sicknessRate)}', strong: true)),
        ])));
    }
    for (final d in data.dumpsites) {
      final fill = decisionNumber(d['fillPercentage']);
      content.add(card('${d['nameAr'] ?? d['name'] ?? d['id']}',
        'الامتلاء: ${fill == null ? 'غير متاح' : '${fill.toStringAsFixed(1)}%'}\n'
        'السعة المسجلة: ${d['capacity'] ?? 'غير متاحة'}\n'
        '${(fill ?? 0) >= 85 ? 'خطر: تحويل المسار إلى مكب بديل آمن وطلب التسوية' : 'دون حد الخطر 85%'}'));
    }
  }
  if (section == 'all' || section == 'supply') {
    final s = supply ?? SupplyChainAnalytics.from(data);
    content.add(pw.NewPage());
    content.add(heading('تحليل سلسلة الإمداد • SUPPLY CHAIN'));
    content.add(note('${s.scope}\n${s.period} • أيام مكتملة حتى نهاية أمس\n'
      'الفترة السابقة مساوية: ${s.days} يومًا. الحالة الحالية للحاويات مستقلة عن الفترة.\n'
      '${s.currentCovered ? '' : 'الفترة الحالية تتجاوز بداية السجل؛ الأعداد جزئية.\n'}'
      '${s.historyCovered ? '' : 'الفترة السابقة غير مكتملة في السجل؛ مقارنة التغير غير متاحة.'}'));
    content.add(card('مؤشرات الأداء', 'نقلات مسجلة ${s.recorded} • مكتملة ${s.completed}\n'
      'الإكمال ${decisionPercent(s.completion)} • تغير النقلات ${decisionPercent(s.change)}\n'
      'مجموع الأوزان المعروفة ${s.tons?.toStringAsFixed(2) ?? 'غير متاح'} طن\n'
      'تغطية الوزن ${s.weighed} من ${s.completed} نقلة مكتملة؛ قد تشمل تقديرات.\n'
      'الأصفار تعني عدم وجود سجلات في البيانات المتاحة؛ راجع جودة البيانات أعلاه.'));
    content.add(heading('اتجاه النقلات اليومية • Line Charts'));
    content.add(note('الأخضر: مكتملة • الأزرق: مسجلة • الوحدة: نقلة\n'
      'المحور الزمني من الأقدم يسارًا إلى الأحدث يمينًا. الحالة حسب آخر تحديث للنقلة المسجلة في ذلك اليوم.'));
    content.add(pw.Image(pw.MemoryImage(await _supplyImage(supplyTrendSeries(s), 'line')), height: 160));
    content.add(pw.TableHelper.fromTextArray(headers: ['اليوم', 'المسجلة', 'المكتملة'],
      data: [for (final p in s.trend) ['${p.day.day}/${p.day.month}', '${p.recorded}', '${p.completed}']],
      headerStyle: pw.TextStyle(font: bold, fontSize: 9, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: _navy),
      cellStyle: pw.TextStyle(font: regular, fontSize: 8), cellAlignment: pw.Alignment.center));
    content.add(pw.NewPage());
    content.add(heading('المقارنات والتوزيعات • Comparisons'));
    // Keep each chart readable even with a large number of authorized groups.
    for (var offset = 0; offset < s.groups.length; offset += 8) {
      final batch = s.groups.skip(offset).take(8).toList();
      content.add(note('مقارنة النقلات • الأخضر: الحالية • الأزرق: السابقة\n'
        '${batch.map((g) => g.name).join(' • ')}'));
      content.add(pw.Image(pw.MemoryImage(await _supplyImage([
        batch.map((g) => g.current.toDouble()).toList(),
        if (s.historyCovered) batch.map((g) => g.previous.toDouble()).toList(),
      ], 'bar')), height: 130));
      for (final g in batch) {
        content.add(note('${g.name}: ${g.current} حالية / ${s.historyCovered ? g.previous : 'غير متاح'} سابقة'));
      }
      content.add(note('مقارنة الأوزان المعروفة • طن • نفس ترتيب المجموعات'));
      content.add(pw.Image(pw.MemoryImage(await _supplyImage([
        batch.map((g) => g.tons).toList()], 'bar')), height: 120));
      for (final g in batch) {
        content.add(note('${g.name}: ${g.weighed == 0 ? 'وزن غير متاح' : '${g.tons.toStringAsFixed(2)} طن'}'));
      }
    }
    content.add(heading('توزيع حالة الحاويات الآن • Pie & Donut'));
    final portions = [s.distribution.values.map((n) => n.toDouble()).toList()];
    final pie = await _supplyImage(portions, 'pie');
    final donut = await _supplyImage(portions, 'donut');
    content.add(pw.Row(children: [for (final image in [pie, donut])
      pw.Expanded(child: pw.Image(pw.MemoryImage(image), height: 130))]));
    final total = s.distribution.values.fold<int>(0, (a, b) => a + b);
    content.add(note([for (final e in s.distribution.entries)
      '${const {'empty':'فارغة - أخضر','full':'ممتلئة - أحمر','partial':'جزئية - برتقالي','unknown':'غير معروفة - رمادي'}[e.key]}: ${e.value} '
      '(${decisionPercent(total == 0 ? null : e.value / total)})'].join('\n')));
  }
  if (section != 'supply') {
  content.add(pw.NewPage(freeSpace: 140));
  content.add(heading('سجل القرارات والاعتمادات'));
  final filtered = decisions.where((d) => section == 'all' ||
    (section == 'strategic' && d['status'] == 'approved') ||
    (section == 'health' && ['health', 'ppe', 'dumpsite_redirect'].contains(d['kind'])) ||
    (section == 'operations' && ['stagnation', 'collection', 'temporary_coverage', 'broadcast'].contains(d['kind'])))
    .toList()..sort((a, b) => '${b['createdAt'] ?? ''}'.compareTo('${a['createdAt'] ?? ''}'));
  for (final d in filtered) {
    content.add(card('${d['title'] ?? ''}', '${d['body'] ?? ''}\n'
      'المسؤول: ${d['coordinatorName']} • ${decisionReportDate(d['createdAt'])}\n'
      'المجموعة: ${d['groupId'] ?? ''} • ${decisionStatusLabel(d)}\n'
      'تأكيد الاستلام: ${decisionReportDate(d['acknowledgedAt'])}\n'
      'إثبات التنفيذ: ${d['completionNote'] ?? 'لم يُوثّق'}'));
  }
  if (filtered.isEmpty) content.add(note('لا توجد قرارات محفوظة لهذا القسم.'));
  }
  doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, maxPages: 500,
    margin: const pw.EdgeInsets.all(28), textDirection: pw.TextDirection.rtl,
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
    header: (_) => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 8),
      child: text('CleanOps 4.9.5 | مركز القرار • $coordinator', size: 8, color: _teal)),
    footer: (c) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [text('قراءة تحليلية للسجلات المتاحة • $quality', size: 7),
        text('${c.pageNumber} / ${c.pagesCount}', size: 8)]),
    build: (_) => content));
  return doc.save();
}

Future<void> exportDecisionPdf({required DecisionAnalytics data,
    required List<DecisionRow> decisions, required String coordinator,
    required String quality, Uint8List? chartImage,
    List<DecisionRow> plans = const [], String section = 'all',
    SupplyChainAnalytics? supply}) async {
  final bytes = await buildDecisionPdf(data: data, decisions: decisions,
    coordinator: coordinator, quality: quality, plans: plans, section: section, supply: supply);
  await Printing.layoutPdf(name: 'CleanOps_Decisions_${section}_'
    '${data.now.toIso8601String().substring(0, 10)}.pdf', onLayout: (_) async => bytes);
}

