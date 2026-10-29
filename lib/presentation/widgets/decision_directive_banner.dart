import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/config_service.dart';
import '../../core/services/decision_pdf_export.dart';

/// In-app live supervisor notification; no push service or Cloud Functions.
class DecisionDirectiveBanner extends StatefulWidget {
  final VoidCallback? onCoverageChanged;
  const DecisionDirectiveBanner({super.key, this.onCoverageChanged});
  @override
  State<DecisionDirectiveBanner> createState() => _DecisionDirectiveBannerState();
}
class _DecisionDirectiveBannerState extends State<DecisionDirectiveBanner> {
  final _subscriptions = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
  final _sources = <String, List<Map<String, dynamic>>>{};
  final _pending = <String>{};
  String? _binding;
  String? _error;
  String _coverageKey = '';
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_coverageKey.isNotEmpty) {
        widget.onCoverageChanged?.call();
        final anyActive = _sources.values.expand((x) => x).any((r) =>
          r['kind'] == 'temporary_coverage' && r['expiresAt'] is Timestamp &&
          (r['expiresAt'] as Timestamp).toDate().isAfter(DateTime.now()));
        if (!anyActive) _coverageKey = '';
      }
    });
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final u = context.watch<AuthService>().currentUser;
    final binding = '${u?.id}:${u?.groupId}:${u?.municipalityCoordinatorId}:${u?.isActive}';
    if (_binding == binding) return;
    for (final s in _subscriptions) { s.cancel(); }
    _subscriptions.clear(); _sources.clear(); _pending.clear();
    _binding = binding;
    if (u == null || u.role != 'group_supervisor' || !u.isActive) return;
    final db = FirebaseFirestore.instance.collection('strategic_decisions');
    final queries = <String, Query<Map<String, dynamic>>>{
      if ((u.groupId ?? '').isNotEmpty)
        'group': db.where('groupId', isEqualTo: u.groupId),
      if ((u.groupId ?? '').isNotEmpty)
        'secondary': db.where('additionalGroupId', isEqualTo: u.groupId)
          .where('kind', isEqualTo: 'temporary_coverage'),
      'global': db.where('scopeKey', isEqualTo: 'global').where('kind', isEqualTo: 'broadcast'),
      if ((u.municipalityCoordinatorId ?? '').isNotEmpty)
        'municipality': db.where('scopeKey',
          isEqualTo: 'municipality:${u.municipalityCoordinatorId}')
          .where('kind', isEqualTo: 'broadcast'),
    };
    for (final q in queries.entries) {
      _subscriptions.add(q.value.where('expiresAt',
        isGreaterThan: Timestamp.fromDate(DateTime.now())).limit(200).snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
          if (!mounted || _binding != binding) return;
          setState(() {
            _error = snapshot.docs.length == 200 ? 'سجل التوجيهات كبير؛ اطلب مراجعته من المنسق.' : null;
            _sources[q.key] = snapshot.docs.map((d) => <String, dynamic>{
              ...d.data(), 'id': d.id, '_pending': d.metadata.hasPendingWrites}).toList();
          });
          final coverage = _sources.values.expand((x) => x)
              .where((r) => r['kind'] == 'temporary_coverage')
              .map((r) => '${r['id']}:${r['expiresAt']}').toList()..sort();
          final key = coverage.join('|');
          if (key != _coverageKey) {
            _coverageKey = key;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _binding == binding) widget.onCoverageChanged?.call();
            });
          }
        }, onError: (Object e) {
          if (mounted && _binding == binding) setState(() =>
            _error = 'تعذر تحميل التوجيهات الإدارية؛ تحقق من الاتصال والصلاحيات.');
        }));
    }
  }
  Future<void> _update(Map<String, dynamic> row, bool complete) async {
    final user = context.read<AuthService>().currentUser;
    if (user == null || _pending.contains(row['id'])) return;
    String? note;
    if (complete) {
      final text = TextEditingController();
      note = await showDialog<String>(context: context, builder: (c) => AlertDialog(
        title: const Text('توثيق تنفيذ القرار'),
        content: TextField(controller: text, minLines: 2, maxLines: 4, maxLength: 1000,
          decoration: const InputDecoration(labelText: 'إثبات التنفيذ (10 أحرف على الأقل)')),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(onPressed: () {
            if (text.text.trim().length >= 10) Navigator.pop(c, text.text.trim());
          }, child: const Text('توثيق التنفيذ'))]));
      text.dispose();
      if (note == null || !mounted) return;
    }
    final id = '${row['id']}';
    setState(() => _pending.add(id));
    try {
      final future = FirebaseFirestore.instance.collection('strategic_decisions').doc(id).update(
        complete ? {'status': 'completed', 'completedBy': user.id,
          'completedAt': FieldValue.serverTimestamp(), 'completionNote': note} :
        {'status': 'acknowledged', 'acknowledgedBy': user.id,
          'acknowledgedAt': FieldValue.serverTimestamp()});
      final done = await future.then((_) => true, onError: (Object e, StackTrace stack) {
        if (mounted) setState(() { _pending.remove(id); _error = 'رفض الخادم تحديث القرار: $e'; });
        Error.throwWithStackTrace(e, stack);
      }).timeout(const Duration(seconds: 3), onTimeout: () => false);
      if (mounted) {
        if (done) setState(() => _pending.remove(id));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          done ? 'أكد الخادم تحديث حالة القرار.' : 'التحديث محفوظ للمزامنة التلقائية.')));
      }
    } catch (e) {
      if (mounted) setState(() { _pending.remove(id); _error = 'لم يُعتمد التحديث: $e'; });
    }
  }
  @override
  void dispose() {
    _timer?.cancel();
    for (final s in _subscriptions) { s.cancel(); }
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    if (user?.role != 'group_supervisor' || user?.isActive != true) {
      return const SizedBox.shrink();
    }
    final unique = <String, Map<String, dynamic>>{};
    for (final row in _sources.values.expand((x) => x)) {
      final expiry = row['expiresAt'];
      if (row['status'] == 'approved' || row['status'] == 'completed' ||
          expiry is! Timestamp || !expiry.toDate().isAfter(DateTime.now())) continue;
      unique['${row['id']}'] = row;
    }
    final rows = unique.values.toList()..sort((a, b) {
      final x = a['createdAt'], y = b['createdAt'];
      return (y is Timestamp ? y.millisecondsSinceEpoch : 0)
        .compareTo(x is Timestamp ? x.millisecondsSinceEpoch : 0);
    });
    if (rows.isEmpty && _error == null) return const SizedBox.shrink();
    return Directionality(textDirection: TextDirection.rtl,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_error != null) Card(child: Padding(padding: const EdgeInsets.all(12),
          child: Text(_error!))),
        ...rows.map((row) => Card(
          color: row['priority'] == 'critical' ? Colors.red.withOpacity(.18) :
            Colors.orange.withOpacity(.12),
          child: Padding(padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${row['title']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6), Text('${row['body']}'),
              Text(decisionStatusLabel(row), style: const TextStyle(fontSize: 12)),
              if (row['kind'] != 'broadcast' && row['groupId'] == user?.groupId)
                FilledButton.tonal(
                  onPressed: _pending.contains(row['id']) || row['_pending'] == true ||
                    context.read<ConfigService>().stageFrozen ? null :
                    () => _update(row, row['status'] == 'acknowledged'),
                  child: Text(row['status'] == 'acknowledged' ?
                    'توثيق التنفيذ الميداني' : 'تأكيد استلام التوجيه')),
            ])))),
      ]));
  }
}
