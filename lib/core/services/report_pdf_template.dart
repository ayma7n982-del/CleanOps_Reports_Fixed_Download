import 'report_distribution.dart';
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

  pw.Widget ink(String value, {double size = 9, bool strong = false,
      PdfColor color = PdfColors.blueGrey900}) => pw.Text(value,
      style: pw.TextStyle(font: strong ? bold : regular, fontSize: size, color: color));

  pw.Widget section(String name) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 8, bottom: 3),
      child: ink(name, size: 11, strong: true, color: PdfColors.teal900));

  pw.Widget grid(List<String> headings, List<List<String>> rows, List<int> widths) {
    final columns = List.generate(widths.length, (i) => english ? i : widths.length - 1 - i);
    pw.Widget cell(String value, bool head) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
        child: ink(value, strong: head, size: head ? 8 : 8.5,
          color: head ? PdfColors.white : PdfColors.blueGrey900));
    return pw.Table(
      columnWidths: {for (var i = 0; i < widths.length; i++) i: pw.FlexColumnWidth(widths[columns[i]].toDouble())},
      border: pw.TableBorder(horizontalInside: const pw.BorderSide(color: PdfColors.grey300, width: .35)),
      children: [
        pw.TableRow(repeat: true, decoration: const pw.BoxDecoration(color: PdfColors.teal900),
            children: [for (final column in columns) cell(headings[column], true)]),
        for (var i = 0; i < rows.length; i++) pw.TableRow(
          decoration: pw.BoxDecoration(color: i.isOdd ? PdfColors.grey100 : PdfColors.white),
          children: [for (final column in columns) cell(rows[i][column], false)]),
      ]);
  }

  List<pw.Widget> build() {
    final metrics = ReportContent.metrics(snapshot);
    final ratios = ReportContent.ratios(snapshot);
    final breakdown = <List<String>>[];
    final groups = ReportContent.breakdowns(snapshot, english: english);
    for (final group in groups) {
      final sum = group.values.values.fold<int>(0, (a, b) => a + b);
      if (group.values.isEmpty) breakdown.add([group.title, t('لا توجد سجلات', 'No records'), '—', '—']);
      for (final entry in group.values.entries) {
        breakdown.add([group.title, entry.key, '${entry.value}',
          sum == 0 ? '—' : RatioMath.display(RatioMath.percent(entry.value, sum))]);
      }
    }
    final role = user?.role ?? 'donor_manager';
    final roleTitle = english ? (const {'donor_manager':'System Manager',
      'jsc_coordinator':'JSC Coordinator','municipality_coordinator':'Municipality Coordinator',
      'group_supervisor':'Group Supervisor','worker':'Worker'}[role] ?? role) : (roleNames[role] ?? role);
    return [
      ink(title, size: 20, strong: true, color: PdfColors.teal900),
      ink('${snapshot.periodLabel}   •   $roleTitle', size: 10),
      ink('${snapshot.reportId}   •   ${DateFormat('yyyy-MM-dd HH:mm').format(snapshot.generatedAt)}   •   ${snapshot.filterLabel(english: english)}', size: 8, color: PdfColors.blueGrey700),
      if (snapshot.legacyCounts != null) ink(t('ملخص النسخة القديمة المحفوظة', 'Stored legacy summary'), strong: true),
      if (snapshot.sourceMayBeIncomplete) ink(t('قد تكون البيانات جزئية؛ راجع المصدر قبل الاعتماد.',
          'Data may be partial; verify the source before approval.'), strong: true, color: PdfColors.orange900),
      section(t('النتائج الرئيسية', 'Key figures')),
      for (var offset = 0; offset < metrics.length; offset += 4)
        pw.Row(children: [for (final metric in metrics.skip(offset).take(4)) pw.Expanded(
          child: pw.Container(margin: const pw.EdgeInsets.all(1), padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            color: PdfColors.teal50, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              ink(metric.label(english), size: 8.5), ink(metric.value, strong: true, size: 15, color: PdfColors.teal900),
            ])))]),
      if (snapshot.tripsByDay.isNotEmpty)
        ink("${t('متوسط النقلات لكل يوم له سجل', 'Trips per recorded day')}: ${(snapshot.tripsByDay.values.fold<int>(0, (a,b) => a+b) / snapshot.tripsByDay.length).toStringAsFixed(1)}", strong: true),
      if (groups.isNotEmpty) distributionChart(groups.first.title, groups.first.values, regular, bold, english: english),
      if (snapshot.legacyCounts?['absence'] is num && snapshot.legacyCounts?['attendance'] is num)
        distributionChart(t('الحضور والغياب المؤرشف','Archived attendance'), {
          t('حضور','Present'): snapshot.attendance, t('غياب','Absent'): snapshot.absence}, regular, bold, english: english),
      if (ratios.isNotEmpty) ...[
        section(t('مؤشرات الأداء وأساس احتسابها', 'Performance indicators and calculation basis')),
        grid([t('المؤشر','Indicator'), t('القيمة','Value'), t('أساس الاحتساب','Basis')],
          [for (final ratio in ratios) [ratio.label(english), ratio.display(english), ratio.basis(english)]], [3,2,8]),
      ],
      if (breakdown.isNotEmpty) ...[
        section(t('التوزيع التفصيلي', 'Detailed distribution')),
        grid([t('المحور','Measure'),t('التصنيف','Category'),t('العدد','Count'),t('حصة المحور','Share of measure')],
          breakdown, [4,4,2,2]),
      ],
      if (snapshot.legacyCounts == null && (snapshot.reportType == 'containers' || snapshot.reportType == 'trips')) ...[
        section(t('السجلات المطابقة للفلاتر','Matching records')),
        grid([t('معرّف السجل','Record ID'), t('تفاصيل السجل','Details')],
          ReportContent.recordRows(snapshot, english: english), [2,5]),
      ],
      pw.SizedBox(height: 5),
      ink(t('تُحسب حصة كل تصنيف من مجموع محوره. عدد النقلات وحده لا يقيس كفاءة التشغيل.',
          'Each share uses the total for its measure. Trip counts alone do not measure efficiency.'), size: 8),
      section(t('المراجعة والاعتماد','Review and approval')),
      grid([t('معدّ التقرير','Prepared by'),t('المراجع','Reviewer'),t('المعتمد','Approved by'),t('تاريخ الاعتماد','Approval date')],
        [[snapshot.preparer ?? user?.name ?? t('النظام','System'), '____________',
          snapshot.reviewer ?? '____________', snapshot.approvalTime ?? '____________']], [3,3,3,3]),
    ];
  }
  pw.Widget header(pw.Context context) => reportLetterhead(cycle: projectName, municipality: municipalityName, council: councilName, regular: regular, bold: bold, english: english, municipalityLogo: municipalityLogo, councilLogo: councilLogo, unicefLogo: unicefLogo);
  pw.Widget footer(pw.Context context)=>pw.Container(padding:const pw.EdgeInsets.only(top:5),decoration:const pw.BoxDecoration(border:pw.Border(top:pw.BorderSide(color:PdfColors.grey300))),child:pw.Row(children:[pw.Expanded(child:pw.Text('${t('صادر عن: ','Issued by: ')}${snapshot.preparer ?? user?.name ?? t('النظام','System')}',style:pw.TextStyle(font:regular,fontSize:7))),pw.Text(t('صفحة ${context.pageNumber} من ${context.pagesCount}','Page ${context.pageNumber} of ${context.pagesCount}'),style:pw.TextStyle(font:bold,fontSize:7))]));
  pw.MultiPage page()=>pw.MultiPage(maxPages:500,pageFormat:PdfPageFormat.a4,margin:const pw.EdgeInsets.fromLTRB(28,32,28,32),textDirection:english ? pw.TextDirection.ltr : pw.TextDirection.rtl,header:header,footer:footer,theme:pw.ThemeData.withFont(base:regular,bold:bold),build:(_)=>build());
}
