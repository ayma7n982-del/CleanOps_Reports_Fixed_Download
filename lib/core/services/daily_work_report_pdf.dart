import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import 'work_report_summary.dart';

/// Prints one saved daily group report. Every value comes from that report.
class DailyWorkReportPdf {
  const DailyWorkReportPdf._();

  static String _value(Map<String, dynamic> row, String key) =>
      '${row[key] ?? ''}'.trim();

  static DateTime? _date(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.tryParse('${raw ?? ''}');
  }

  static String _status(String raw) => switch (raw) {
    'submitted' => 'مرسل للمراجعة',
    'approved' => 'معتمد من المجلس',
    'closed' => 'مغلق',
    'needs_edits' => 'بحاجة إلى تعديل',
    _ => 'مسودة',
  };

  static String _weekday(DateTime date) => const [
    'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد',
  ][date.weekday - 1];

  static Future<Uint8List> build(Map<String, dynamic> report) async {
    if (!WorkReportSummary.isWorkReport(report) || report['isDeleted'] == true) {
      throw StateError('هذا السجل ليس تقرير عمل يوميًا صالحًا للطباعة.');
    }
    final workDate = _date(report['workDate'] ?? report['createdAt']);
    if (workDate == null) throw StateError('تاريخ العمل غير مسجل.');
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));
    final prefs = await SharedPreferences.getInstance();
    pw.ImageProvider? logo(String key) {
      try {
        final raw = prefs.getString(key);
        return raw == null || raw.isEmpty ? null : pw.MemoryImage(base64Decode(raw));
      } catch (_) { return null; }
    }
    final municipalityLogo = logo('report_municipality_logo_base64');
    final councilLogo = logo('report_council_logo_base64');
    final unicefLogo = logo('report_unicef_logo_base64');
    final municipality = _value(report, 'municipalityName').isNotEmpty
        ? _value(report, 'municipalityName')
        : prefs.getString('report_municipality_name') ?? 'البلدية غير محددة';
    final council = _value(report, 'councilName').isNotEmpty
        ? _value(report, 'councilName')
        : prefs.getString('report_council_name') ?? 'المجلس غير محدد';
    final cycle = _value(report, 'cycleName').isNotEmpty
        ? _value(report, 'cycleName')
        : prefs.getString('report_project_name') ?? 'الدورة غير محددة';
    final snapshot = report['sourceSnapshot'] is Map
        ? Map<String, dynamic>.from(report['sourceSnapshot'] as Map)
        : <String, dynamic>{};
    final sourceConfirmed = report['countsMode'] == 'operational_sources_v1' &&
        snapshot['serverConfirmed'] == true && snapshot['needsReview'] != true;
    final status = _value(report, 'status');
    final provisional = status == 'draft' || status == 'needs_edits' || !sourceConfirmed;
    String number(String key) => report[key] is num ? '${(report[key] as num).toInt()}' : '—';
    final leaveValues = [report['specialLeave'], report['sickLeave'], report['otherAbsence']];
    final leaves = leaveValues.every((v) => v is! num) ? '—' :
        '${leaveValues.whereType<num>().fold<int>(0, (n, v) => n + v.toInt())}';
    String content(String key) => _value(report, key).isEmpty ? 'لم يرد وصف.' : _value(report, key);
    pw.Widget text(String value, {double size = 9, bool strong = false,
        PdfColor color = PdfColors.blueGrey900}) => pw.Text(value,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(font: strong ? bold : regular, fontSize: size,
            color: color));
    pw.Widget brand(pw.ImageProvider? image, String label) => pw.Expanded(child: pw.Row(children: [
      if (image != null) pw.Container(width: 32, height: 32,
          margin: const pw.EdgeInsets.only(left: 7),
          child: pw.Image(image, fit: pw.BoxFit.contain)),
      pw.Expanded(child: text(label, size: 8.5, strong: true)),
    ]));
    pw.Widget header(pw.Context context) => pw.Directionality(textDirection: pw.TextDirection.rtl,
        child: pw.Column(children: [
          pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: pw.BoxDecoration(color: PdfColors.teal50,
                  borderRadius: pw.BorderRadius.circular(8)),
              child: pw.Row(children: [
                brand(municipalityLogo, municipality),
                brand(councilLogo, council),
                brand(unicefLogo, 'اليونيسف UNICEF'),
              ])),
          pw.SizedBox(height: 8),
          pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: pw.BoxDecoration(color: PdfColors.teal800,
                  borderRadius: pw.BorderRadius.circular(8)),
              child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                text('تقرير الأعمال اليومي', size: 17, strong: true, color: PdfColors.white),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  text(_weekday(workDate), size: 9,
                      strong: true, color: PdfColors.white),
                  text(DateFormat('yyyy-MM-dd').format(workDate), size: 10,
                      strong: true, color: PdfColors.white),
                ]),
              ])),
          pw.SizedBox(height: 7),
        ]));
    pw.Widget footer(pw.Context context) => pw.Directionality(textDirection: pw.TextDirection.rtl,
        child: pw.Column(children: [
          pw.Divider(color: PdfColors.teal100),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            text('المصدر: تقرير المجموعة المحفوظ وسجلات الحضور والنقلات المرتبطة به', size: 7),
            text('صفحة ${context.pageNumber} من ${context.pagesCount}', size: 7),
          ]),
        ]));
    pw.Widget metadata(String label, String value) => pw.Expanded(child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        margin: const pw.EdgeInsets.only(left: 6),
        decoration: pw.BoxDecoration(color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          text(label, size: 7.5, color: PdfColors.blueGrey600),
          pw.SizedBox(height: 3),
          text(value.isEmpty ? 'غير محدد' : value, size: 10, strong: true),
        ])));
    pw.Widget metric(String label, String value, PdfColor accent) => pw.Expanded(child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        margin: const pw.EdgeInsets.only(left: 6),
        decoration: pw.BoxDecoration(color: PdfColors.teal50,
            borderRadius: pw.BorderRadius.circular(7)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          text(label, size: 8, color: PdfColors.blueGrey700),
          pw.SizedBox(height: 4), text(value, size: 18, strong: true, color: accent),
        ])));
    pw.Widget sectionTitle(String index, String label) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 13, bottom: 6),
        padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: pw.BoxDecoration(color: PdfColors.teal50,
            borderRadius: pw.BorderRadius.circular(5)),
        child: pw.Row(children: [
          text(index, size: 9, strong: true, color: PdfColors.teal800),
          pw.SizedBox(width: 8), text(label, size: 10, strong: true),
        ]));
    List<pw.Widget> paragraph(String label, String key) => [
          text(label, size: 8, strong: true, color: PdfColors.teal800),
          pw.SizedBox(height: 3),
          text(content(key), size: 9),
          pw.SizedBox(height: 9),
        ];
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 26, 30, 30),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        header: header, footer: footer,
        build: (_) => [
          pw.Directionality(textDirection: pw.TextDirection.rtl, child: pw.Row(children: [
            metadata('المجموعة', _value(report, 'groupName')),
            metadata('الوردية', _value(report, 'shift')),
            metadata('الدورة', cycle),
          ])),
          pw.SizedBox(height: 7),
          pw.Directionality(textDirection: pw.TextDirection.rtl, child: pw.Row(children: [
            metadata('مُعد التقرير', _value(report, 'reporterName')),
            metadata('البلدية', municipality),
            metadata('الحالة', _status(status)),
          ])),
          pw.SizedBox(height: 10),
          pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: pw.BoxDecoration(color: provisional ? PdfColors.orange50 : PdfColors.green50,
                  borderRadius: pw.BorderRadius.circular(6)),
              child: text(provisional
                  ? 'الأعداد أو حالة الاعتماد تحتاج مراجعة. هذا التقرير ليس اعتمادًا نهائيًا.'
                  : 'الأعداد مؤكدة من سجلات المصدر وقت الإرسال؛ حالة التقرير: ${_status(status)}.',
                  size: 8, color: provisional ? PdfColors.orange800 : PdfColors.green700)),
          pw.SizedBox(height: 11),
          pw.Directionality(textDirection: pw.TextDirection.rtl, child: pw.Row(children: [
            metric('الحضور', number('attendance'), PdfColors.green700),
            metric('الغياب', number('absence'), PdfColors.red700),
            metric('النقلات المكتملة', number('trips'), PdfColors.teal800),
            metric('الإجازات وأسباب أخرى', leaves, PdfColors.orange800),
          ])),
          pw.SizedBox(height: 8),
          text('إجازة خاصة: ${number('specialLeave')}    •    إجازة مرضية: ${number('sickLeave')}    •    أسباب أخرى: ${number('otherAbsence')}    •    نقلات جارية: ${snapshot['activeTrips'] is num ? snapshot['activeTrips'] : '—'}', size: 8),
          sectionTitle('01', 'العمل المنفذ'),
          ...paragraph('المهام المنفذة / المخطط لها', 'workTasks'),
          ...paragraph('الأعمال المكتملة', 'completedWork'),
          sectionTitle('02', 'المواقع والوضع التشغيلي'),
          ...paragraph('مواقع العمل', 'workLocations'),
          ...paragraph('حالة الحاويات', 'containerStatus'),
          ...paragraph('حالة المكب', 'landfillStatus'),
          sectionTitle('03', 'العوائق والمقترحات'),
          ...paragraph('المشكلات أو العوائق', 'problems'),
          ...paragraph('المقترحات', 'suggestions'),
          pw.SizedBox(height: 16),
          pw.Directionality(textDirection: pw.TextDirection.rtl,
              child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                text('إعداد: ____________________', size: 8),
                text('مراجعة منسق البلدية: ____________________', size: 8),
                text('اعتماد مجلس الخدمات: ____________________', size: 8),
              ])),
        ]));
    return Uint8List.fromList(await doc.save());
  }
}
