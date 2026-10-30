import 'package:flutter/material.dart';
import '../../core/services/decision_hub_service.dart';
import '../../core/services/decision_pdf_export.dart';
import '../../core/services/supply_chain_analytics.dart';
import '../widgets/decision_charts.dart';
import '../widgets/supply_chain_charts.dart';
import '../widgets/app_design.dart';
import '../../core/constants/app_constants.dart';

class SupplyChainDashboard extends StatefulWidget {
  final DecisionHubService service;
  const SupplyChainDashboard({super.key, required this.service});
  @override
  State<SupplyChainDashboard> createState() => _SupplyChainDashboardState();
}
class _SupplyChainDashboardState extends State<SupplyChainDashboard> {
  int days = 7;
  String? groupId;
  bool pie = false, exporting = false;
  Widget card(String title, List<Widget> children) => Card(
    color: Colors.white, margin: const EdgeInsets.only(bottom: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Padding(padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
          color: EcoPalette.ink)), const SizedBox(height: 12), ...children])));
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl,
    child: AnimatedBuilder(animation: widget.service, builder: (context, _) {
      final s = widget.service, data = s.analytics;
      final selected = data.groups.any((g) => g.id == groupId) ? groupId : null;
      final d = SupplyChainAnalytics.from(data, days: days, groupId: selected);
      final quality = s.complete ? 'بيانات مكتملة من الخادم' : 'بيانات جزئية أو محلية؛ المقارنات غير مؤكدة';
      return Scaffold(backgroundColor: cleanOpsBg,
        appBar: AppBar(title: const Text('تحليل سلسلة الإمداد')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Container(padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(colors: [Color(0xFF06463D), Color(0xFF119A85)], begin: Alignment.topRight, end: Alignment.bottomLeft)),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('SUPPLY CHAIN DASHBOARD', style: TextStyle(color: Color(0xFF8AE0CA))),
              SizedBox(height: 8), Text('الجمع • النقل • الاستيعاب',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
              Text('اتجاهات ومقارنات من سجلات التشغيل', style: TextStyle(color: Colors.white)),
            ])),
          const SizedBox(height: 14),
          card('نطاق التحليل', [
            Wrap(spacing: 8, children: [for (final n in [7, 14, 30])
              ChoiceChip(label: Text('$n يومًا'), selected: days == n,
                onSelected: (_) => setState(() => days = n))]),
            DropdownButton<String>(isExpanded: true, value: selected ?? '',
              items: [const DropdownMenuItem(value: '', child: Text('جميع المجموعات')),
                ...data.groups.map((g) => DropdownMenuItem(value: g.id,
                  child: Text(g.name, overflow: TextOverflow.ellipsis)))],
              onChanged: (v) => setState(() => groupId = v == '' ? null : v)),
            Text('${d.period}\nأيام مكتملة حتى نهاية أمس. المقارنة بفترة سابقة مساوية.'),
            Text(quality),
            if (!d.currentCovered) const Text('الفترة الحالية تتجاوز بداية السجل المتاح؛ الأعداد المعروضة جزئية.'),
            if (!d.historyCovered) const Text('بداية السجل المتاح لا تغطي الفترة السابقة كاملة؛ مقارنة التطور غير متاحة.'),
            if (d.groups.isEmpty) const Text('لا توجد مجموعات متاحة ضمن نطاقك.'),
          ]),
          card('مؤشرات الأداء والمقارنة', [
            Text('النقلات المسجلة: ${d.recorded} • المكتملة: ${d.completed}'),
            Text('نسبة الإكمال: ${decisionPercent(d.completion)}'),
            Text('التغير عن الفترة السابقة: ${s.complete ? decisionPercent(d.change) : 'غير مؤكد'}'),
            Text('مجموع الأوزان المعروفة: ${d.tons?.toStringAsFixed(2) ?? 'غير متاح'} طن'),
            Text('تغطية الأوزان: ${d.weighed} من ${d.completed} نقلة مكتملة؛ قد تشمل كميات تقديرية.'),
          ]),
          card('اتجاه النقلات اليومي • Line Charts', [
            const Text('الأخضر: المكتملة • الأزرق: المسجلة. المحور من الأقدم يسارًا إلى الأحدث يمينًا.'),
            SupplyChart(series: supplyTrendSeries(d), kind: 'line', description: 'اتجاه النقلات اليومي'),
            for (final p in d.trend) Text('${p.day.day}/${p.day.month}: ${p.completed} مكتملة / ${p.recorded} مسجلة'),
          ]),
          card('مقارنة الفترتين • Clustered Bar Charts', [
            const Text('الأخضر: الحالية • الأزرق: السابقة • الوحدة: نقلة مكتملة'),
            SupplyChart(series: supplyClusterSeries(d), kind: 'bar', description: 'مقارنة المجموعات بين فترتين'),
            for (final g in d.groups) Text('${g.name}: ${g.current} / ${d.historyCovered ? g.previous : 'غير متاح'}'),
          ]),
          card('توزيع الأوزان المعروفة • Bar Charts', [
            SupplyChart(series: [d.groups.map((g) => g.tons).toList()], kind: 'bar', description: 'أطنان المجموعات المعروفة'),
            for (final g in d.groups) Text('${g.name}: ${g.weighed == 0 ? 'وزن غير متاح' : '${g.tons.toStringAsFixed(2)} طن'}'),
          ]),
          card('حالة الحاويات الآن • Pie & Donut', [
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('عرض دائري مصمت'),
              value: pie, onChanged: (v) => setState(() => pie = v)),
            SupplyChart(series: [d.distribution.values.map((n) => n.toDouble()).toList()],
              kind: pie ? 'pie' : 'donut', description: 'توزيع حالة الحاويات الحالية'),
            for (final e in d.distribution.entries) Text('${const {'empty':'فارغة','full':'ممتلئة','partial':'جزئية','unknown':'غير معروفة'}[e.key]}: ${e.value} '
              '(${decisionPercent(d.distribution.values.fold<int>(0, (a,b) => a+b) == 0 ? null : e.value / d.distribution.values.fold<int>(0, (a,b) => a+b))})'),
            const Text('لقطة حالية؛ لا تمثل توزيع الحاويات خلال الفترة التاريخية.'),
          ]),
          FilledButton.icon(icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(exporting ? 'جارٍ إعداد التقرير...' : 'تصدير تحليل سلسلة الإمداد PDF'),
            onPressed: exporting ? null : () async {
              setState(() => exporting = true);
              try {
                await exportDecisionPdf(data: data, decisions: s.decisions,
                  coordinator: s.user.name, quality: quality, section: 'supply', supply: d);
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر التصدير: $e')));
              } finally { if (mounted) setState(() => exporting = false); }
            }),
        ]));
    }));
}
