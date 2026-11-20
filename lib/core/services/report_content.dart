import 'report_service.dart';
import 'report_ratios.dart';

/// One report definition shared by the screen and its three export formats.
class ReportMetric {
  final String id, ar, en, value;
  const ReportMetric(this.id, this.ar, this.en, this.value);
  String label(bool english) => english ? en : ar;
}

class ReportBreakdown {
  final String title;
  final Map<String, int> values;
  const ReportBreakdown(this.title, this.values);
}

class ReportContent {
  static List<ReportRatio> ratios(ReportSnapshot s) {
    if (s.legacyCounts != null) return [];
    final result = <ReportRatio>[...s.ratioInsights];
    if (s.reportType != 'containers' && s.reportType != 'trips') {
      result.add(ReportRatio('attendance', 'نسبة الحضور المسجل', 'Recorded attendance rate',
        RatioMath.percent(s.attendance, s.attendance + s.absence),
        '${s.attendance} حضور ÷ ${s.attendance + s.absence} سجل حضور وغياب؛ الإجازات والأيام غير المسجلة خارج المقام.',
        '${s.attendance} present / ${s.attendance + s.absence} present and absent records; excludes leave and unrecorded days.'));
      if (s.reportType != 'work') result.add(ReportRatio('ppe', 'توثيق السلامة ضمن الحضور', 'PPE documentation among present records',
        RatioMath.percent(s.ppeCompliant, s.attendance),
        '${s.ppeCompliant} سجل حضور موثق بمعدات مكتملة ÷ ${s.attendance} سجل حضور.',
        '${s.ppeCompliant} present records with complete PPE / ${s.attendance} present records.'));
    }
    if (s.reportType == 'containers' || s.reportType == null || ['all', 'executive'].contains(s.reportType)) {
      result.add(ReportRatio('fullShare', 'حصة الحاويات الممتلئة', 'Full-container share',
        RatioMath.percent(s.containersFull, s.containersTotal),
        '${s.containersFull} ممتلئة ÷ ${s.containersTotal} حاوية.',
        '${s.containersFull} full / ${s.containersTotal} containers.'));
      result.add(ReportRatio('issueShare', 'نسبة الحاويات ذات المشكلات', 'Container issue rate',
        RatioMath.percent(s.containerIssues, s.containersTotal),
        '${s.containerIssues} ذات مشكلات ÷ ${s.containersTotal} حاوية. قد تتداخل مع حالات الامتلاء.',
        '${s.containerIssues} with issues / ${s.containersTotal} containers. May overlap fill states.'));
    }
    return result;
  }

  static List<ReportMetric> metrics(ReportSnapshot s) {
    final all = <String, ReportMetric>{
      'trips': ReportMetric('trips', s.reportType == 'work' ? 'النقلات المكتملة' : 'النقلات المسجلة', s.reportType == 'work' ? 'Completed trips' : 'Registered trips', '${s.trips}'),
      'completedTrips': ReportMetric('completedTrips', 'النقلات المكتملة', 'Completed trips', '${s.completedTrips}'),
      'supervisors': ReportMetric('supervisors', 'المشرفون', 'Supervisors', '${s.supervisors}'),
      'emergencies': ReportMetric('emergencies', 'الطوارئ', 'Emergencies', '${s.emergencies}'),
      'groups': ReportMetric('groups', 'المجموعات', 'Groups', '${s.groups}'),
      'municipalities': ReportMetric('municipalities', 'البلديات', 'Municipalities', '${s.municipalities}'),
      'containers': ReportMetric('containers', 'كل الحاويات', 'Containers', '${s.containersTotal}'),
      'full': ReportMetric('full', 'ممتلئة', 'Full containers', '${s.containersFull}'),
      'partial': ReportMetric('partial', 'نصف ممتلئة', 'Half-full containers', '${s.containersPartial}'),
      'issues': ReportMetric('issues', 'تحتاج متابعة', 'Container issues', '${s.containerIssues}'),
      'attendance': ReportMetric('attendance', 'الحضور', 'Present records', '${s.attendance}'),
      'absence': ReportMetric('absence', 'الغياب', 'Absence records', '${s.absence}'),
      'attendanceRate': ReportMetric('attendanceRate', 'نسبة الحضور', 'Attendance rate',
          s.attendance + s.absence == 0 ? '—' : '${(s.attendanceRate * 100).toStringAsFixed(0)}%'),
      'ppe': ReportMetric('ppe', 'الالتزام بالسلامة', 'PPE compliant records', '${s.ppeCompliant}'),
      'workers': ReportMetric('workers', 'العمال', 'Workers', '${s.workers}'),
      'cycles': ReportMetric('cycles', 'الدورات في النتائج', 'Cycles in results', '${s.cycleCount}'),
    };
    if (s.legacyCounts != null) {
      return [for (final key in s.legacyCounts!.keys) if (all.containsKey(key)) all[key]!];
    }
    final keys = switch (s.reportType) {
      'trips' => ['trips', 'completedTrips', 'groups', 'municipalities'],
      'containers' => ['containers', 'full', 'partial', 'issues'],
      'absence' => ['attendanceRate', 'attendance', 'absence', 'ppe'],
      'work' => ['trips', 'attendance', 'groups', 'workers'],
      'cycles' => ['cycles', 'trips', 'attendance'],
      'municipalities' => ['municipalities', 'trips', 'attendance', 'containers'],
      'groups' => ['groups', 'trips', 'attendance', 'absence'],
      _ => ['trips', 'completedTrips', 'attendanceRate', 'containers', 'full', 'groups', 'workers'],
    };
    return [for (final key in keys) all[key]!];
  }

