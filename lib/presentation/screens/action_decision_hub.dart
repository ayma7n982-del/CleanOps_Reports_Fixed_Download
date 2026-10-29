import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/config_service.dart';
import '../../core/services/decision_analytics.dart';
import '../../core/services/decision_hub_service.dart';
import '../../core/services/decision_pdf_export.dart';
import '../widgets/decision_charts.dart';
import 'supply_chain_dashboard.dart';

class ActionDecisionHubEntry extends StatelessWidget {
  const ActionDecisionHubEntry({super.key});
  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    if (!DecisionHubService.allowed(user)) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(width: double.infinity, child: FilledButton.icon(
        icon: const Icon(Icons.insights_rounded),
        label: const Padding(padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('لوحة الإجراءات والقرارات', textAlign: TextAlign.center)),
        onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
          builder: (_) => const ActionDecisionHubScreen())))));
  }
}

class ActionDecisionHubScreen extends StatefulWidget {
  const ActionDecisionHubScreen({super.key});
  @override
  State<ActionDecisionHubScreen> createState() => _ActionDecisionHubScreenState();
}
class _ActionDecisionHubScreenState extends State<ActionDecisionHubScreen> {
  DecisionHubService? _service;
  final _cycle = TextEditingController();
  bool _exporting = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.watch<AuthService>().currentUser;
    final shift = context.watch<ConfigService>().shift;
    if (_service?.user == user && _service?.shiftText == shift) return;
    _service?.dispose();
    _service = DecisionHubService.allowed(user) ?
        (DecisionHubService(user: user!, shiftText: shift)..start()) : null;
  }
  @override
  void dispose() { _service?.dispose(); _cycle.dispose(); super.dispose(); }

  Future<void> _perform(Future<bool> Function() action) async {
    try {
      final confirmed = await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(confirmed
        ? 'تم حفظ القرار وتأكيد صدوره من الخادم. التنفيذ الميداني يتابعه المشرف.'
        : 'القرار قيد المزامنة أو مسجل سابقًا؛ راجع حالته في السجل.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('لم يُعتمد القرار: $error')));
    }
  }
  Future<void> _export(DecisionHubService service, {String section = 'all'}) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await exportDecisionPdf(data: service.analytics, decisions: service.decisions,
        coordinator: service.user.name, section: section, plans: service.plans,
        quality: service.complete ? 'بيانات مكتملة من الخادم' :
            'بيانات جزئية أو مخزنة محليًا؛ لا تصلح لإثبات غياب النشاط');
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تصدير الملخص: $error')));
    } finally { if (mounted) setState(() => _exporting = false); }
  }
  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service == null) return const Directionality(textDirection: TextDirection.rtl,
      child: Scaffold(body: Center(child: Text('هذه اللوحة متاحة للإدارة L2–L4 فقط.'))));
    return Directionality(textDirection: TextDirection.rtl,
      child: DefaultTabController(length: 3, child: AnimatedBuilder(
        animation: service,
        builder: (context, _) {
          final data = service.analytics;
          return Scaffold(
            appBar: AppBar(title: const Text('لوحة الإجراءات والقرارات الذكية')),
            body: SafeArea(child: NestedScrollView(
              headerSliverBuilder: (context, inner) => [
                SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF06463D), Color(0xFF119A85)]),
                        borderRadius: BorderRadius.circular(24)),
                      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('CLEANOPS  •  DECISION INTELLIGENCE',
                          style: TextStyle(color: Color(0xFF81E7D0), fontSize: 11)),
                        SizedBox(height: 10),
                        Text('من الرصد إلى القرار', style: TextStyle(color: Colors.white,
                          fontSize: 26, fontWeight: FontWeight.w900)),
                        SizedBox(height: 6),
                        Text('قرار واضح • مسؤول محدد • أثر قابل للمتابعة',
                          style: TextStyle(color: Colors.white)),
                      ])),
                    const SizedBox(height: 8),
                    Text('الدورة: ${data.cycleName} • الوردية: ${data.shift.label}\n'
                      'التاريخ المحلي: ${data.shift.start.toIso8601String().substring(0, 10)}'),
                    if (!service.loaded) const LinearProgressIndicator(),
                    if (!service.complete) _notice(service.localOnly
                      ? 'بيانات مخزنة محليًا؛ تُزامن القرارات تلقائيًا عند الاتصال.'
                      : 'البيانات غير مكتملة. لا نستنتج ركودًا أو فائضًا من سجلات ناقصة.'),
                    if (service.capped.isNotEmpty) _notice(
                      'تجاوزت بعض البيانات حد القراءة الآمنة. تم تعليق الاستنتاجات والاعتماد الاستراتيجي.'),
                    if (service.errors.isNotEmpty) _notice(
                      'تعذر تحميل بعض مصادر البيانات. تحقق من الاتصال والصلاحيات المنشورة.'),
                    if (service.writeErrors.isNotEmpty) _notice(
                      'رفض الخادم ${service.writeErrors.length} قرارًا. لم تُنفذ هذه الطلبات؛ '
                      'يمكن إعادة المحاولة بعد معالجة الاتصال أو الصلاحيات.'),
                    DecisionExecutiveCharts(data: data),
                    FilledButton.icon(
                      icon: const Icon(Icons.analytics_outlined),
                      label: const Padding(padding: EdgeInsets.all(12),
                        child: Text('تحليل سلسلة الإمداد • الاتجاهات والمقارنات')),
                      onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
                        builder: (_) => SupplyChainDashboard(service: service)))),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(onPressed: _exporting ? null : () => _export(service),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(_exporting ? 'جارٍ إعداد PDF...' :
                        'تصدير ملخص القرارات والرسوم البيانية PDF')),
                    ExpansionTile(title: const Text('كفاءة المجموعات وترحيل النفايات'),
                      subtitle: const Text('الأخضر: المنجز • الأزرق: الهدف المسجّل'),
                      children: data.groups.isEmpty ? [const ListTile(
                        title: Text('لا توجد مجموعات نشطة في نطاقك.'))] :
                        data.groups.map((g) => Padding(padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Text(g.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            if (g.tons != null) DecisionComparisonBar(actual: g.tons!,
                              target: g.targetTons, label: g.estimatedTons ?
                                'الكمية التقديرية للرحلات المكتملة' : 'الوزن المسجّل',
                              unit: 'طن')
                            else const Text('لا توجد أوزان صالحة بوحدة الطن للرحلات المكتملة.'),
                            DecisionComparisonBar(actual: g.completedTrips.length.toDouble(),
                              target: g.targetTrips, label: 'الرحلات المكتملة', unit: 'نقلة'),
                          ]))).toList()),
                  ]))),
                SliverPersistentHeader(pinned: true, delegate: _DecisionTabs(
                  Theme.of(context).scaffoldBackgroundColor)),
              ],
              body: TabBarView(children: [
                _live(service, data), _strategic(service, data), _health(service, data),
              ]),
            )),
          );
        })));
  }
  Widget _sectionExport(DecisionHubService s, String section, String title) =>
    OutlinedButton.icon(onPressed: _exporting ? null : () => _export(s, section: section),
      icon: const Icon(Icons.picture_as_pdf_outlined), label: Text(title));
  Widget _notice(String text) => Card(color: Colors.amber.withOpacity(.12),
    child: Padding(padding: const EdgeInsets.all(12), child: Text(text)));
  Widget _list(List<Widget> children) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: children);
  Widget _card(String title, String text, List<Widget> actions,
      {Color color = Colors.cyan}) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: color.withOpacity(.45))),
    child: Padding(padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: color)),
        const SizedBox(height: 8), Text(text), const SizedBox(height: 12),
        ...actions,
      ])));
  Widget _issueButton(DecisionHubService s, {required String label, required String kind,
      required String groupId, required String owner, required String title,
      required String body, String targetId = '', DecisionRow details = const {}}) {
    final id = s.key(kind, targetId.isEmpty ? groupId : targetId);
    final saved = s.existing(id);
    final blocked = saved != null || s.submitted.contains(id) ||
        context.read<ConfigService>().stageFrozen;
    final state = saved?['_pending'] == true ? 'بانتظار المزامنة' :
        saved?['status'] == 'completed' ? 'تم التنفيذ الميداني' :
        saved?['status'] == 'acknowledged' ? 'استلمه المشرف' : 'صدر القرار';
    return FilledButton.tonalIcon(
      onPressed: blocked ? null : () => _perform(() => s.issue(kind: kind, title: title,
        body: body, groupId: groupId, owner: owner, targetId: targetId, details: details)),
      icon: const Icon(Icons.bolt_rounded),
      label: Text(blocked ? (saved == null ? 'بانتظار تأكيد المزامنة' : state) : label,
        textAlign: TextAlign.center));
  }
  DecisionGroup? _containerGroup(DecisionAnalytics a, DecisionRow c) {
    for (final g in a.groups) {
      if ([g.id, g.row['number'], g.row['name'], g.row['groupName']]
          .contains(c['groupId'])) return g;
    }
    return null;
  }

  Widget _live(DecisionHubService s, DecisionAnalytics a) => _list([
    _sectionExport(s, 'operations', 'تقرير الميدان والرسوم PDF'),
    _card('التعميم الإداري العاجل',
      s.user.role == 'municipality_coordinator' ?
        'يظهر لجميع مشرفي بلديتك لمدة 24 ساعة.' : 'يظهر لجميع مشرفي المجموعات لمدة 24 ساعة.',
      [FilledButton.icon(icon: const Icon(Icons.campaign_outlined),
        onPressed: context.read<ConfigService>().stageFrozen ? null : () => _broadcast(s),
        label: const Text('إرسال تعميم طارئ للجميع'))]),
    if (s.complete)
      ...a.groups.where((g) => g.stagnant).map((g) => _card('تنبيه الركود الميداني • ${g.name}',
        'لا توجد نقلات مسجلة منذ بداية الوردية النشطة بعد مرور ساعة. '
        'القرار يطلب التحقق والدعم ولا يغيّر تخصيص الكارات تلقائيًا.',
        [_issueButton(s, label: 'توجيه كارة مساندة / تنبيه المشرف', kind: 'stagnation',
          groupId: g.id, owner: g.owner, title: 'تحقق ميداني ودعم عاجل',
          body: 'لا توجد نقلات مسجلة لهذه الوردية. تحقق من الحالة ونسّق كارة مساندة.')],
        color: Colors.orange)),
    ...a.fullContainers.map((c) {
      final g = _containerGroup(a, c);
      return _card('تنبيه الحاويات الحرجة • ${c['locationName'] ?? c['id']}',
        'الحالة المسجلة: ممتلئة. تُسجل أولوية التفريغ ووقت إصدار التكليف.',
        [if (g != null) _issueButton(s, label: 'توجيه طاقم تفريغ فوري',
          kind: 'collection', groupId: g.id, owner: g.owner,
          targetId: '${c['id']}_${c['fullSince'] ?? 'legacy'}', title: 'تفريغ حاوية بأولوية عاجلة',
          body: 'كلّف طاقم التفريغ للموقع ${c['locationName'] ?? c['id']} وأكد إتمامه.',
          details: {'containerId': c['id'], 'locationName': c['locationName'] ?? ''})
        else const Text('يلزم ربط الحاوية بمجموعة نشطة قبل إرسال طاقم.')],
        color: Colors.redAccent);
    }),
    if (s.complete) ...a.groups.where((g) => (g.absenceRate ?? 0) > .2).map((g) =>
      _card('معالجة الغياب الطارئ • ${g.name}',
        'الغياب المثبت ${decisionPercent(g.absenceRate)} • '
        'غير المسجّل ${g.unknown}. لا نعتبر غير المسجّل غائبًا.',
        [FilledButton.tonal(onPressed: () => _coverage(s, a, g),
          child: const Text('دمج مؤقت / تكليف بديل'))], color: Colors.orange)),
    if (a.fullContainers.isEmpty && (!s.complete || !a.groups.any((g) =>
        g.stagnant || (g.absenceRate ?? 0) > .2)))
      _notice(s.complete ? 'لا توجد تنبيهات ميدانية حسب السجلات الحالية.' :
        'ستظهر التنبيهات المؤكدة بعد اكتمال البيانات.'),
    ExpansionTile(title: Text('سجل القرارات • ${s.decisions.length}'),
      children: (s.decisions.toList()..sort((a, b) =>
        '${b['createdAt'] ?? ''}'.compareTo('${a['createdAt'] ?? ''}')))
        .map((d) => ListTile(
          title: Text('${d['title']}'),
          subtitle: Text('${d['coordinatorName']} • ${d['createdAt'] ?? ''}\n'
            '${d['_pending'] == true ? 'بانتظار المزامنة' : d['status']}'),
          isThreeLine: true)).toList()),
  ]);

  Future<void> _broadcast(DecisionHubService s) async {
    final text = TextEditingController();
    final result = await showDialog<String>(context: context, builder: (c) =>
      Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
        title: const Text('صياغة التعميم الطارئ'),
        content: TextField(controller: text, maxLength: 1000, minLines: 3,
          maxLines: 5, decoration: const InputDecoration(labelText: 'نص التعميم')),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(onPressed: () {
            if (text.text.trim().isNotEmpty) Navigator.pop(c, text.text.trim());
          }, child: const Text('إرسال التعميم'))])));
    text.dispose();
    if (result == null || !mounted) return;
    await _perform(() => s.issue(kind: 'broadcast', title: 'تعميم إداري عاجل',
      body: result, groupId: '', owner: s.user.role == 'municipality_coordinator'
          ? s.user.id : '', targetId: 'broadcast_${DateTime.now().microsecondsSinceEpoch}'));
  }
  Future<void> _coverage(DecisionHubService s, DecisionAnalytics a, DecisionGroup group) async {
    final adjacent = group.row['adjacentGroupIds'];
    final nearby = a.groups.where((g) => g.id != group.id && g.owner == group.owner &&
        adjacent is List && adjacent.contains(g.id)).toList();
    final reserves = s.operations.where((w) => w['_entity'] == 'worker' &&
        decisionActive(w) && w['isReserve'] == true && s.reserveAvailable('${w['id']}') &&
        w['municipalityCoordinatorId'] == group.owner).toList();
    String? choice;
    final selected = await showDialog<String>(context: context, builder: (c) =>
      Directionality(textDirection: TextDirection.rtl, child: StatefulBuilder(
        builder: (c, update) => AlertDialog(title: const Text('تغطية مؤقتة لهذه الوردية'),
          content: SizedBox(width: 420, child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('يحفظ التكليف المؤقت دون تغيير المجموعة الأصلية للعامل.'),
              ...reserves.map((w) => RadioListTile<String>(
                value: 'worker:${w['id']}', groupValue: choice,
                title: Text('تكليف الاحتياط: ${w['name'] ?? w['id']}'),
                onChanged: (v) => update(() => choice = v))),
              ...nearby.map((g) => RadioListTile<String>(
                value: 'group:${g.id}', groupValue: choice,
                title: Text('دمج تغطية مع ${g.name}'),
                onChanged: (v) => update(() => choice = v))),
              if (reserves.isEmpty && nearby.isEmpty) const Text(
                'لا يوجد احتياط مسجل أو مجموعات مجاورة موثقة في نطاق البلدية.'),
            ]))),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
            FilledButton(onPressed: choice == null ? null :
              () => Navigator.pop(c, choice), child: const Text('اعتماد التكليف'))]))));
    if (selected == null || !mounted) return;
    final split = selected.indexOf(':');
    final type = selected.substring(0, split), id = selected.substring(split + 1);
    final selectedWorker = type == 'worker' ?
        reserves.firstWhere((w) => '${w['id']}' == id) : <String, dynamic>{};
    final name = type == 'worker' ? '${selectedWorker['name'] ?? id}' :
        nearby.firstWhere((g) => g.id == id).name;
    await _perform(() => s.issue(kind: 'temporary_coverage', groupId: group.id,
      owner: group.owner, title: 'تغطية غياب مؤقتة',
      body: type == 'worker' ? 'تكليف العامل الاحتياطي $name لتغطية هذه الوردية.' :
        'تغطية مشتركة مؤقتة مع المجموعة $name لهذه الوردية.',
      details: {'assignmentType': type, 'assignmentId': id,
        if (type == 'worker') 'workerName': selectedWorker['name'] ?? '',
        if (type == 'worker') 'workerJob': selectedWorker['job'] ?? '',
        'validUntil': a.shift.end.toIso8601String()}));
  }

  Widget _strategic(DecisionHubService s, DecisionAnalytics a) {
    final next = _cycle.text.trim();
    final recommendations = a.recommendations;
    final approved = s.decisions.where((d) => d['status'] == 'approved' &&
        d['targetCycleId'] == next).toList();
    final planId = s.key('plan', 'master', cycleId: next);
    return _list([
      _sectionExport(s, 'strategic', 'تقرير الخطة والتوصيات PDF'),
      _notice('محرك قواعد محلي: يعرض سبب التوصية ونسبة استيفاء شروطها. '
        'الحضور التاريخي مبني على الكشوف المسجّلة؛ لا تُفترض نسب للسجلات المفقودة. '
        'لا يغيّر الاعتماد عمال الدورة الحالية.'),
      TextField(controller: _cycle, maxLength: 80,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'اسم أو معرّف الدورة القادمة',
          hintText: 'مثال: الدورة 12')),
      Text('نافذة التحليل: ${a.historyStart.toIso8601String().substring(0, 10)} '
        'حتى ${a.now.toIso8601String().substring(0, 10)}'),
      const SizedBox(height: 12),
      ...recommendations.map((r) {
        final id = s.key(r.kind, r.group.id, cycleId: next);
        final existing = s.existing(id);
        final disabled = next.isEmpty || !s.complete || existing != null ||
          s.submitted.contains(id) || context.read<ConfigService>().stageFrozen;
        return _card('${r.group.name} • ${r.title}',
          '${r.reason}\nالعمال الحاليون: ${r.group.workers.length} • '
          'كارات مسجلة مع عمال: ${r.group.cartWorkers}',
          [DecisionComparisonBar(actual: (r.kind == 'increase_carts' ?
              r.group.cartWorkers : r.group.workers.length).toDouble(),
            target: ((r.kind == 'increase_carts' ? r.group.cartWorkers :
              r.group.workers.length) + r.delta).toDouble(),
            label: 'الحالي / المقترح', unit: r.kind == 'increase_carts' ? 'كارة' : 'عامل'),
           LinearProgressIndicator(value: r.confidence,
             semanticsLabel: 'اكتمال أدلة التوصية'),
           Text('استيفاء شروط القاعدة: ${decisionPercent(r.confidence)}'),
           FilledButton(onPressed: disabled ? null :
             () => _approveRecommendation(s, r, next),
             child: Text(existing != null ? 'التوصية معتمدة' :
               r.kind == 'increase_carts' ? 'اعتماد دعم الكارات' :
               r.kind == 'reallocate_surplus' ? 'اعتماد تدوير الفائض' :
               'اعتماد زيادة العمال للدورة القادمة'))],
          color: r.kind == 'expand_manpower' ? Colors.redAccent :
            r.kind == 'increase_carts' ? Colors.orange : Colors.green);
      }),
      if (recommendations.isEmpty) _notice(
        'بيانات غير كافية لتوصيات موثوقة، أو لا توجد حالات تستوفي القواعد. '
        'يلزم ثلاثة أيام حضور على الأقل، وتاريخ امتلاء أو مدد رحلات موثقة.'),
      FilledButton.icon(icon: const Icon(Icons.save_outlined),
        onPressed: next.isEmpty || approved.isEmpty || !s.complete ||
            s.existing(planId) != null || s.submitted.contains(planId) ||
            context.read<ConfigService>().stageFrozen ? null :
          () => _perform(() => s.savePlan(next, approved)),
        label: Text(s.existing(planId) != null ? 'تم حفظ الخطة الاستراتيجية' :
          'حفظ واعتماد الخطة الاستراتيجية للدورة القادمة')),
      Text('توصيات معتمدة لهذه الدورة: ${approved.length} • '
        'خطط محفوظة: ${s.plans.length}'),
    ]);
  }

  Future<void> _approveRecommendation(DecisionHubService s,
      DecisionRecommendation recommendation, String cycle) async {
    String destination = '';
    if (recommendation.kind == 'reallocate_surplus') {
      final targets = s.analytics.recommendations.where((r) =>
        r.kind == 'expand_manpower' && r.group.id != recommendation.group.id &&
        (s.user.role != 'municipality_coordinator' || r.group.owner == s.user.id)).toList();
      if (targets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('لا توجد مجموعة احتياج مؤهلة لاستقبال الفائض حاليًا.')));
        return;
      }
      String? chosen;
      final selected = await showDialog<String>(context: context, builder: (c) =>
        StatefulBuilder(builder: (c, update) => AlertDialog(
          title: const Text('اختر منطقة الاحتياج المستفيدة'),
          content: DropdownButtonFormField<String>(value: chosen, isExpanded: true,
            items: targets.map((r) => DropdownMenuItem(value: r.group.id,
              child: Text(r.group.name))).toList(),
            onChanged: (v) => update(() => chosen = v)),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
            FilledButton(onPressed: chosen == null ? null : () => Navigator.pop(c, chosen),
              child: const Text('اعتماد تدوير الفائض'))])));
      if (selected == null || !mounted) return;
      destination = selected;
    }
    await _perform(() => s.approve(recommendation, cycle, destinationGroupId: destination));
  }

  Widget _health(DecisionHubService s, DecisionAnalytics a) => _list([
    _sectionExport(s, 'health', 'تقرير الصحة والبيئة والنسب PDF'),
    ...a.healthHazards.map((c) {
      final g = _containerGroup(a, c);
      return _card('خطر صحي وبيئي عالي - أولوية قصوى',
        '${c['locationName'] ?? c['id']} • ممتلئة منذ أكثر من 12 ساعة موثقة.',
        [if (g != null) _issueButton(s, label: 'إخلاء طارئ وتطهير الموقع',
          kind: 'health', groupId: g.id, owner: g.owner,
          targetId: '${c['id']}_${c['fullSince'] ?? 'legacy'}', title: 'إخلاء وتطهير عاجل',
          body: 'أخلِ الحاوية ${c['locationName'] ?? c['id']} وطهّر الموقع '
            'مع مراعاة معدات الوقاية، ثم وثّق التنفيذ.',
          details: {'containerId': c['id'], 'fullSince': c['fullSince']})
        else const Text('اربط الحاوية بمجموعة لاستلام التكليف.')],
        color: const Color(0xFFB3263E));
    }),
    if (a.fullContainers.any((c) => c['fullSince'] == null)) _notice(
      'بعض الحاويات الممتلئة لا تملك وقت بدء امتلاء موثقًا؛ '
      'تظهر للتفريغ العاجل دون الجزم بتجاوز 12 ساعة.'),
    ...a.groups.map((g) => _card('السلامة المهنية • ${g.name}',
      'التزام عناصر PPE في النقلات • غياب مرضي مصنف: ${decisionPercent(g.sicknessRate)}\n'
      'غياب التصنيف المرضي لا يثبت خلو المجموعة من المرض.',
      [Center(child: DecisionRing(value: g.ppeRate, label: 'التزام الوقاية',
        color: decisionAttendanceColor(g.ppeRate))),
       _issueButton(s, label: 'طلب تزويد معدات وقاية PPE للمجموعة',
         kind: 'ppe', groupId: g.id, owner: g.owner,
         title: 'طلب معدات وقاية', body: 'راجع مخزون البوت والقفازات والكمامات '
           'والقبعات والصديريات ونسّق تزويد المجموعة.')], color: Colors.teal)),
    ...a.dumpsites.where((d) => (decisionNumber(d['fillPercentage']) ?? -1) >= 85)
      .map((d) {
        final alternatives = a.dumpsites.where((x) => x['isActive'] == true && x['id'] != d['id'] &&
          decisionNumber(x['fillPercentage']) != null &&
          decisionNumber(x['fillPercentage'])! < 85 &&
          (decisionNumber(x['capacity']) ?? 0) > 0).toList()
          ..sort((x, y) => decisionNumber(x['fillPercentage'])!
            .compareTo(decisionNumber(y['fillPercentage'])!));
        return _card('منع الفيضان البيئي • ${d['nameAr'] ?? d['name'] ?? d['id']}',
          'امتلاء ${d['fillPercentage']}% • '
          '${alternatives.isEmpty ? 'لا يوجد مكب بديل نشط بسعة آمنة مسجلة.' :
            'البديل الأقل امتلاء: ${alternatives.first['nameAr'] ?? alternatives.first['name']}'}',
          [FilledButton.tonal(onPressed: alternatives.isEmpty ? null :
              () => _redirect(s, a, d, alternatives),
            child: const Text('تحويل مسار المجموعات للمكب البديل + طلب آليات تسوية'))],
          color: Colors.redAccent);
      }),
    if (a.healthHazards.isEmpty) _notice('لا توجد حاويات تجاوز امتلاؤها 12 ساعة موثقة.'),
  ]);

  Future<void> _redirect(DecisionHubService s, DecisionAnalytics a,
      DecisionRow source, List<DecisionRow> alternatives) async {
    // Each routing directive is scoped to one actual group. This keeps L2
    // isolated, allows a named recipient and avoids changing historical trips.
    String? groupId, alternativeId = '${alternatives.first['id']}';
    final approved = await showDialog<bool>(context: context, builder: (c) =>
      StatefulBuilder(builder: (c, update) => Directionality(textDirection: TextDirection.rtl,
        child: AlertDialog(title: const Text('توجيه مسار آمن'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(value: groupId, isExpanded: true,
              decoration: const InputDecoration(labelText: 'المجموعة المستلمة'),
              items: a.groups.map((g) => DropdownMenuItem(value: g.id,
                child: Text(g.name))).toList(),
              onChanged: (v) => update(() => groupId = v)),
            DropdownButtonFormField<String>(value: alternativeId, isExpanded: true,
              decoration: const InputDecoration(labelText: 'المكب البديل'),
              items: alternatives.map((d) => DropdownMenuItem(value: '${d['id']}',
                child: Text('${d['nameAr'] ?? d['name']}'))).toList(),
              onChanged: (v) => update(() => alternativeId = v)),
            const Text('يسري 24 ساعة على النقلات الجديدة. يتضمن طلب آليات التسوية '
              'ولا يغيّر سعة المكب أو النقلات السابقة.'),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
            FilledButton(onPressed: groupId == null || alternativeId == null ? null :
              () => Navigator.pop(c, true), child: const Text('إصدار التوجيه'))]))));
    if (approved != true || !mounted) return;
    final group = a.groups.firstWhere((g) => g.id == groupId);
    final alternate = alternatives.firstWhere((d) => d['id'] == alternativeId);
    await _perform(() => s.issue(kind: 'dumpsite_redirect',
      title: 'تحويل مسار وطلب آليات تسوية',
      body: 'تحويل النقلات الجديدة من ${source['nameAr'] ?? source['name']} '
        'إلى ${alternate['nameAr'] ?? alternate['name']}. '
        'نسّق آليات التسوية للمكب الممتلئ وأكد الاستلام.',
      groupId: group.id, owner: group.owner, targetId: '${source['id']}_${group.id}',
      details: {'sourceId': source['id'], 'sourceName': source['nameAr'] ?? source['name'],
        'alternativeId': alternate['id'],
        'alternativeName': alternate['nameAr'] ?? alternate['name'],
        'requestLeveling': true}));
  }
}

class _DecisionTabs extends SliverPersistentHeaderDelegate {
  final Color color;
  _DecisionTabs(this.color);
  @override
  double get minExtent => 58;
  @override
  double get maxExtent => 58;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
    Material(color: color, elevation: 2,
      child: const TabBar(isScrollable: true, tabs: [
        Tab(text: 'قرارات الميدان الفورية'),
        Tab(text: 'التخطيط الاستراتيجي للدورة القادمة'),
        Tab(text: 'القرارات الصحية والبيئية'),
      ]));
  @override
  bool shouldRebuild(covariant _DecisionTabs old) => old.color != color;
}

