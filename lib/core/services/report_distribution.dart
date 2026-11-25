import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Map<String, int> reportCounts(Iterable<String> labels) {
  final result = <String, int>{};
  for (final label in labels) {
    result.update(label, (value) => value + 1, ifAbsent: () => 1);
  }
  return result;
}

/// A common 0–100% scale, with the numerator and denominator beside every bar.
pw.Widget distributionChart(String title, Map<String, int> counts, pw.Font regular, pw.Font bold,
    {bool english = false}) {
  final total = counts.values.fold<int>(0, (sum, value) => sum + value);
  final items = counts.entries.toList();
  final rows = items.take(6).toList();
  if (items.length > 6) {
    rows.add(MapEntry(english ? 'Other' : 'بقية التصنيفات',
        items.skip(6).fold<int>(0, (sum, e) => sum + e.value)));
  }
  return pw.Container(margin: const pw.EdgeInsets.symmetric(vertical: 5),
    padding: const pw.EdgeInsets.all(7), color: PdfColors.grey100,
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 10, color: PdfColors.teal900)),
      if (total == 0) pw.Text(english ? 'No observations' : 'لا توجد مشاهدات لحساب النسبة',
          style: pw.TextStyle(font: regular, fontSize: 8)),
      if (total > 0) for (final e in rows) pw.Padding(padding: const pw.EdgeInsets.only(top: 3),
        child: pw.Row(children: [
          pw.Expanded(flex: 2, child: pw.Text(e.key, style: pw.TextStyle(font: regular, fontSize: 8))),
          pw.Expanded(flex: 3, child: pw.Row(children: [
            if (e.value > 0) pw.Expanded(flex: e.value, child: pw.Container(height: 6, color: PdfColors.teal700)),
            if (total > e.value) pw.Expanded(flex: total - e.value, child: pw.Container(height: 6, color: PdfColors.blueGrey100)),
          ])),
          pw.SizedBox(width: 6),
          pw.Text('${(100 * e.value / total).toStringAsFixed(1)}%   (${e.value}/$total)',
              textDirection: pw.TextDirection.ltr, style: pw.TextStyle(font: bold, fontSize: 8)),
        ])),
    ]));
}
