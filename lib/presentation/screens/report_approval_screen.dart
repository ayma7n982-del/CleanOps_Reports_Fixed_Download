import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/core_models.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/data_service.dart';
import '../../core/services/report_service.dart';
import '../../core/localization.dart';
import '../widgets/app_navigation_bar.dart';

class ReportApprovalScreen extends StatefulWidget {
  const ReportApprovalScreen({super.key});

  static bool aggregate(Map<String, dynamic> r) =>
      (r['reportKind'] ?? r['_entity']) == 'report_approval';

  static bool canView(Map<String, dynamic> r, AppUser user) {
    if (r['isDeleted'] == true || !user.can('reports', 'view')) return false;
    if (!{'report','work_report','report_approval'}.contains(r['_entity'] ?? r['reportKind'])) return false;
    if (!{'work_report', 'report_approval'}
        .contains(r['reportKind'] ?? r['_entity'])) return false;
    final owner = r['requestedBy'] ?? r['reportedBy'];
    final scope = user.scope.trim();
    final named =
        scope.isNotEmpty && scope != 'all' && scope != 'assigned_only';
    switch (user.role) {
      case 'municipality_coordinator':
        return owner == user.id ||
            r['municipalityCoordinatorId'] == user.id ||
            (named &&
                [r['municipalityName'], r['municipality'], r['municipalityId']]
                    .contains(scope));
      case 'group_supervisor':
      case 'worker':
        return (user.groupId ?? '').isNotEmpty &&
            (r['groupId'] ?? r['groupName']) == user.groupId &&
            owner == user.id;
      case 'jsc_coordinator':
        return named &&
            (r['councilName'] ?? r['councilId'] ?? r['municipalityName']) ==
                scope;
      case 'donor_manager':
        return ['approved', 'closed'].contains(r['status']);
      default:
        return false;
    }
  }

  static bool canExport(
          Map<String, dynamic> r, AppUser user, DataService data) =>
      aggregate(r) &&
      canView(r, user) &&
      user.can('reports', 'export') &&
      ['municipality_coordinator', 'jsc_coordinator', 'donor_manager']
          .contains(user.role) &&
      ['approved', 'closed'].contains(r['status']) &&
      data.pendingReport('${r['id']}') == null;

  @override
  State<ReportApprovalScreen> createState() => _ReportApprovalState();
}

class _ReportApprovalState extends State<ReportApprovalScreen> {
  final busy = <String>{};
  String language = 'ar';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() async {
    final user = context.read<AuthService>().currentUser;
    if (user != null)
      await context.read<DataService>().refreshReportArchive(user);
  }

  static String _label(dynamic status) => switch (status) {
        'approved' => 'معتمد',
        'submitted' => 'مرسل للمراجعة',
        'needs_edits' => 'بحاجة إلى تعديل',
        'closed' => 'مغلق',
        _ => 'مسودة',
      };

  static String _summary(Map<String, dynamic> row) {
    final values = row['snapshot'] is Map ? row['snapshot'] as Map : row;
    final labels = {
      'trips':
          ReportApprovalScreen.aggregate(row) && row['reportType'] != 'work'
              ? 'النقلات المسجلة'
              : 'النقلات المكتملة',
      if (row['reportType'] != 'work') 'completedTrips': 'النقلات المكتملة',
      'attendance': 'الحضور',
      'absence': 'الغياب',
      'groups': 'المجموعات',
      'workers': 'العمال',
      'supervisors': 'المشرفون',
      'containers': 'الحاويات',
      'emergencies': 'الطوارئ',
    };
    return [
      for (final key in labels.keys)
        if (values[key] != null) '${labels[key]}: ${values[key]}'
    ].join('  •  ');
  }

