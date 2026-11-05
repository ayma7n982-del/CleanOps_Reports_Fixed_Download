import '../widgets/app_navigation_bar.dart';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';

import '../../core/localization.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/data_service.dart';
import '../../core/services/daily_work_report_pdf.dart';
import '../../core/services/pdf_file_saver.dart';
import 'work_entry_form_screen.dart';
import '../../core/services/work_report_sources.dart';
import '../../core/services/work_report_summary.dart';
import '../widgets/work_report_summary_card.dart';

class WorkReportsDashboard extends StatefulWidget {
  const WorkReportsDashboard({super.key});
  @override
  State<WorkReportsDashboard> createState() => _WorkReportsDashboardState();
}

class _WorkReportsDashboardState extends State<WorkReportsDashboard> {
  final Set<String> _submitting = {};
  final Set<String> _printing = {};
  DateTime startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime endDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final arabic = context.watch<LocaleController>().isArabic;
    final user = context.watch<AuthService>().currentUser;
    final all = context
        .watch<DataService>()
        .operations
        .where(
          (e) =>
              (e['_entity'] == 'work_report' ||
                  (e['_entity'] == 'report' &&
                      e['reportKind'] == 'work_report')) &&
              e['isDeleted'] != true,
        )
        .toList();
    final visible =
        all.where((e) {
          if (user == null || !_inSelectedPeriod(e)) return false;
          final status = '${e['status'] ?? 'draft'}';
          if (user.role == 'group_supervisor' || user.role == 'worker') {
            return '${e['groupId'] ?? e['groupName'] ?? ''}' ==
                    '${user.groupId ?? ''}' &&
                (e['reportedBy'] == user.id || user.role == 'group_supervisor');
          }
          if (user.role == 'municipality_coordinator') {
            final scope = user.scope.trim();
            final owner =
                '${e['municipalityCoordinatorId'] ?? e['requestedBy'] ?? ''}';
            final municipality =
                '${e['municipalityName'] ?? e['municipality'] ?? e['municipalityId'] ?? ''}';
            return owner == user.id ||
                (scope.isNotEmpty &&
                    scope != 'all' &&
                    scope != 'assigned_only' &&
                    municipality == scope);
          }
          if (user.role == 'jsc_coordinator') {
            final scope = user.scope.trim();
            final council =
                '${e['councilName'] ?? e['councilId'] ?? e['municipalityName'] ?? ''}';
            return scope.isNotEmpty &&
                scope != 'all' &&
                scope != 'assigned_only' &&
                council == scope &&
                ['submitted', 'approved', 'needs_edits'].contains(status);
          }
          if (user.role == 'donor_manager')
            return status == 'approved' || status == 'closed';
          return false;
        }).toList()..sort(
          (a, b) => '${b['workDate'] ?? b['createdAt'] ?? ''}'.compareTo(
            '${a['workDate'] ?? a['createdAt'] ?? ''}',
          ),
        );
    final todayReports = visible;
    final trips = todayReports.fold<int>(
      0,
      (n, e) => n + ((e['trips'] as num?)?.toInt() ?? 0),
    );
    final specialLeave = todayReports.fold<int>(
      0,
      (n, e) => n + ((e['specialLeave'] as num?)?.toInt() ?? 0),
    );
    final sickLeave = todayReports.fold<int>(
      0,
      (n, e) => n + ((e['sickLeave'] as num?)?.toInt() ?? 0),
    );
    final otherAbsence = todayReports.fold<int>(
      0,
      (n, e) => n + ((e['otherAbsence'] as num?)?.toInt() ?? 0),
    );
    final present = todayReports.fold<int>(
      0,
      (n, e) => n + ((e['attendance'] as num?)?.toInt() ?? 0),
    );
    final absent = todayReports.fold<int>(
      0,
      (n, e) => n + ((e['absence'] as num?)?.toInt() ?? 0),
    );
    return Directionality(
      textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          bottom: const AppNavigationBar(),
          title: const AppText('لوحة تقارير العمل'),
          actions: [
            if (user?.role == 'group_supervisor' ||
                user?.role == 'municipality_coordinator')
              IconButton(
                tooltip: 'تسجيل تقرير',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WorkEntryFormScreen(),
                  ),
                ),
                icon: const Icon(Icons.add_circle_outline),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppText(
                      'الفترة الزمنية',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _dateButton('من', startDate, (d) {
                          if (d != null)
                            setState(() {
                              startDate = d;
                              if (endDate.isBefore(startDate))
                                endDate = startDate;
                            });
                        }),
                        _dateButton('إلى', endDate, (d) {
                          if (d != null)
                            setState(
                              () => endDate = d.isBefore(startDate)
                                  ? startDate
                                  : d,
                            );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppText(
                      'ملخص الفترة',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _kpi('تقارير الفترة', '${todayReports.length}'),
                        _kpi('النقلات', '$trips'),
                        _kpi('الحضور', '$present'),
                        _kpi('الغياب', '$absent'),
                        _kpi('إجازة خاصة', '$specialLeave'),
                        _kpi('إجازة مرضية', '$sickLeave'),
                        _kpi('أسباب أخرى', '$otherAbsence'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (visible.any(
              (r) =>
                  r['sourceSnapshot'] is Map &&
                  r['sourceSnapshot']['needsReview'] == true,
            ))
              const AppText(
                'بعض المسودات غير مكتملة؛ الأرقام المعروضة جزئية إلى حين مراجعة سجلات المصدر.',
              ),
            const SizedBox(height: 10),
            if (user?.role == 'group_supervisor' ||
                user?.role == 'municipality_coordinator')
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WorkEntryFormScreen(),
                  ),
                ),
                icon: const Icon(Icons.edit_note),
                label: const AppText('تسجيل تقرير مجموعة'),
              ),
            const SizedBox(height: 14),
            const AppText(
              'ملخص البلدية دون أسماء العمال',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            ..._municipalitySummary(visible),
            const SizedBox(height: 14),
            const AppText(
              'تقارير المجموعات الفعلية',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.all(18),
                child: AppText('لا توجد تقارير عمل مسجلة ضمن نطاق صلاحياتك.'),
              ),
            for (final e in visible)
              Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.assignment_outlined),
                  title: Text(
                    (e['groupName'] ?? 'مجموعة غير محددة').toString(),
                  ),
                  subtitle: Text(
                    '${e['workDate'] ?? e['createdAt'] ?? ''} • ${_status((e['status'] ?? 'draft').toString())}',
                  ),
                  trailing:
                      ((user?.role == 'group_supervisor' ||
                              user?.role == 'municipality_coordinator') &&
                          (e['status'] ?? 'draft').toString() == 'draft')
                      ? IconButton(
                          tooltip: 'مراجعة السجلات وإرسال التقرير',
                          icon: _submitting.contains('${e['id']}')
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_outlined),
                          onPressed: _submitting.contains('${e['id']}')
                              ? null
                              : () => _submitReport(context, e),
                        )
                      : null,
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    if (e['countsMode'] == 'operational_sources_v1') ...[
                      _line(
                        'مصدر الأعداد',
                        'مجمعة تلقائيًا • الوردية ${e['shift'] ?? ''}',
                      ),
                      _line(
                        'حالة الملخص',
                        e['sourceSnapshot'] is Map &&
                                e['sourceSnapshot']['needsReview'] == true
                            ? 'مسودة تحتاج استكمال السجلات والمزامنة'
                            : 'نسخة محفوظة من السجلات عند آخر مراجعة',
                      ),
                      const AppText(
                        'تُفحص أحدث سجلات المصدر قبل الإرسال للمراجعة. التقارير المرسلة تحتفظ بنسختها.',
                      ),
                    ],
                    _line('النقلات المكتملة', '${e['trips'] ?? 'غير مكتمل'}'),
                    _line(
                      'الحضور / الغياب',
                      '${e['attendance'] ?? 'غير مكتمل'} / ${e['absence'] ?? 'غير مكتمل'}',
                    ),
                    _line(
                      'الإجازات',
                      'خاصة ${e['specialLeave'] ?? '—'} • مرضية ${e['sickLeave'] ?? '—'} • أخرى ${e['otherAbsence'] ?? '—'}',
                    ),
                    _line('المهام', '${e['workTasks'] ?? '—'}'),
                    _line('حالة المكب', '${e['landfillStatus'] ?? '—'}'),
                    _line('حالة الحاويات', '${e['containerStatus'] ?? '—'}'),
                    _line('مواقع العمل', '${e['workLocations'] ?? '—'}'),
                    _line('العمل المكتمل', '${e['completedWork'] ?? '—'}'),
                    _line('المشكلات', '${e['problems'] ?? '—'}'),
                    _line('المقترحات', '${e['suggestions'] ?? '—'}'),
                    if (e['recordType'] == 'daily_work' &&
                        user?.can('reports', 'export') == true)
                      Wrap(spacing: 8, children: [
                        OutlinedButton.icon(
                          onPressed: _printing.contains('${e['id']}')
                              ? null : () => _outputPdf(e, preview: true),
                          icon: const Icon(Icons.preview_outlined),
                          label: const AppText('معاينة التقرير اليومي'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _printing.contains('${e['id']}')
                              ? null : () => _outputPdf(e, preview: false),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const AppText('تصدير PDF'),
                        ),
                      ]),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _inSelectedPeriod(Map<String, dynamic> report) {
    final raw = report['workDate'] ?? report['createdAt'] ?? report['date'];
    final date = raw is DateTime
        ? raw
        : raw is Timestamp
        ? raw.toDate()
        : DateTime.tryParse('$raw');
    if (date == null) return false;
    final from = DateTime(startDate.year, startDate.month, startDate.day);
    final until = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      23,
      59,
      59,
      999,
    );
    return !date.isBefore(from) && !date.isAfter(until);
  }

  Future<void> _outputPdf(Map<String, dynamic> report,
      {required bool preview}) async {
    final user = context.read<AuthService>().currentUser;
    if (user?.can('reports', 'export') != true) return;
    final id = '${report['id'] ?? ''}';
    if (id.isEmpty || _printing.contains(id)) return;
    setState(() => _printing.add(id));
    try {
      final bytes = await DailyWorkReportPdf.build(report);
      if (preview) {
        if (mounted) await Printing.layoutPdf(onLayout: (_) async => bytes);
      } else {
        final date = '${report['workDate'] ?? report['createdAt'] ?? ''}';
        final day = date.length >= 10 ? date.substring(0, 10).replaceAll('-', '') : 'undated';
        final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
        final path = await savePdfBytes(bytes, 'daily_work_${day}_$safeId.pdf');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(path == null ? 'تعذر حفظ PDF' : 'تم إنشاء PDF: $path')));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذر إنشاء تقرير العمل اليومي: $error')));
    } finally {
      if (mounted) setState(() => _printing.remove(id));
    }
  }

  Widget _dateButton(
    String label,
    DateTime value,
    ValueChanged<DateTime?> onPicked,
  ) => OutlinedButton.icon(
    onPressed: () async {
      final d = await showDatePicker(
        context: context,
        initialDate: value,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (d != null) onPicked(d);
    },
    icon: const Icon(Icons.calendar_month),
    label: Text(
      '$label: ${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
    ),
  );

  Future<void> _submitReport(
    BuildContext context,
    Map<String, dynamic> report,
  ) async {
    final user = context.read<AuthService>().currentUser;
    final data = context.read<DataService>();
    final id = '${report['id']}';
    if (user == null || _submitting.contains(id)) return;
    if ('${report['reportedBy'] ?? ''}' != user.id ||
        !const [
          'group_supervisor',
          'municipality_coordinator',
        ].contains(user.role)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('يرسل التقرير منشئه ضمن صلاحياته فقط.'),
        ),
      );
      return;
    }
    setState(() => _submitting.add(id));
    try {
      var updated = <String, dynamic>{...report};
      if (report['countsMode'] == 'operational_sources_v1') {
        final rows = await WorkReportSources.readConfirmed(
          data,
          '${report['groupId'] ?? ''}',
        );
        final day = WorkReportSummary.date(report['workDate']);
        if (day == null) throw StateError('تاريخ التقرير غير مكتمل.');
        final s = WorkReportSummary.build(
          records: rows,
          groupId: '${report['groupId'] ?? ''}',
          day: day,
          shift: '${report['shift'] ?? ''}',
          serverConfirmed: true,
        );
        if (!context.mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const AppText('مراجعة أعداد التقرير'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (report['sourceSnapshot'] is Map &&
                      report['sourceSnapshot']['fingerprint'] != s.fingerprint)
                    const AppText(
                      'تغيرت سجلات المصدر منذ حفظ المسودة. هذه الأعداد المحدثة التي ستُرسل.',
                    ),
                  WorkReportSummaryCard(summary: s),
                  if (!s.readyForSubmission)
                    const AppText(
                      'استكمل كشف المصدر وصحح التعارضات وانتظر المزامنة، ثم أعد الإرسال. مسودتك محفوظة.',
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const AppText('رجوع'),
              ),
              if (s.readyForSubmission)
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const AppText('إرسال الأعداد المراجعة'),
                ),
            ],
          ),
        );
        if (proceed != true || !context.mounted) return;
        final latest = WorkReportSummary.build(
          records: await WorkReportSources.readConfirmed(data, s.groupId),
          groupId: s.groupId,
          day: day,
          shift: s.shift,
          serverConfirmed: true,
        );
        if (!latest.readyForSubmission || latest.fingerprint != s.fingerprint)
          throw StateError(
            'تغيرت سجلات المصدر أثناء المراجعة؛ أعد فتح ملخص الإرسال.',
          );
        updated = {
          ...updated,
          ...latest.counts,
          'sourceSnapshot': latest.snapshot(),
        };
      }
      updated.addAll({
        'status': 'submitted',
        'submittedAt': DateTime.now().toIso8601String(),
        'submittedBy': user.id,
      });
      await data.enqueue('work_report', 'update', updated);
      await data.writeAudit(
        actorId: user.id,
        operation: 'WORK_REPORT_SUBMITTED',
        targetId: id,
        before: {'status': report['status'] ?? 'draft'},
        after: {'status': 'submitted', 'countsMode': report['countsMode']},
      );
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: AppText(
              'أضيف إرسال التقرير إلى المزامنة؛ تأكيد الخادم يظهر بعد نجاحها.',
            ),
          ),
        );
    } catch (error) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: AppText('تعذر إرسال التقرير: $error')),
        );
    } finally {
      if (mounted) setState(() => _submitting.remove(id));
    }
  }

  static List<Widget> _municipalitySummary(List<Map<String, dynamic>> reports) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final report in reports) {
      final municipality = '${report['municipalityName'] ?? ''}'.trim();
      final label = municipality.isEmpty || municipality == 'assigned_only'
          ? 'غير محددة'
          : municipality;
      (grouped[label] ??= []).add(report);
    }
    if (grouped.isEmpty)
      return [
        const Padding(
          padding: EdgeInsets.all(10),
          child: AppText('لا توجد بيانات كافية للملخص البلدي.'),
        ),
      ];
    return grouped.entries.map((entry) {
      final rows = entry.value;
      int sum(String key) =>
          rows.fold<int>(0, (n, e) => n + ((e[key] as num?)?.toInt() ?? 0));
      return Card(
        child: ListTile(
          leading: const Icon(Icons.location_city_outlined),
          title: Text(entry.key),
          subtitle: Text(
            "تقارير: ${rows.length} • نقلات: ${sum('trips')} • حضور: ${sum('attendance')} • غياب: ${sum('absence')}\nإجازة خاصة: ${sum('specialLeave')} • مرضية: ${sum('sickLeave')} • أسباب أخرى: ${sum('otherAbsence')}",
          ),
          isThreeLine: true,
        ),
      );
    }).toList();
  }

  static Widget _kpi(String label, String value) => SizedBox(
    width: 135,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    ),
  );
  static Widget _line(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 105,
          child: Text(k, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Expanded(child: Text(v)),
      ],
    ),
  );
  static String _status(String s) => switch (s) {
    'approved' => 'معتمد',
    'submitted' => 'بانتظار المراجعة',
    'needs_edits' => 'بحاجة إلى تعديل',
    'closed' => 'مغلق',
    _ => 'مسودة',
  };
}
