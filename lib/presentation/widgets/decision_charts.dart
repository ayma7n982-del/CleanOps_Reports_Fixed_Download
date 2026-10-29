import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/services/decision_analytics.dart';

Color decisionAttendanceColor(double? v) => v == null ? Colors.blueGrey :
    v > .85 ? const Color(0xFF21BA88) :
    v >= .7 ? const Color(0xFFFFB347) : const Color(0xFFEF6262);
String decisionPercent(double? v) => v == null ? 'غير متاح' :
    '${(v * 100).toStringAsFixed(1)}%';

class DecisionRingPainter extends CustomPainter {
  final List<double> portions;
  final List<Color> colors;
  final double progress;
  final bool gauge;
  const DecisionRingPainter({required this.portions, required this.colors,
    this.progress = 1, this.gauge = false});
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 13;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 13;
    final start = gauge ? math.pi * .75 : -math.pi / 2;
    final sweep = gauge ? math.pi * 1.5 : math.pi * 2;
    canvas.drawArc(rect, start, sweep, false, paint..color = Colors.blueGrey.withOpacity(.18));
    var cursor = start;
    for (var i = 0; i < portions.length; i++) {
      final angle = portions[i].clamp(0.0, 1.0) * sweep * progress;
      canvas.drawArc(rect, cursor, angle, false, paint..color = colors[i % colors.length]);
      cursor += angle;
    }
    if (gauge) {
      final threshold = start + sweep * .85;
      final p = Offset(math.cos(threshold), math.sin(threshold));
      canvas.drawLine(center + p * (radius - 12), center + p * (radius + 12),
          Paint()..color = Colors.redAccent..strokeWidth = 3);
    }
  }
  @override
  bool shouldRepaint(covariant DecisionRingPainter old) =>
      old.progress != progress || old.gauge != gauge ||
      old.portions.toString() != portions.toString() || old.colors.toString() != colors.toString();
}

class DecisionRing extends StatelessWidget {
  final double? value;
  final List<double>? portions;
  final List<Color>? colors;
  final Color color;
  final bool gauge, animate;
  final String label;
  const DecisionRing({super.key, required this.value, required this.label,
    required this.color, this.portions, this.colors, this.gauge = false, this.animate = true});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: ${decisionPercent(value)}',
    child: SizedBox(width: 142, height: 142,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: animate ? 650 : 0),
        builder: (_, progress, __) => CustomPaint(
          painter: DecisionRingPainter(
            portions: portions ?? [value ?? 0], colors: colors ?? [color],
            progress: progress, gauge: gauge),
          child: Center(child: Text(decisionPercent(value),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: value == null ? 17 : 25,
              fontWeight: FontWeight.w800, color: color)))))));
}

class DecisionExecutiveCharts extends StatelessWidget {
  final DecisionAnalytics data;
  const DecisionExecutiveCharts({super.key, required this.data});
  Widget _card(String title, String subtitle, Widget chart) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: const EdgeInsets.all(14),
      child: Column(children: [
        Text(title, textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800)),
        chart,
        Text(subtitle, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12)),
      ])));
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final columns = constraints.maxWidth >= 920 ? 3 : constraints.maxWidth >= 560 ? 2 : 1;
    final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
    final full = data.fullContainers.length;
    final partial = data.containers.where((c) => c['status'] == 'partial').length;
    final count = data.containers.length;
    final rest = data.workers - data.present - data.absent;
    return Wrap(spacing: 10, runSpacing: 10, children: [
      SizedBox(width: width, child: _card('نسبة الالتزام بالحضور العام',
        'حاضر ${data.present} • غياب مثبت ${data.absent}\n'
        'غير مسجّل ${data.unknown} • الإجمالي ${data.workers}\n'
        'الرمادي يشمل الإجازة والإذن والحالات غير المسجّلة',
        DecisionRing(value: data.attendanceRate, label: 'الالتزام بالحضور',
          color: decisionAttendanceColor(data.attendanceRate),
          portions: data.workers == 0 ? [] :
            [data.present / data.workers, data.absent / data.workers, rest / data.workers],
          colors: [decisionAttendanceColor(data.attendanceRate), Colors.redAccent, Colors.blueGrey]))),
      SizedBox(width: width, child: _card('مؤشر حالة الحاويات الميدانية',
        'نسبة الفارغ من جميع الحاويات\n'
        'ممتلئة $full • جزئية $partial • الإجمالي $count',
        DecisionRing(value: data.emptyRate, label: 'الحاويات الفارغة',
          color: const Color(0xFF21BA88),
          portions: count == 0 ? [] :
            [data.emptyRate ?? 0, full / count, partial / count],
          colors: const [Color(0xFF21BA88), Color(0xFFEF6262), Color(0xFFFFB347)]))),
      SizedBox(width: width, child: _card('نسبة استيعاب المكبات المركزية',
        'امتلاء مرجّح بالسعة المسجلة\nالعلامة الحمراء: حد الخطر 85%',
        DecisionRing(value: data.dumpsiteRate, label: 'استيعاب المكبات',
          gauge: true, color: (data.dumpsiteRate ?? 0) >= .85 ?
            Colors.redAccent : Colors.cyan))),
    ]);
  });
}

class DecisionComparisonPainter extends CustomPainter {
  final double actual, target, progress;
  const DecisionComparisonPainter(this.actual, this.target, this.progress);
  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = math.max(math.max(actual, target), 1.0);
    final paint = Paint();
    for (final y in [0.0, 16.0]) {
      canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y, size.width, 10), const Radius.circular(5)),
        paint..color = Colors.blueGrey.withOpacity(.15));
    }
    canvas.drawRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * (1 - actual / maxValue * progress), 0,
        size.width * actual / maxValue * progress, 10), const Radius.circular(5)),
      paint..color = const Color(0xFF22C5AA));
    canvas.drawRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * (1 - target / maxValue * progress), 16,
        size.width * target / maxValue * progress, 10), const Radius.circular(5)),
      paint..color = const Color(0xFF5595EE));
  }
  @override
  bool shouldRepaint(covariant DecisionComparisonPainter old) =>
      old.actual != actual || old.target != target || old.progress != progress;
}

class DecisionComparisonBar extends StatelessWidget {
  final double actual;
  final double? target;
  final String label, unit;
  const DecisionComparisonBar({super.key, required this.actual,
    required this.target, required this.label, required this.unit});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label، الفعلي $actual، الهدف ${target ?? 'غير مسجّل'} $unit',
    child: Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('$label: ${actual.toStringAsFixed(1)} $unit / '
          '${target == null ? 'الهدف غير مسجّل' : 'هدف ${target!.toStringAsFixed(1)} $unit'}'),
        const SizedBox(height: 6),
        TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 650),
          builder: (_, progress, __) => SizedBox(height: 27,
            child: CustomPaint(painter: DecisionComparisonPainter(
              actual, target ?? 0, progress)))),
      ])));
}
