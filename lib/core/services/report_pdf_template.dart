import 'report_letterhead.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../constants/app_constants.dart';
import '../models/core_models.dart';
import 'report_service.dart';
import 'report_content.dart';
import 'report_ratios.dart';

class ReportPdfTemplate {
  final pw.Font regular;
  final pw.Font bold;
  final AppUser? user;
  final String title;
  final ReportSnapshot snapshot;
  final pw.ImageProvider? logo;
  final pw.ImageProvider? municipalityLogo, councilLogo, unicefLogo;
  final String languageCode;
  final String municipalityName, councilName, projectName;
  bool get english => languageCode == 'en';
  String t(String ar, String en) => english ? en : ar;
  ReportPdfTemplate({required this.regular, required this.bold, required this.user, required this.title, required this.snapshot, this.logo, this.municipalityLogo, this.councilLogo, this.unicefLogo, this.languageCode = 'ar', this.municipalityName = '', this.councilName = '', this.projectName = ''});

  pw.Widget _kpi(String label, String value) => pw.Container(
    padding: const pw.EdgeInsets.all(9),
    decoration: pw.BoxDecoration(color: PdfColors.teal50,
        borderRadius: pw.BorderRadius.circular(7)),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(label, style: pw.TextStyle(font: regular, fontSize: 8,
          color: PdfColors.blueGrey700)),
      pw.SizedBox(height: 5),
      pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 17,
          color: PdfColors.teal800)),
    ]));
  pw.Widget _breakdownTable(ReportBreakdown section) {
    final entries = section.values.entries.toList();
    final maximum = entries.fold<int>(0, (value, entry) => value + entry.value);
    return pw.Table(
      columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(2), 2: const pw.FlexColumnWidth(2)},
      children: [for (final entry in entries) pw.TableRow(children: [
        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(entry.key,
            style: pw.TextStyle(font: regular, fontSize: 8))),
        pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 5),
          child: pw.Row(children: [
            if (entry.value > 0) pw.Expanded(flex: entry.value,
              child: pw.Container(height: 5, color: PdfColors.teal700)),
            if (maximum - entry.value > 0) pw.Expanded(flex: maximum - entry.value,
              child: pw.Container(height: 5, color: PdfColors.grey200)),
          ])),
        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${entry.value} • ${RatioMath.display(RatioMath.percent(entry.value, maximum))}',
            style: pw.TextStyle(font: bold, fontSize: 8))),
      ])],
    );
  }
  pw.Widget _section(String heading,List<pw.Widget> children)=>pw.Container(
    margin:const pw.EdgeInsets.only(top:11),
    padding:const pw.EdgeInsets.all(10),
    decoration:pw.BoxDecoration(color:PdfColors.grey100,
        borderRadius:pw.BorderRadius.circular(7)),
    child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
      pw.Text(heading,style:pw.TextStyle(font:bold,fontSize:11,
          color:PdfColors.teal800)),
      pw.Divider(color: PdfColors.teal100),
      ...children,
    ]));

  List<pw.Widget> build() {
    final role=user?.role ?? 'donor_manager'; final roleTitle=english ? ({'donor_manager':'System Manager','jsc_coordinator':'JSC Coordinator','municipality_coordinator':'Municipality Coordinator','group_supervisor':'Group Supervisor','worker':'Worker'}[role] ?? 'Operational Report') : (roleNames[role] ?? 'التقرير التشغيلي');
    final metrics = ReportContent.metrics(snapshot);
    final sections = ReportContent.breakdowns(snapshot, english: english);
    return [
      pw.Container(padding:const pw.EdgeInsets.all(14),decoration:pw.BoxDecoration(color:PdfColors.blueGrey900,borderRadius:pw.BorderRadius.circular(10)),child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
        pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 17, color: PdfColors.white)),
        pw.Text(roleTitle,style:pw.TextStyle(font:bold,fontSize:9,color:PdfColors.amber)),
        pw.Text('${t('الفترة: ','Period: ')}${snapshot.periodLabel}',style:pw.TextStyle(font:regular,fontSize:8,color:PdfColors.white)),
        pw.Text(snapshot.filterLabel(english: english), style: pw.TextStyle(font: regular, fontSize: 8, color: PdfColors.white)),
        pw.Text('${t('تاريخ الإصدار: ','Generated: ')}${DateFormat('yyyy-MM-dd HH:mm').format(snapshot.generatedAt)}',style:pw.TextStyle(font:regular,fontSize:8,color:PdfColors.white)),
      ])),
      pw.SizedBox(height: 12),
      if (snapshot.legacyCounts != null) pw.Text(t('ملخص النسخة القديمة المحفوظة', 'Stored legacy summary')),
      if (snapshot.sourceMayBeIncomplete) _section(t('تنبيه اكتمال البيانات', 'Data completeness warning'), [
        pw.Text(t('قد تكون البيانات جزئية؛ راجع المصدر قبل الاعتماد.',
            'Data may be partial; verify the source before approval.'),
            style: pw.TextStyle(font: bold, fontSize: 9, color: PdfColors.orange800)),
      ]),
      for (var offset = 0; offset < metrics.length; offset += 3) ...[
        pw.SizedBox(height: 6),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          for (final metric in metrics.skip(offset).take(3)) pw.Expanded(
            child: _kpi(metric.label(english), metric.value)),
        ]),
      ],
      pw.SizedBox(height: 10),
      pw.Text(t('الأعداد من السجلات المتاحة ضمن الفلاتر. مقارنة النقلات وحدها لا تحدد الكفاءة.',
          'Counts reflect available filtered records. Trip counts alone do not determine efficiency.'),
          style: pw.TextStyle(font: regular, fontSize: 8)),
      pw.SizedBox(height: 12),
      pw.Text(t('النسب ومؤشرات الأداء', 'Ratios and performance indicators'),
          style: pw.TextStyle(font: bold, fontSize: 11, color: PdfColors.teal800)),
      for (final ratio in ReportContent.ratios(snapshot)) ...[
        pw.SizedBox(height: 7),
        pw.Text('${ratio.label(english)}: ${ratio.display(english)}',
            style: pw.TextStyle(font: bold, fontSize: 9)),
        pw.Text(ratio.basis(english), style: pw.TextStyle(font: regular, fontSize: 8)),
      ],
      for (final section in sections) ...[
        pw.SizedBox(height: 14),
        pw.Text(section.title, style: pw.TextStyle(font: bold, fontSize: 11, color: PdfColors.teal800)),
        pw.Divider(color: PdfColors.teal100),
        if (section.values.isEmpty) pw.Text(t('لا توجد سجلات', 'No records'),
            style: pw.TextStyle(font: regular, fontSize: 8))
        else _breakdownTable(section),
      ],
      if (snapshot.legacyCounts == null && (snapshot.reportType == 'containers' || snapshot.reportType == 'trips')) ...[
        pw.SizedBox(height: 14),
        pw.Text(t('السجلات المطابقة للفلاتر', 'Records matching filters'),
            style: pw.TextStyle(font: bold, fontSize: 11, color: PdfColors.teal800)),
        pw.Table(columnWidths: {0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(3)},
          children: [for (final row in ReportContent.recordRows(snapshot, english: english)) pw.TableRow(
            children: [for (final value in row) pw.Padding(padding: const pw.EdgeInsets.all(4),
              child: pw.Text(value, style: pw.TextStyle(font: regular, fontSize: 8)))],
          )]),
      ],
      _section(t('الاعتماد والتوقيع','Review and signatures'),[pw.Text('${t('معدّ التقرير: ','Prepared by: ')}${snapshot.preparer ?? user?.name ?? t('النظام','System')}',style:pw.TextStyle(font:regular,fontSize:9)),pw.Text(t('المراجع: ____________________','Reviewer: ____________________'),style:pw.TextStyle(font:regular,fontSize:9)),pw.Text(snapshot.reviewer == null ? t('المعتمد: ____________________    التاريخ: __________','Approved by: ____________________    Date: __________') : '${t('المعتمد','Approved by')}: ${snapshot.reviewer}    ${snapshot.approvalTime ?? ''}',style:pw.TextStyle(font:regular,fontSize:9))]),
    ];
  }
  pw.Widget header(pw.Context context) => reportLetterhead(cycle: projectName, municipality: municipalityName, council: councilName, regular: regular, bold: bold, english: english, municipalityLogo: municipalityLogo, councilLogo: councilLogo, unicefLogo: unicefLogo);
  pw.Widget footer(pw.Context context)=>pw.Container(padding:const pw.EdgeInsets.only(top:5),decoration:const pw.BoxDecoration(border:pw.Border(top:pw.BorderSide(color:PdfColors.grey300))),child:pw.Row(children:[pw.Expanded(child:pw.Text('${t('صادر عن: ','Issued by: ')}${snapshot.preparer ?? user?.name ?? t('النظام','System')}',style:pw.TextStyle(font:regular,fontSize:7))),pw.Text(t('صفحة ${context.pageNumber} من ${context.pagesCount}','Page ${context.pageNumber} of ${context.pagesCount}'),style:pw.TextStyle(font:bold,fontSize:7))]));
  pw.MultiPage page()=>pw.MultiPage(maxPages:500,pageFormat:PdfPageFormat.a4,margin:const pw.EdgeInsets.fromLTRB(28,32,28,32),textDirection:english ? pw.TextDirection.ltr : pw.TextDirection.rtl,header:header,footer:footer,theme:pw.ThemeData.withFont(base:regular,bold:bold),build:(_)=>build());
}