  Future<String?> _note(String title, String summary) {
    var note = '';
    return showDialog<String>(
        context: context,
        builder: (dialog) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                    title: Text(title),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      if (summary.isNotEmpty) Text(summary),
                      TextField(
                          maxLength: 1000,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(labelText: title),
                          onChanged: (v) => update(() => note = v.trim())),
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: const Text('إلغاء')),
                      FilledButton(
                          onPressed: note.isEmpty
                              ? null
                              : () => Navigator.pop(dialog, note),
                          child: const Text('تأكيد')),
                    ])));
  }

  Future<void> _act(Map<String, dynamic> r, AppUser user, String action) async {
    final id = '${r['id']}';
    if (busy.contains(id)) return;
    setState(() => busy.add(id));
    final data = context.read<DataService>();
    try {
      final pending = data.pendingReport(id);
      if (action == 'dismiss' && pending?.reportError != null) {
        await data.dismissReportError(pending!);
        return;
      }
      if (pending != null) return;
      if (['PDF', 'Excel', 'CSV'].contains(action)) {
        if (!ReportApprovalScreen.canExport(r, user, data)) return;
        final snapshot = ReportArchive.read(r);
        final service = ReportService(data);
        final path = switch (action) {
          'PDF' => await service.exportOperationalPdf(
              snapshot: snapshot,
              user: user,
              languageCode: language,
              title: '${r['title'] ?? 'تقرير معتمد'}'),
          'Excel' => await service.exportOperationalExcel(
              snapshot: snapshot, user: user, languageCode: language),
          _ => await service.exportOperationalCsv(
              snapshot: snapshot, user: user, languageCode: language),
        };
        _message(path == null
            ? 'تعذر إنشاء الملف.'
            : 'تم إنشاء الملف من النسخة المعتمدة.');
        return;
      }
      final payload = <String, dynamic>{
        'id': id,
        'status': action,
        '_expectedRevision': r['revision'] ?? 0
      };
      if (action == 'needs_edits') {
        final reason = await _note('سبب إرجاع التقرير', _summary(r));
        if (reason == null || !mounted) return;
        payload['returnReason'] = reason;
      } else if (action == 'submitted') {
        if (user.role != 'municipality_coordinator' ||
            user.id != r['requestedBy'] ||
            !user.can('reports', 'create') ||
            r['status'] != 'needs_edits') return;
        final dates = RegExp(r'\d{4}-\d{2}-\d{2}')
            .allMatches('${r['period']}')
            .map((m) => m[0]!)
            .toList();
        DateTime? start =
            DateTime.tryParse('${r['periodStart'] ?? dates.firstOrNull}');
        DateTime? end =
            DateTime.tryParse('${r['periodEnd'] ?? dates.lastOrNull}');
        if (r['reportType'] == 'containers') {
          start ??= DateTime.now();
          end ??= start;
        }
        if (start == null || end == null)
          throw StateError('تعذرت قراءة الفترة الأصلية من التقرير.');
        final snapshot = await ReportService(data).load(
            user: user,
            reportType: r['reportType'],
            startDate: start,
            endDate: end,
            municipality: r['municipality'],
            group: r['group'],
            cycle: r['cycle'],
            search: r['search'] ?? '',
            containerStatus: r['containerStatus'] ?? 'all');
        if (!mounted) return;
        final captured = ReportArchive.submission(snapshot, offline: !data.online);
        final note = await _note(
            'توضيح التصحيح وإعادة الإرسال',
            'سبب الإرجاع: ${r['returnReason'] ?? 'غير مسجل'}\n'
                'الأعداد بعد إعادة القراءة: ${_summary({...r, ...captured})}');
        if (note == null || !mounted) return;
        payload.addAll({...captured, 'correctionNote': note});
      }
      if (!mounted || context.read<AuthService>().currentUser?.id != user.id)
        return;
      await data.enqueue(
          ReportApprovalScreen.aggregate(r) ? 'report_approval' : 'work_report',
          'update',
          payload);
      _message('حُفظ الإجراء للمزامنة. تظهر الحالة الجديدة بعد تأكيد الخادم.');
    } catch (e) {
      _message('تعذر إكمال الإجراء: $e');
    } finally {
      if (mounted) setState(() => busy.remove(id));
    }
  }

  void _message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final data = context.watch<DataService>();
    final rows = data.operations
        .where((r) => user != null && ReportApprovalScreen.canView(r, user))
        .toList()
      ..sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
    return Scaffold(
        appBar: AppBar(
            bottom: const AppNavigationBar(),
            title: const AppText('دورة اعتماد التقارير')),
        body: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
                padding: const EdgeInsets.all(12),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (rows.isNotEmpty) Card(child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('مسار الاعتماد', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      const Wrap(spacing: 6, children: [
                        Chip(label: Text('مسودة')), Chip(label: Text('مراجعة المجلس')),
                        Chip(label: Text('معتمد')), Chip(label: Text('مغلق')),
                      ]),
                    ]),
                  )),
                  if (rows.isEmpty)
                    const AppText('لا توجد تقارير ضمن نطاق حسابك.'),
                  if (user != null &&
                      rows.any(
                          (r) => ReportApprovalScreen.canExport(r, user, data)))
                    DropdownButton<String>(
                        value: language,
                        items: const [
                          DropdownMenuItem(
                              value: 'ar', child: Text('لغة التصدير: العربية')),
                          DropdownMenuItem(
                              value: 'en', child: Text('Export in English'))
                        ],
                        onChanged: (v) => setState(() => language = v ?? 'ar')),
                  if (user != null)
                    for (final r in rows) _card(r, user, data),
                ])));
  }

  Widget _card(Map<String, dynamic> r, AppUser user, DataService data) {
    final id = '${r['id']}';
    final pending = data.pendingReport(id);
    final aggregate = ReportApprovalScreen.aggregate(r);
    final enabled = !busy.contains(id) && pending == null;
    Widget button(String key, String label) => TextButton(
        onPressed: enabled ? () => _act(r, user, key) : null,
        child: Text(label));
    return Card(
        child: ExpansionTile(
            leading: Icon(pending != null
                ? Icons.cloud_upload_outlined
                : Icons.assignment_outlined),
            title: Text('${r['title'] ?? r['groupName'] ?? 'تقرير العمل'}'),
            subtitle: Text([
              if (pending == null)
                _label(r['status'])
              else if (pending.reportError != null)
                'رفض الخادم الإجراء'
              else
                'بانتظار تأكيد الخادم',
              '${r['period'] ?? r['workDate'] ?? r['createdAt'] ?? ''}'
            ].join(' • ')),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(_summary(r)),
          if (r['partialSource'] == true)
            const Text('المصدر جزئي. راجع الأرقام قبل الاعتماد.'),
          if (r['filterLabel'] != null) Text('${r['filterLabel']}'),
          if (r['returnReason'] != null)
            Text('سبب الإرجاع: ${r['returnReason']}'),
          if (r['correctionNote'] != null)
            Text('توضيح التصحيح: ${r['correctionNote']}'),
          if (pending?.reportError != null) ...[
            Text(pending!.reportError!),
            TextButton(
                onPressed:
                    busy.contains(id) ? null : () => _act(r, user, 'dismiss'),
                child: const Text('استعادة حالة الخادم')),
          ],
          Wrap(children: [
            if (user.role == 'jsc_coordinator' &&
                user.can('reports', 'approve') &&
                r['status'] == 'submitted') ...[
              button('approved', 'اعتماد المجلس'),
              button('needs_edits', 'إعادة للتعديل')
            ],
            if (user.role == 'donor_manager' &&
                user.can('reports', 'approve') &&
                r['status'] == 'approved')
              button('closed', 'إغلاق التقرير'),
            if (aggregate &&
                user.role == 'municipality_coordinator' &&
                user.can('reports', 'create') &&
                user.id == r['requestedBy'] &&
                r['status'] == 'needs_edits')
              button('submitted', 'مراجعة التصحيح وإعادة الإرسال'),
            if (ReportApprovalScreen.canExport(r, user, data))
              for (final format in ['PDF', 'Excel', 'CSV'])
                button(format, 'تصدير $format'),
          ])
        ]));
  }
}
