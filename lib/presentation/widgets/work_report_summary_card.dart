import 'package:flutter/material.dart';

import '../../core/services/work_report_summary.dart';
import '../../core/localization.dart';

class WorkReportSummaryCard extends StatelessWidget {
  final WorkReportSummary summary;
  final String? sourceError;
  const WorkReportSummaryCard({
    super.key,
    required this.summary,
    this.sourceError,
  });
  @override
  Widget build(BuildContext context) {
    final s = summary;
    final counts = summary.counts;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppText(
              'ملخص ذكي من السجلات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            AppText(
              s.serverConfirmed && !s.hasPendingSources
                  ? 'المصدر مؤكد من الخادم • الأعداد تتحدث تلقائيًا'
                  : 'بيانات محلية أو بانتظار المزامنة • يمكن حفظ مسودة',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metric(
                  context,
                  'الحضور',
                  counts['attendance'],
                  s.attendanceRecords,
                ),
                _metric(
                  context,
                  'الغياب دون إجازات',
                  counts['absence'],
                  s.attendanceRecords,
                ),
                _metric(
                  context,
                  'إجازة / إذن خاص',
                  counts['specialLeave'],
                  s.attendanceRecords,
                ),
                _metric(
                  context,
                  'إجازة مرضية',
                  counts['sickLeave'],
                  s.attendanceRecords,
                ),
                _metric(
                  context,
                  'بعذر / مهمة خارجية',
                  counts['otherAbsence'],
                  s.attendanceRecords,
                ),
                _metric(
                  context,
                  'نقلات مكتملة',
                  counts['trips'],
                  s.tripRecords,
                ),
              ],
            ),
            const SizedBox(height: 8),
            AppText(
              'نقلات جارية: ${s.activeTrips} • ملغاة: ${s.cancelledTrips} (لا تدخل في الإنجاز)',
            ),
            const AppText(
              'اضغط على المؤشر لمراجعة سجلاته. كل عامل يُحتسب مرة واحدة في الوردية. النقلة تتبع يوم بدئها.',
            ),
            if (sourceError != null)
              AppText(
                sourceError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            for (final issue in s.issues)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: AppText(
                  '• $issue',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _metric(
    BuildContext context,
    String label,
    dynamic count,
    List<Map<String, dynamic>> rows,
  ) => ActionChip(
    avatar: const Icon(Icons.fact_check_outlined, size: 18),
    label: AppText('$label: ${count ?? 'غير مكتمل'}'),
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheet).height * .65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: AppText(
                  'مصدر $label',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? const Center(
                        child: AppText(
                          'لا توجد سجلات متاحة ضمن الاختيار الحالي.',
                        ),
                      )
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (_, i) {
                          final r = rows[i];
                          return ListTile(
                            title: AppText(
                              '${r['workerName'] ?? r['title'] ?? r['id']}',
                            ),
                            subtitle: AppText(
                              '${_status('${r['status']}')} • ${r['shift'] ?? ''}\n${r['id']}',
                            ),
                            trailing: r['_pendingSource'] == true
                                ? const Icon(Icons.cloud_upload_outlined)
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  static String _status(String s) =>
      const {
        'present': 'حاضر',
        'absent': 'غائب',
        'leave': 'إجازة',
        'permission': 'إذن خاص',
        'excused_absence': 'غياب بعذر',
        'unexcused_absence': 'غياب دون عذر',
        'external_task': 'مهمة خارجية',
        'sick_leave': 'إجازة مرضية',
        'special_leave': 'إجازة خاصة',
        'completed': 'مكتملة',
        'done': 'مكتملة',
        'closed': 'مغلقة',
        'cancelled': 'ملغاة',
        'canceled': 'ملغاة',
        'rejected': 'مرفوضة',
        'in_progress': 'قيد التنفيذ',
        'pending': 'بانتظار التنفيذ',
        'delayed': 'متأخرة',
        'late': 'متأخرة',
        'active': 'جارية',
        'scheduled': 'مجدولة',
        'assigned': 'مسندة',
        'open': 'مفتوحة',
        'overdue': 'متجاوزة للوقت',
      }[s] ??
      'حالة تحتاج مراجعة';
}