  static List<ReportBreakdown> breakdowns(ReportSnapshot s, {bool english = false}) {
    String t(String ar, String en) => english ? en : ar;
    if (s.legacyCounts != null) return [];
    final daily = ReportBreakdown(t('النقلات حسب يوم التسجيل', 'Trips by recorded day'), s.tripsByDay);
    final groups = ReportBreakdown(t('النقلات حسب المجموعة', 'Trips by group'), s.tripsByGroup);
    final municipalities = ReportBreakdown(t('النقلات حسب البلدية', 'Trips by municipality'), s.tripsByMunicipality);
    final absent = ReportBreakdown(t('الغياب حسب المجموعة', 'Absence by group'), s.absenceByGroup);
    final attendance = ReportBreakdown(t('سجلات الحضور والغياب', 'Attendance and absence records'), {
      t('حضور', 'Present'): s.attendance, t('غياب', 'Absent'): s.absence,
    });
    final containers = ReportBreakdown(t('حالة الحاويات', 'Container status'), {
      t('فارغة', 'Empty'): s.containersEmpty, t('نصف ممتلئة', 'Half full'): s.containersPartial,
      t('ممتلئة', 'Full'): s.containersFull,
      if (s.containersTotal > s.containersEmpty + s.containersPartial + s.containersFull)
        t('غير محددة', 'Unknown'): s.containersTotal - s.containersEmpty - s.containersPartial - s.containersFull,
    });
    return switch (s.reportType) {
      'trips' => [daily, groups],
      'work' => [daily, groups, municipalities],
      'absence' => [attendance, absent],
      'containers' => [containers,
        ReportBreakdown(t('الحاويات حسب البلدية', 'Containers by municipality'), s.containersByMunicipality),
        ReportBreakdown(t('الحاويات حسب المجموعة', 'Containers by group'), s.containersByGroup)],
      'municipalities' => [municipalities],
      'groups' => [groups, absent],
      'cycles' => [daily, groups, attendance],
      _ => [daily, groups, attendance, containers],
    };
  }

  static List<List<String>> recordRows(ReportSnapshot s, {bool english = false}) {
    final records = s.reportType == 'containers' ? s.containerRecords
        : s.reportType == 'trips' ? s.tripRecords : const <Map<String, dynamic>>[];
    final statuses = english ? const {'full':'Full', 'partial':'Half full', 'empty':'Empty'}
        : const {'full':'ممتلئة', 'partial':'نصف ممتلئة', 'empty':'فارغة'};
    return [for (final record in records) [
      '${record['id'] ?? ''}',
      [
        '${record['locationName'] ?? record['title'] ?? record['location'] ?? ''}',
        '${record['municipalityName'] ?? ''}', '${record['groupName'] ?? ''}',
        if (s.reportType == 'containers') statuses['${record['status']}'] ?? '${record['status'] ?? ''}',
      ].where((value) => value.isNotEmpty).join(' • '),
    ]];
  }

  static List<List<String>> rows(ReportSnapshot s, {bool english = false}) {
    String t(String ar, String en) => english ? en : ar;
    return [
      [t('المؤشر', 'Metric'), t('القيمة', 'Value')],
      [t('معرّف التقرير', 'Report ID'), s.reportId],
      [t('نوع التقرير', 'Report type'), s.reportType ?? 'all'],
      [t('الفترة', 'Period'), s.periodLabel],
      [t('الفلاتر', 'Filters'), s.filterLabel(english: english)],
      [t('البلدية', 'Municipality'), s.selectedMunicipality ?? s.municipalityNames.join(' • ')],
      [t('المجموعة', 'Group'), s.selectedGroup ?? t('كل المجموعات المتاحة', 'All permitted groups')],
      [t('الدورة', 'Cycle'), s.selectedCycle ?? t('كل الدورات', 'All cycles')],
      [t('تاريخ الإصدار', 'Generated at'), s.generatedAt.toIso8601String()],
      if (s.reviewer != null) [t('المعتمد', 'Approved by'), s.reviewer!],
      if (s.approvalTime != null) [t('تاريخ الاعتماد','Approved at'),s.approvalTime!],
      if (s.legacyCounts != null) [t('الأرشيف', 'Archive'), t('ملخص النسخة القديمة المحفوظة', 'Stored legacy summary')]
      else [t('اكتمال المصدر', 'Source completeness'), s.sourceMayBeIncomplete
        ? t('قد تكون البيانات جزئية؛ راجع المصدر قبل الاعتماد.', 'Data may be partial; verify the source before approval.')
        : t('لم يُكتشف اقتطاع ضمن البيانات المتاحة.', 'No truncation detected in available data.')],
      for (final metric in metrics(s)) [metric.label(english), metric.value],
      for (final ratio in ratios(s)) ...[
        [ratio.label(english), ratio.display(english)],
        [t('أساس الحساب', 'Calculation basis'), ratio.basis(english)],
      ],
      for (final section in breakdowns(s, english: english)) ...[
        [section.title, ''],
        if (section.values.isEmpty) [t('لا توجد سجلات', 'No records'), ''],
        for (final entry in section.values.entries) ...[
          [entry.key, '${entry.value}'],
          [t('الحصة', 'Share') + ' — ' + entry.key, RatioMath.display(RatioMath.percent(entry.value, section.values.values.fold<int>(0, (a, b) => a + b)))],
        ],
      ],
      if (s.legacyCounts == null && (s.reportType == 'containers' || s.reportType == 'trips')) ...[
        [t('السجلات المطابقة للفلاتر', 'Records matching filters'), ''],
        ...recordRows(s, english: english),
      ],
    ];
  }
}
