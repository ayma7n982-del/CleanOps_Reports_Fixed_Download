import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/services/supply_chain_analytics.dart';

const supplyColors = [Color(0xFF008B78), Color(0xFF4285D4),
  Color(0xFFFFB347), Color(0xFF9AA8B5)];

/// Shared screen/PDF painter. Labels live outside the canvas for accessible RTL
/// and embedded vector Arabic text in PDF; no screenshot or scroll dependency.
class SupplyChartPainter extends CustomPainter {
  final List<List<double>> series;
  final String kind;
  final double progress;
  const SupplyChartPainter(this.series, this.kind, {this.progress = 1});
  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    final paint = Paint()..isAntiAlias = true;
    if (kind == 'pie' || kind == 'donut') {
      final values = series.first;
      final total = values.fold<double>(0, (a, b) => a + b);
      final center = size.center(Offset.zero);
      final radius = math.min(size.width, size.height) * .43;
      if (total <= 0) {
        canvas.drawCircle(center, radius, paint..color = const Color(0xFFE8EEF2));
      } else {
        var start = -math.pi / 2;
        for (var i = 0; i < values.length; i++) {
          final sweep = values[i] / total * math.pi * 2 * progress;
          canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start,
            sweep, true, paint..color = [supplyColors[0], const Color(0xFFEF6262),
              supplyColors[2], supplyColors[3]][i % 4]);
          start += sweep;
        }
      }
      if (kind == 'donut') canvas.drawCircle(center, radius * .62,
        paint..color = Colors.white);
      return;
    }
    final n = series.map((s) => s.length).fold<int>(0, math.max);
    if (n == 0) return;
    final maxValue = math.max(1.0, series.expand((s) => s)
      .fold<double>(0, math.max));
    final rect = Rect.fromLTWH(8, 8, math.max(1, size.width - 16),
      math.max(1, size.height - 20));
    paint..color = const Color(0xFFE3EBF0)..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = rect.bottom - rect.height * i / 4;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    }
    for (var s = 0; s < series.length; s++) {
      paint..color = supplyColors[s % supplyColors.length]..strokeWidth = 3;
      final path = Path();
      for (var i = 0; i < series[s].length; i++) {
        final y = rect.bottom - series[s][i] / maxValue * rect.height * progress;
        // Chronological axis runs left to right, even inside Arabic layouts.
        if (kind == 'line') {
          final x = rect.left + (n == 1 ? rect.width / 2 : i * rect.width / (n - 1));
          if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
          canvas.drawCircle(Offset(x, y), 3, paint..style = PaintingStyle.fill);
        } else {
          final slot = rect.width / n;
          final width = slot * .72 / series.length;
          final x = rect.left + i * slot + slot * .14 + s * width;
          canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTRB(x, y, x + width * .9, rect.bottom), const Radius.circular(3)),
            paint..style = PaintingStyle.fill);
        }
      }
      if (kind == 'line') canvas.drawPath(path, paint..style = PaintingStyle.stroke);
      paint.style = PaintingStyle.fill;
    }
  }
  @override
  bool shouldRepaint(covariant SupplyChartPainter old) =>
      old.series != series || old.kind != kind || old.progress != progress;
}

class SupplyChart extends StatelessWidget {
  final List<List<double>> series;
  final String kind, description;
  const SupplyChart({super.key, required this.series, required this.kind,
    required this.description});
  @override
  Widget build(BuildContext context) => Semantics(label: description,
    child: TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      builder: (_, value, __) => SizedBox(height: 185, width: double.infinity,
        child: CustomPaint(painter: SupplyChartPainter(series, kind,
          progress: MediaQuery.disableAnimationsOf(context) ? 1 : value)))));
}

List<List<double>> supplyTrendSeries(SupplyChainAnalytics d) => [
  d.trend.map((p) => p.completed.toDouble()).toList(),
  d.trend.map((p) => p.recorded.toDouble()).toList(),
];
List<List<double>> supplyClusterSeries(SupplyChainAnalytics d) => [
  d.groups.map((g) => g.current.toDouble()).toList(),
  if (d.historyCovered) d.groups.map((g) => g.previous.toDouble()).toList(),
];
