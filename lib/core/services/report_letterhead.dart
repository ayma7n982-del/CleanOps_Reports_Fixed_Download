import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Names come from the records included in the report, including aggregate scopes.
String reportNames(Iterable<String> values) {
  final names = values.map((name) => name.trim()).where((name) => name.isNotEmpty).toSet().toList()..sort();
  return names.join(' • ');
}

String reportField(Iterable<Map<String, dynamic>> records, List<String> keys) =>
    reportNames(records.map((row) => keys.map((key) => '${row[key] ?? ''}'.trim())
        .firstWhere((name) => name.isNotEmpty, orElse: () => '')));

pw.Widget reportLetterhead({required String cycle, required String municipality,
    required String council, required pw.Font regular, required pw.Font bold,
    bool english = false, pw.ImageProvider? municipalityLogo,
    pw.ImageProvider? councilLogo, pw.ImageProvider? unicefLogo}) {
  String value(String name) => name.trim().isNotEmpty ? name : (english ? 'Unspecified' : 'غير محدد');
  pw.Widget partner(String label, String name, pw.ImageProvider? logo) => pw.Expanded(
    child: pw.Row(children: [
      if (logo != null) pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          child: pw.Image(logo, width: 24, height: 24, fit: pw.BoxFit.contain)),
      pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(label, style: pw.TextStyle(font: regular, color: PdfColors.blueGrey700, fontSize: 8)),
        pw.Text(value(name), style: pw.TextStyle(font: bold, color: PdfColors.blueGrey900, fontSize: 10)),
      ])),
    ]));
  return pw.Directionality(textDirection: english ? pw.TextDirection.ltr : pw.TextDirection.rtl,
    child: pw.Container(margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: const pw.BoxDecoration(color: PdfColors.white,
          border: pw.Border(top: pw.BorderSide(color: PdfColors.teal900, width: 2.4), bottom: pw.BorderSide(color: PdfColors.amber800, width: .8))),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Text("${english ? 'Cycle' : 'اسم الدورة'}: ${value(cycle)}",
            style: pw.TextStyle(font: bold, fontSize: 16, color: PdfColors.teal900)),
        pw.SizedBox(height: 5),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          partner(english ? 'Municipality' : 'اسم البلدية', municipality, municipalityLogo),
          partner(english ? 'Services council' : 'مجلس الخدمات', council, councilLogo),
          partner(english ? 'Supporting institution' : 'الجهة الداعمة',
              english ? 'UNICEF' : 'مؤسسة اليونسيف', unicefLogo),
        ]),
      ])));
}
