import 'package:flutter/material.dart';
import '../../core/services/report_ratios.dart';

class ReportRatioPanel extends StatelessWidget {
  final List<ReportRatio> ratios;
  final bool english;
  const ReportRatioPanel({super.key, required this.ratios, required this.english});
  @override
  Widget build(BuildContext context) {
    final ordered = [...ratios.where((r) => r.value != null), ...ratios.where((r) => r.value == null)];
    Widget row(ReportRatio ratio) => ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Row(children: [
        Expanded(child: Text(ratio.label(english), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(ratio.points && ratio.value != null
              ? '${ratio.value! > 0 ? '+' : ''}${ratio.value!.toStringAsFixed(1)}'
              : ratio.display(english),
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900,
                  color: ratio.value == null ? Colors.blueGrey : const Color(0xFF087F78))),
          if (ratio.points) Text(english ? 'percentage points' : 'نقطة مئوية', style: const TextStyle(fontSize: 10)),
        ]),
      ]),
      subtitle: Text(ratio.basis(english), maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11)),
      children: [Padding(padding: const EdgeInsets.only(bottom: 12),
        child: Text(ratio.basis(english), style: const TextStyle(fontSize: 12)))],
    );
    return Material(color: Theme.of(context).colorScheme.surface, child: Container(padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(border: BorderDirectional(start: BorderSide(color: Color(0xFF087F78), width: 3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(english ? 'Ratios and performance indicators' : 'النسب ومؤشرات الأداء',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        Text(english ? 'Each rate includes its basis. Tap to read the full calculation.'
            : 'كل نسبة معها أساس حسابها. اضغط لقراءة التوضيح كاملًا.', style: const TextStyle(fontSize: 11)),
        for (final ratio in ordered.take(4)) row(ratio),
        if (ordered.length > 4) ExpansionTile(tilePadding: EdgeInsets.zero,
          title: Text(english ? 'More indicators (${ordered.length - 4})' : 'مؤشرات إضافية (${ordered.length - 4})'),
          children: [for (final ratio in ordered.skip(4)) row(ratio)]),
      ])));
  }
}
