import 'dart:async';
import '../widgets/container_status_picker.dart';
import '../widgets/app_navigation_bar.dart';
import 'dart:typed_data';
import '../../core/localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import '../widgets/app_design.dart';
import '../widgets/eco_shortcuts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/core_models.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/data_service.dart';
import '../../core/services/report_service.dart';
import 'monthly_attendance_report_screen.dart';
import 'attendance_reports_home_screen.dart';
import 'work_reports_dashboard.dart';
import 'report_branding_settings_screen.dart';
import 'report_approval_screen.dart';

class ReportsCenterScreen extends StatefulWidget {
  final bool embedded;
  const ReportsCenterScreen({super.key, this.embedded = false});
  @override State<ReportsCenterScreen> createState() => _ReportsCenterState();
}

class _ReportsCenterState extends State<ReportsCenterScreen> {
  late Future<ReportSnapshot> future;
  int days = 30;
  DateTime startDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime endDate = DateTime.now();
  String reportType = 'all';
  String search = '', containerStatus = 'all';
  final searchController = TextEditingController();
  Timer? searchTimer;
  ReportSnapshot? lastSnapshot;
  String exportLanguage = 'ar';
  String periodPreset = 'daily';
  String? municipality, group, cycle;

  @override void initState() { super.initState(); _reload(); }
  void _reload() {
    final data = context.read<DataService>(); final user = context.read<AuthService>().currentUser;
    final request = ReportService(data).load(days: days, startDate: startDate, endDate: endDate, user: user, municipality: municipality, group: group, cycle: cycle, reportType: reportType, reportId: _stableReportId(data), search: search, containerStatus: reportType == 'containers' ? containerStatus : 'all');
    future = request;
    request.then((snapshot) {
      if (mounted && identical(future, request)) setState(() => lastSnapshot = snapshot);
    }, onError: (Object error, StackTrace stack) {});
  }
  void _refresh() {
    if (!mounted) return;
    setState(_reload);
  }

  void _applyPeriodPreset(String preset) {
    final now = DateTime.now();
    final range = preset == 'daily'
        ? ReportPeriodPresets.daily(now)
        : preset == 'monthly' ? ReportPeriodPresets.monthly(now) : ReportPeriodPresets.weekly(now);
    setState(() {
      periodPreset = preset;
      startDate = range.startDate;
      endDate = range.endDate;
    });
    _refresh();
  }

  Future<void> _pickCustomPeriod() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
      initialDateRange: DateTimeRange(start: startDate, end: endDate),
      helpText: 'اختر فترة التقرير — يمكن أن تتجاوز 60 يومًا',
      saveText: 'اعتماد الفترة',
    );
    if (picked == null || !mounted) return;
    final range = ReportPeriodPresets.custom(picked.start, picked.end);
    setState(() {
      periodPreset = 'custom';
      startDate = range.startDate;
      endDate = range.endDate;
    });
    _refresh();
  }

  String _periodPresetLabel() {
    if (reportType == 'containers') return 'آخر حالة مسجلة للحاويات';
    if (periodPreset == 'monthly') return 'هذا الشهر';
    if (periodPreset == 'daily') return 'اليوم';
    if (periodPreset == 'weekly') return 'تقرير أسبوعي';
    final range = ReportPeriodPresets.custom(startDate, endDate);
    return 'فترة مخصصة (${range.inclusiveDays} يوم)';
  }

  String _stableReportId(DataService data) {
    String dateKey(DateTime d) => '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    final operationKeys = data.operations.where((e) => e['isDeleted'] != true && e['reportKind'] != 'report_approval' && e['_entity'] != 'report_approval').map((e) {
      final entity = '${e['_entity'] ?? ''}';
      return '${e['id'] ?? ''}:${e['createdAt'] ?? ''}:${e['checkInAt'] ?? ''}:${e['checkOutAt'] ?? ''}:${e['trips'] ?? ''}:${e['status'] ?? ''}:${e['updatedAt'] ?? ''}:${e['attendance'] ?? ''}:${e['absence'] ?? ''}:${entity == 'attendance' ? e['status'] ?? '' : ''}';
    }).toList()..sort();
    final source = '$search|$containerStatus|${dateKey(startDate)}|${dateKey(endDate)}|$reportType|${municipality ?? 'all'}|${group ?? 'all'}|${cycle ?? 'all'}|${operationKeys.join(';')}';
    var hash = 0;
    for (final unit in source.codeUnits) { hash = (hash * 31 + unit) & 0x7fffffff; }
    return 'CO-${hash.toRadixString(16)}';
  }

  bool _isApproved(ReportSnapshot snapshot) => context.watch<DataService>().operations.any((e) =>
      '${e['id'] ?? ''}' == snapshot.reportId &&
      (e['reportKind'] == 'report_approval' || e['_entity'] == 'report_approval') &&
      ['approved', 'closed'].contains('${e['status'] ?? ''}'));

  bool _canExportOfficial(ReportSnapshot snapshot, AppUser user) =>
      user.can('reports', 'export') &&
      ['municipality_coordinator', 'jsc_coordinator', 'donor_manager'].contains(user.role) &&
      _isApproved(snapshot);

  String _councilForReport(String? municipalityName) {
    final requested = (municipalityName ?? '').trim();
    if (requested.isEmpty) return '';
    for (final row in context.read<DataService>().operations) {
      final municipalityValue = '${row['municipalityName'] ?? row['municipality'] ?? row['municipalityId'] ?? ''}'.trim();
      if (municipalityValue != requested) continue;
      final council = '${row['councilName'] ?? row['councilId'] ?? ''}'.trim();
      if (council.isNotEmpty) return council;
    }
    return '';
  }

  @override Widget build(BuildContext context) {
    final rtl = context.watch<LocaleController>().isArabic;
    return Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: Scaffold(
      appBar: widget.embedded ? null : AppBar(bottom: const AppNavigationBar(), title: const AppText('التقارير')),
      body: RefreshIndicator(onRefresh: () async { _refresh(); await future; }, child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 120), children: [
          _hero(lastSnapshot),
          const SizedBox(height: 12),
          _reportTabs(),
          const SizedBox(height: 12),
          _filters(lastSnapshot),
          const SizedBox(height: 12),
          FutureBuilder<ReportSnapshot>(future: future, builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
            if (snap.hasError) return Column(children: [const AppText('تعذر تحميل التقارير.'), TextButton(onPressed: _refresh, child: const AppText('إعادة المحاولة'))]);
            if (!snap.hasData) return const SizedBox.shrink();
            return _body(snap.data!);
          }),
        ],
      )),
    ));
  }

  @override
  void dispose() { searchTimer?.cancel(); searchController.dispose(); super.dispose(); }

  void _selectReport(String value) {
    searchTimer?.cancel();
    setState(() {
      reportType = value; search = ''; searchController.clear();
      if (value != 'containers') containerStatus = 'all';
      _reload();
    });
  }

  Widget _reportTabs() {
    const reports = <(String, String, IconData)>[
      ('all', 'نظرة عامة', Icons.dashboard_customize_rounded),
      ('trips', 'الترحيلات', Icons.local_shipping_outlined),
      ('containers', 'الحاويات', Icons.delete_sweep_outlined),
      ('absence', 'الحضور والغياب', Icons.fact_check_outlined),
      ('work', 'العمل والتشغيل', Icons.assignment_turned_in_outlined),
      ('municipalities', 'البلديات', Icons.location_city_outlined),
      ('groups', 'المجموعات', Icons.groups_outlined),
      ('cycles', 'دورات العمل', Icons.event_repeat_outlined),
    ];
    return AiSectionCard(
      title: '1. اختر نوع التقرير',
      subtitle: 'اختر تقريرًا واحدًا؛ ستتغير المؤشرات والنتائج تلقائيًا.',
      feature: 'reports',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in reports)
            ChoiceChip(
              avatar: Icon(item.$3, size: 18),
              label: AppText(item.$2),
              selected: reportType == item.$1,
              onSelected: (_) => _selectReport(item.$1),
            ),
        ],
      ),
    );
  }

  Widget _body(ReportSnapshot s) {
    final u = context.read<AuthService>().currentUser!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (s.sourceMayBeIncomplete) const Card(child: ListTile(
        leading: Icon(Icons.warning_amber_rounded, color: Colors.orange),
        title: AppText('قد تكون بعض سجلات التقرير غير مكتملة'),
        subtitle: AppText('راجع الفترة والفلاتر قبل اعتماد التقرير.'),
      )),
      if (s.sourceMayBeIncomplete) const SizedBox(height: 8),
      _resultsHeader(s),
      const SizedBox(height: 10),
      _readingGuide(s),
      const SizedBox(height: 12),
      _kpis(s),
      const SizedBox(height: 12),
      _selectedReport(s),
      if (reportType == 'containers' || reportType == 'trips') ...[
        const SizedBox(height: 12),
        _records(s),
      ],
      const SizedBox(height: 12),
      _actions(s, u),
      const SizedBox(height: 12),
      _specializedReports(),
    ]);
  }

  Widget _resultsHeader(ReportSnapshot s) => Row(children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppText('3. النتائج — ${_title()}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      const SizedBox(height: 3),
      AppText(s.filterLabel(), style: const TextStyle(color: cleanOpsMuted, fontSize: 12)),
    ])),
    IconButton(tooltip: 'تحديث النتائج', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
  ]);

  Widget _records(ReportSnapshot s) {
    final rows = reportType == 'containers' ? s.containerRecords : s.tripRecords;
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppText('النتائج: ${rows.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
      if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: AppText('لا توجد نتائج مطابقة. جرّب مسح الفلاتر أو تغيير الفترة.')),
      for (final row in rows.take(100)) ListTile(
        title: AppText('${row['locationName'] ?? row['title'] ?? row['location'] ?? row['id'] ?? ''}'),
        subtitle: AppText(reportType == 'containers'
          ? (containerStatusLabels['${row['status']}'] ?? 'غير محددة')
          : '${row['municipalityName'] ?? ''} • ${row['groupName'] ?? ''}'),
      ),
      if (rows.length > 100) const AppText('تُعرض أول 100 نتيجة. ملخص التقرير يشمل جميع النتائج المطابقة.'),
    ])));
  }

  Widget _hero(ReportSnapshot? s) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: const LinearGradient(colors: [Color(0xFF123640), Color(0xFF087F78)]),
    ),
    child: Row(children: [
      const Icon(Icons.auto_graph_rounded, color: Color(0xFFE1B660), size: 36),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const AppText('المشهد التشغيلي', style: TextStyle(
            color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
        const AppText('مؤشرات ورسوم من السجلات التي تسمح بها صلاحياتك',
            style: TextStyle(color: Color(0xFFD0E8E1))),
        const SizedBox(height: 6),
        AppText(s?.periodLabel ?? _periodPresetLabel(),
            style: const TextStyle(color: Color(0xFFFFDA90))),
      ])),
      IconButton(onPressed: _refresh,
          icon: const Icon(Icons.refresh, color: Colors.white)),
    ]),
  );

  Widget _specializedReports() {
    final cards = <Widget>[
      EcoShortcutCard(
        title: 'سجل الحضور والإجازات',
        subtitle: 'عرض السجلات اليومية والتفاصيل',
        feature: 'attendance',
        icon: Icons.fact_check_outlined,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceReportsHomeScreen())),
      ),
      EcoShortcutCard(
        title: 'التقرير الشهري',
        subtitle: 'تقويم الحضور والغياب للشهر',
        feature: 'attendance',
        icon: Icons.calendar_month_outlined,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MonthlyAttendanceReportScreen())),
      ),
      EcoShortcutCard(
        title: 'تقارير العمل اليومية',
        subtitle: 'المسودات والتقارير المرسلة',
        feature: 'reports',
        icon: Icons.assignment_turned_in_outlined,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkReportsDashboard())),
      ),
      EcoShortcutCard(
        title: 'اعتماد التقارير',
        subtitle: 'المراجعة وحالة الموافقة',
        feature: 'reports',
        icon: Icons.verified_outlined,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportApprovalScreen())),
      ),
      if (const ['jsc_coordinator','donor_manager'].contains(context.read<AuthService>().currentUser?.role))
        EcoShortcutCard(
          title: 'هوية التقرير',
          subtitle: 'الشعارات وأسماء الجهات',
          feature: 'settings',
          icon: Icons.branding_watermark_outlined,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportBrandingSettingsScreen())),
        ),
    ];
    return AiSectionCard(
      title: 'سجلات وتقارير متخصصة',
      subtitle: 'أدوات تفصيلية مستقلة عند الحاجة.',
      feature: 'reports',
      child: EcoShortcutGrid(cards: cards, maxColumns: 3),
    );
  }

  void _resetFilters() {
    searchTimer?.cancel(); searchController.clear();
    setState(() {
      municipality = null; group = null; cycle = null; search = ''; containerStatus = 'all';
      final range = ReportPeriodPresets.daily(DateTime.now());
      startDate = range.startDate; endDate = range.endDate; periodPreset = 'daily';
      _reload();
    });
  }

  int get _activeFilterCount {
    var count = 0;
    if (reportType != 'containers' && periodPreset != 'daily') count++;
    if (municipality != null && municipality!.isNotEmpty) count++;
    if (group != null && group!.isNotEmpty) count++;
    if (reportType != 'containers' && cycle != null && cycle!.isNotEmpty) count++;
    if (search.isNotEmpty) count++;
    if (reportType == 'containers' && containerStatus != 'all') count++;
    return count;
  }

  Widget _filters(ReportSnapshot? s) {
    final filterCount = _activeFilterCount;
    final advancedSelected = group != null || cycle != null;
    return AiSectionCard(
      title: '2. حدّد النطاق',
      subtitle: reportType == 'containers'
          ? 'تعرض الحاويات وفق آخر حالة مسجلة.'
          : 'ابدأ بالفترة والموقع، واستخدم الخيارات الإضافية عند الحاجة.',
      feature: 'reports',
      trailing: filterCount == 0 ? null : Chip(label: AppText('$filterCount فلاتر نشطة')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppText(
          reportType == 'containers' ? 'حالة الحاوية' : 'الفترة الزمنية',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 7),
        if (reportType != 'containers')
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final entry in const {'daily':'اليوم', 'weekly':'آخر 7 أيام', 'monthly':'هذا الشهر'}.entries)
              ChoiceChip(
                label: AppText(entry.value),
                selected: periodPreset == entry.key,
                onSelected: (_) => _applyPeriodPreset(entry.key),
              ),
            ChoiceChip(
              avatar: const Icon(Icons.date_range_rounded, size: 18),
              label: AppText(periodPreset == 'custom' ? _periodPresetLabel() : 'فترة محددة'),
              selected: periodPreset == 'custom',
              onSelected: (_) => _pickCustomPeriod(),
            ),
          ])
        else
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final entry in const {'all':'كل الحالات', 'full':'ممتلئة', 'partial':'نصف ممتلئة', 'empty':'فارغة', 'stale':'لم تُحدّث اليوم'}.entries)
              ChoiceChip(
                label: AppText(entry.value),
                selected: containerStatus == entry.key,
                onSelected: (_) {
                  setState(() => containerStatus = entry.key);
                  _refresh();
                },
              ),
          ]),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _drop<String>(
            'الموقع',
            municipality,
            <String?,String>{
              null:'كل المواقع المتاحة',
              if (municipality != null) municipality!:municipality!,
              ...{for(final x in s?.availableMunicipalities ?? <String>[]) x:x},
            },
            (v) {
              setState(() { municipality = v; group = null; });
              _refresh();
            },
          ),
          SizedBox(
            width: 310,
            child: TextField(
              controller: searchController,
              onChanged: (v) {
                searchTimer?.cancel();
                searchTimer = Timer(const Duration(milliseconds: 350), () {
                  if (!mounted) return;
                  setState(() { search = v.trim(); _reload(); });
                });
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: search.isEmpty ? null : IconButton(
                  tooltip: 'مسح البحث',
                  onPressed: () {
                    searchController.clear();
                    setState(() { search = ''; _reload(); });
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
                labelText: tr(reportType == 'containers'
                    ? 'ابحث برقم الحاوية أو اسم الموقع'
                    : 'ابحث في نتائج التقرير'),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        ExpansionTile(
          key: ValueKey('$reportType-$advancedSelected'),
          initiallyExpanded: advancedSelected,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          title: const AppText('تصفية حسب المجموعة والدورة'),
          subtitle: const AppText('اختياري — اتركها كما هي لعرض الكل'),
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              _drop<String>(
                'المجموعة',
                group,
                <String?,String>{
                  null:'كل المجموعات',
                  if (group != null) group!:group!,
                  ...{for(final x in _availableGroups()) x:x},
                },
                (v) { setState(() => group = v); _refresh(); },
              ),
              if (reportType != 'containers')
                _drop<String>(
                  'الدورة',
                  cycle,
                  <String?,String>{
                    null:'كل الدورات',
                    if (cycle != null) cycle!:cycle!,
                    ...{for(final x in s?.cycles ?? <String>[]) x:x},
                  },
                  (v) { setState(() => cycle = v); _refresh(); },
                ),
            ]),
          ],
        ),
        Row(children: [
          Expanded(child: AppText(
            reportType == 'containers'
                ? 'النطاق الحالي: آخر حالة مسجلة للحاويات'
                : 'النطاق الحالي: ${_periodPresetLabel()}',
            style: const TextStyle(color: cleanOpsMuted, fontSize: 12),
          )),
          if (filterCount > 0)
            TextButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const AppText('إعادة الضبط'),
            ),
        ]),
      ]),
    );
  }

  List<String> _availableGroups() {
    final ops = context.read<DataService>().operations;
    final values = <String>{};
    for (final e in ops) {
      if (e['isDeleted'] == true) continue;
      if (e['_entity'] != 'group' && e['_entity'] != 'trip' && e['_entity'] != 'attendance' && e['_entity'] != 'work_report' && !(e['_entity'] == 'report' && e['reportKind'] == 'work_report')) continue;
      final currentUser = context.read<AuthService>().currentUser;
      if (currentUser == null) continue;
      if (currentUser.role == 'municipality_coordinator') {
        final owner = '${e['municipalityCoordinatorId'] ?? ''}';
        final scope = currentUser.scope.trim();
        final mun = '${e['municipalityName'] ?? e['municipality'] ?? e['municipalityId'] ?? ''}';
        if (owner != currentUser.id && (scope.isEmpty || scope == 'all' || scope == 'assigned_only' || mun != scope)) continue;
      } else if (currentUser.role == 'group_supervisor' || currentUser.role == 'worker') {
        if ('${e['groupId'] ?? e['groupName'] ?? ''}' != '${currentUser.groupId ?? ''}') continue;
      } else if (currentUser.role == 'jsc_coordinator') {
        final scope = currentUser.scope.trim();
        final council = '${e['councilName'] ?? e['councilId'] ?? e['municipalityName'] ?? ''}';
        if (scope.isEmpty || scope == 'all' || scope == 'assigned_only' || council != scope) continue;
      }
      final groupName = '${e['groupName'] ?? e['name'] ?? e['groupId'] ?? ''}'.trim();
      if (groupName.isEmpty) continue;
      if (municipality != null && municipality!.isNotEmpty) {
        final municipalityName = '${e['municipalityName'] ?? e['municipality'] ?? ''}'.trim();
        final municipalityId = '${e['municipalityId'] ?? ''}'.trim();
        if (municipalityName != municipality && municipalityId != municipality) continue;
      }
      values.add(groupName);
    }
    return values.toList()..sort();
  }

  Widget _drop<T>(String label, T? value, Map<T?,String> items, ValueChanged<T?> onChanged) => SizedBox(width: 190, child: DropdownButtonFormField<T>(value: value, isExpanded: true, decoration: InputDecoration(labelText: label, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)), items: items.entries.map((e)=>DropdownMenuItem<T>(value:e.key, child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(), onChanged: onChanged));

  Widget _kpis(ReportSnapshot s) {
    final cards = switch (reportType) {
      'trips' => <Widget>[
          _k('الترحيلات', '${s.trips}', navy, Icons.local_shipping_outlined),
          _k('المجموعات', '${s.groups}', green, Icons.groups_outlined),
          _k('البلديات', '${s.municipalities}', gold, Icons.location_city_outlined),
        ],
      'containers' => <Widget>[
          _k('كل الحاويات', '${s.containersTotal}', navy, Icons.delete_outline),
          _k('ممتلئة', '${s.containersFull}', red, Icons.warning_amber_rounded),
          _k('نصف ممتلئة', '${s.containersPartial}', orange, Icons.timelapse_rounded),
          _k('تحتاج متابعة', '${s.containerIssues}', red, Icons.build_circle_outlined),
        ],
      'absence' => <Widget>[
          _k('نسبة الحضور', '${(s.attendanceRate * 100).toStringAsFixed(0)}%', green, Icons.how_to_reg),
          _k('الحضور', '${s.attendance}', green, Icons.person_add_alt_1_outlined),
          _k('الغياب', '${s.absence}', red, Icons.person_off_outlined),
          _k('التزام السلامة', '${s.ppeCompliant}', aiCyan, Icons.health_and_safety_outlined),
        ],
      'work' => <Widget>[
          _k('الترحيلات', '${s.trips}', navy, Icons.local_shipping_outlined),
          _k('الحضور', '${s.attendance}', green, Icons.how_to_reg),
          _k('المجموعات', '${s.groups}', green, Icons.groups_outlined),
          _k('العمال', '${s.workers}', aiGreen, Icons.people_alt_outlined),
        ],
      'cycles' => <Widget>[
          _k('الدورات', '${s.cycleCount}', aiCyan, Icons.event_repeat_outlined),
          _k('الترحيلات', '${s.trips}', navy, Icons.local_shipping_outlined),
          _k('الحضور', '${s.attendance}', green, Icons.how_to_reg),
        ],
      'municipalities' => <Widget>[
          _k('البلديات', '${s.municipalities}', gold, Icons.location_city_outlined),
          _k('الترحيلات', '${s.trips}', navy, Icons.local_shipping_outlined),
          _k('الحضور', '${s.attendance}', green, Icons.how_to_reg),
          _k('الحاويات', '${s.containersTotal}', aiCyan, Icons.delete_outline),
        ],
      'groups' => <Widget>[
          _k('المجموعات', '${s.groups}', green, Icons.groups_outlined),
          _k('الترحيلات', '${s.trips}', navy, Icons.local_shipping_outlined),
          _k('الحضور', '${s.attendance}', green, Icons.how_to_reg),
          _k('الغياب', '${s.absence}', red, Icons.person_off_outlined),
        ],
      _ => <Widget>[
          _k('الترحيلات', '${s.trips}', navy, Icons.local_shipping_outlined),
          _k('نسبة الحضور', '${(s.attendanceRate * 100).toStringAsFixed(0)}%', green, Icons.how_to_reg),
          _k('الحاويات', '${s.containersTotal}', aiCyan, Icons.delete_outline),
          _k('الحاويات الممتلئة', '${s.containersFull}', red, Icons.warning_amber_rounded),
          _k('المجموعات', '${s.groups}', green, Icons.groups_outlined),
          _k('العمال', '${s.workers}', aiGreen, Icons.people_alt_outlined),
        ],
    };
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 850 ? 4 : constraints.maxWidth >= 540 ? 3 : constraints.maxWidth >= 300 ? 2 : 1;
      final width = (constraints.maxWidth - 10 * (columns - 1)) / columns;
      return Wrap(spacing: 10, runSpacing: 10,
          children: [for (final card in cards) SizedBox(width: width, child: card)]);
    });
  }
  Widget _k(String a,String b,Color c,IconData icon)=>Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: c.withOpacity(.09),
        borderRadius: BorderRadius.circular(17),
        border: BorderDirectional(start: BorderSide(color: c, width: 4))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: c, size: 20), const SizedBox(height: 7),
      AppText(b, style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: c)),
      AppText(a, style: const TextStyle(fontSize: 12)),
    ]));

  Widget _readingGuide(ReportSnapshot s) {
    final attendanceTotal = s.attendance + s.absence;
    final headline = switch (reportType) {
      'containers' => '${s.containersFull} حاوية ممتلئة من ${s.containersTotal} حاوية مسجلة',
      'absence' => attendanceTotal == 0 ? 'لا توجد سجلات حضور أو غياب في الفترة' : '${s.attendance} سجل حضور من $attendanceTotal سجل حضور وغياب',
      'cycles' => 'الدورات المتاحة: ${s.cycleCount}',
      _ => '${s.trips} نقلة مسجلة ضمن الفترة المختارة',
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      decoration: BoxDecoration(
        border: BorderDirectional(start: BorderSide(color: green, width: 3)),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const AppText('قراءة سريعة', style: TextStyle(fontSize: 12, color: cleanOpsMuted)),
        const SizedBox(height: 5),
        AppText(headline, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const AppText('المؤشرات تصف السجلات المتاحة ضمن الفلاتر؛ مقارنة عدد النقلات لا تمثل وحدها كفاءة المجموعة أو البلدية.',
            style: TextStyle(fontSize: 12, color: cleanOpsMuted)),
      ]),
    );
  }

  Widget _selectedReport(ReportSnapshot s) {
    switch(reportType) {
      case 'absence': return _section('الحضور والغياب', Column(children: [
        _donut(s), _rank(s.absenceByGroup, 'سجلات الغياب حسب المجموعة', red)]));
      case 'trips': return _section('حركة الترحيلات', Column(children: [
        _lineTrips(s), _rank(s.tripsByGroup, 'عدد النقلات حسب المجموعة', green)]));
      case 'containers': return _section('توزيع الحاويات', Column(children: [
        _rank(s.containersByMunicipality, 'حسب البلدية', navy),
        _rank(s.containersByGroup, 'حسب المجموعة', green)]));
      case 'work': return _section('الأعمال خلال الفترة', Column(children: [
        _lineTrips(s), _rank(s.tripsByGroup, 'عدد النقلات حسب المجموعة', green),
        _rank(s.tripsByMunicipality, 'عدد النقلات حسب البلدية', navy)]));
      case 'cycles': return _section('دورات العمل', _cycleSummary(s));
      case 'municipalities': return _section('مقارنة البلديات',
        _rank(s.tripsByMunicipality, 'عدد النقلات المسجلة', navy));
      case 'groups': return _section('مقارنة المجموعات', Column(children: [
        _rank(s.tripsByGroup, 'عدد النقلات', green),
        _rank(s.absenceByGroup, 'سجلات الغياب', red)]));
      default: return _section('تفاصيل المشهد التشغيلي', Column(children: [
        _lineTrips(s), _rank(s.tripsByGroup, 'عدد النقلات حسب المجموعة', green),
        const Divider(height: 30), _donut(s),
        const Divider(height: 30), _containerStatus(s)]));
    }
  }
  Widget _section(String title, Widget child) => AiSectionCard(title: title, feature: 'reports', child: child);

  Widget _lineTrips(ReportSnapshot s) {
    final points = s.tripsByDay.entries.toList();
    DateTime date(String key) {
      final full = DateTime.tryParse(key);
      if (full != null) return full;
      final parts = key.split('/');
      if (parts.length != 2) return startDate;
      final month = int.tryParse(parts[0]) ?? startDate.month;
      final day = int.tryParse(parts[1]) ?? startDate.day;
      return DateTime(startDate.year + (month < startDate.month ? 1 : 0), month, day);
    }
    points.sort((a, b) => date(a.key).compareTo(date(b.key)));
    if (points.isEmpty) return const Padding(padding: EdgeInsets.all(16),
        child: AppText('لا توجد نقلات مسجلة لرسم حركة الفترة.'));
    final interval = points.length <= 5 ? 1.0 : ((points.length - 1) / 4).ceilToDouble();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const AppText('حركة النقلات حسب أيام التسجيل', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      const AppText('الأيام غير المسجلة لا تمثل صفرًا مؤكدًا.',
          style: TextStyle(fontSize: 11, color: cleanOpsMuted)),
      const SizedBox(height: 18),
      SizedBox(height: 180, child: LineChart(LineChartData(
        minY: 0, minX: 0, maxX: points.length == 1 ? 1 : (points.length - 1).toDouble(),
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [LineChartBarData(
          spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].value.toDouble())],
          isCurved: false, barWidth: 3, color: green,
          belowBarData: BarAreaData(show: true, color: green.withOpacity(.08)),
          dotData: FlDotData(show: points.length <= 15))],
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 38)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, interval: interval,
            getTitlesWidget: (value, meta) {
              final index = value.round();
              if ((value - index).abs() > .01 || index < 0 || index >= points.length) return const SizedBox.shrink();
              final day = date(points[index].key);
              return Padding(padding: const EdgeInsets.only(top: 7),
                child: Text('${day.day}/${day.month}', style: const TextStyle(fontSize: 10)));
            })),
        ),
      ))),
    ]);
  }
  Widget _donut(ReportSnapshot s) {
    final total = s.attendance + s.absence;
    if (total == 0) return const Padding(padding: EdgeInsets.all(16),
        child: AppText('لا توجد سجلات حضور وغياب متاحة للرسم.'));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const AppText('توزيع سجلات الحضور والغياب', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 14),
      Center(child: SizedBox(width: 150, height: 150, child: Stack(alignment: Alignment.center, children: [
        PieChart(PieChartData(centerSpaceRadius: 49, sectionsSpace: 4, sections: [
          if (s.attendance > 0) PieChartSectionData(value: s.attendance.toDouble(), showTitle: false, color: green, radius: 18),
          if (s.absence > 0) PieChartSectionData(value: s.absence.toDouble(), showTitle: false, color: red, radius: 18),
        ])),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${(s.attendance / total * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: green)),
          const AppText('حضور', style: TextStyle(fontSize: 12)),
        ]),
      ]))),
      const SizedBox(height: 12),
      Center(child: Wrap(spacing: 18, runSpacing: 8, children: [
        Text('● حضور: ${s.attendance}', style: TextStyle(color: green)),
        Text('● غياب: ${s.absence}', style: TextStyle(color: red)),
      ])),
      const SizedBox(height: 8),
      const AppText('النسبة من سجلات الحضور والغياب فقط؛ لا تشمل الإجازات أو الأيام غير المسجلة.',
          style: TextStyle(fontSize: 11, color: cleanOpsMuted)),
    ]);
  }
  Widget _containerStatus(ReportSnapshot s)=>Wrap(spacing:8,runSpacing:8,children:[_mini('فارغة',s.containersEmpty,green),_mini('نصف ممتلئة',s.containersPartial,orange),_mini('ممتلئة',s.containersFull,red),_mini('مشكلات',s.containerIssues,red)]);
  Widget _mini(String t,int v,Color c)=>Container(width:125,padding:const EdgeInsets.all(12),decoration:BoxDecoration(borderRadius:BorderRadius.circular(14),border:Border.all(color:c.withOpacity(.3))),child:Column(children:[AppText(t),AppText('$v',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900,color:c))]));
  Widget _rank(Map<String, int> map, String title, Color color) {
    final entries = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maximum = entries.isEmpty || entries.first.value <= 0 ? 1 : entries.first.value;
    Widget row(MapEntry<String, int> entry, int index) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${index + 1}'.padLeft(2, '0'), style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          Expanded(child: Text(entry.key)),
          const SizedBox(width: 12),
          Text('${entry.value}', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 17)),
        ]),
        const SizedBox(height: 7),
        ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(
          value: (entry.value / maximum).clamp(0.0, 1.0), minHeight: 6,
          color: color, backgroundColor: color.withOpacity(.08))),
      ]),
    );
    return Padding(padding: const EdgeInsets.only(top: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppText(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        if (entries.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 14),
          child: AppText('لا توجد سجلات متاحة لهذه المقارنة.')),
        for (var i = 0; i < entries.length && i < 6; i++) row(entries[i], i),
        if (entries.length > 6) ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: AppText('عرض البقية (${entries.length - 6})'),
          children: [for (var i = 6; i < entries.length; i++) row(entries[i], i)]),
      ]));
  }
  Widget _cycleSummary(ReportSnapshot s)=>ListTile(leading:const Icon(Icons.event_repeat),title:AppText('الدورات المتاحة: ${s.cycleCount}'),subtitle:AppText(s.cycles.isEmpty?'لا توجد بيانات دورات متاحة':'آخر دورة: ${s.cycles.first}'));

  Future<void> _createSmartDraft(ReportSnapshot snapshot, AppUser user) async {
    try {
      final summary = await ReportService(context.read<DataService>()).createSmartReport(
        user: user,
        snapshot: snapshot,
        municipality: municipality,
        group: group,
        cycle: cycle,
        periodPreset: periodPreset,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: AppText('تم حفظ مسودة التقرير الذكي: $summary'),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: AppText('تعذر إنشاء مسودة التقرير الذكي: $error'),
      ));
    }
  }

  Widget _actions(ReportSnapshot snapshot, AppUser user) {
    final approved = _canExportOfficial(snapshot, user);
    return AiSectionCard(
      title: '4. المعاينة والتصدير',
      subtitle: 'عاين التقرير أولًا، ثم أرسله للمراجعة أو صدّر النسخة المعتمدة.',
      feature: 'reports',
      trailing: Icon(
        approved ? Icons.verified_rounded : Icons.pending_actions_rounded,
        color: approved ? green : orange,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _drop<String>(
            'لغة التقرير',
            exportLanguage,
            const {'ar':'العربية','en':'English'},
            (value) {
              if (value != null) setState(() => exportLanguage = value);
            },
          ),
          OutlinedButton.icon(
            onPressed: () => _previewReport(snapshot, user),
            icon: const Icon(Icons.preview_outlined),
            label: const AppText('معاينة وطباعة'),
          ),
          OutlinedButton.icon(
            onPressed: user.can('reports', 'create')
                ? () => _createSmartDraft(snapshot, user)
                : null,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const AppText('حفظ مسودة'),
          ),
          if (user.role == 'municipality_coordinator' && user.can('reports', 'create'))
            FilledButton.tonalIcon(
              onPressed: () => _requestApproval(snapshot, user),
              icon: const Icon(Icons.send_rounded),
              label: const AppText('إرسال للمراجعة'),
            ),
        ]),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: approved ? green.withOpacity(.08) : orange.withOpacity(.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: (approved ? green : orange).withOpacity(.25)),
          ),
          child: Row(children: [
            Icon(approved ? Icons.verified_outlined : Icons.info_outline_rounded,
                color: approved ? green : orange),
            const SizedBox(width: 8),
            Expanded(child: AppText(
              approved
                  ? 'التقرير معتمد وجاهز للتصدير الرسمي.'
                  : 'التصدير الرسمي يتاح بعد اعتماد التقرير. المعاينة والطباعة متاحتان الآن.',
              style: const TextStyle(fontSize: 12),
            )),
          ]),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: approved ? () => _exportPdf(snapshot, user) : null,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const AppText('PDF معتمد'),
          ),
          OutlinedButton.icon(
            onPressed: approved ? () => _exportExcel(snapshot, user) : null,
            icon: const Icon(Icons.table_view_outlined),
            label: const AppText('Excel'),
          ),
          OutlinedButton.icon(
            onPressed: approved ? () => _exportCsv(snapshot, user) : null,
            icon: const Icon(Icons.file_download_outlined),
            label: const AppText('CSV'),
          ),
        ]),
      ]),
    );
  }

  Future<void> _previewReport(ReportSnapshot snapshot, AppUser user) async {
    try {
      final bytes = await ReportService(context.read<DataService>()).buildOperationalPdfBytes(
        snapshot: snapshot,
        user: user,
        title: '${_title()} — CleanOps',
        languageCode: exportLanguage,
      );
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
        appBar: AppBar(
          bottom: const AppNavigationBar(),
          title: const AppText('معاينة التقرير'),
        ),
        body: PdfPreview(build: (_) => Uint8List.fromList(bytes)),
      )));
    } catch (error) {
      _showMessage('تعذرت معاينة التقرير: $error');
    }
  }

  Future<void> _exportPdf(ReportSnapshot snapshot, AppUser user) async {
    if (!_canExportOfficial(snapshot, user)) return;
    try {
      final path = await ReportService(context.read<DataService>()).exportOperationalPdf(
        snapshot: snapshot,
        user: user,
        title: '${_title()} — CleanOps',
        languageCode: exportLanguage,
      );
      _showMessage(path == null ? 'تعذر إنشاء PDF.' : 'تم إنشاء ملف PDF: $path');
    } catch (error) {
      _showMessage('فشل إنشاء PDF: $error');
    }
  }

  Future<void> _exportExcel(ReportSnapshot snapshot, AppUser user) async {
    if (!_canExportOfficial(snapshot, user)) return;
    try {
      final path = await ReportService(context.read<DataService>()).exportOperationalExcel(
        snapshot: snapshot,
        user: user,
        languageCode: exportLanguage,
      );
      _showMessage(path == null ? 'تعذر إنشاء Excel.' : 'تم إنشاء ملف Excel: $path');
    } catch (error) {
      _showMessage('فشل إنشاء Excel: $error');
    }
  }

  Future<void> _exportCsv(ReportSnapshot snapshot, AppUser user) async {
    if (!_canExportOfficial(snapshot, user)) return;
    try {
      final path = await ReportService(context.read<DataService>()).exportOperationalCsv(
        snapshot: snapshot,
        user: user,
        languageCode: exportLanguage,
      );
      _showMessage(path == null ? 'تعذر إنشاء CSV.' : 'تم إنشاء ملف CSV: $path');
    } catch (error) {
      _showMessage('فشل إنشاء CSV: $error');
    }
  }

  Future<void> _requestApproval(ReportSnapshot snapshot, AppUser user) async {
    if (user.role != 'municipality_coordinator' || !user.can('reports', 'create')) return;
    try {
      final now = DateTime.now().toIso8601String();
      final data = context.read<DataService>();
      await data.enqueue('report_approval', 'create', {
        'id': snapshot.reportId,
        'title': '${_periodPresetLabel()} — ${_title()}',
        'reportType': reportType,
        'search': snapshot.search,
        'containerStatus': snapshot.containerStatus,
        'filterLabel': snapshot.filterLabel(),
        'period': snapshot.periodLabel,
        'municipality': municipality,
        'group': group,
        'cycle': cycle,
        'requestedBy': user.id,
        'municipalityCoordinatorId': user.id,
        'municipalityName': municipality ?? (user.scope != 'assigned_only' ? user.scope : ''),
        'councilName': _councilForReport(municipality ?? user.scope),
        'snapshot': {
          'trips': snapshot.trips,
          'attendance': snapshot.attendance,
          'absence': snapshot.absence,
          'workers': snapshot.workers,
          'supervisors': snapshot.supervisors,
          'groups': snapshot.groups,
          'containers': snapshot.containersTotal,
          'emergencies': snapshot.emergencies,
        },
        'createdAt': now,
        'status': 'submitted',
        'isDeleted': false,
      });
      await data.writeAudit(
        actorId: user.id,
        operation: 'REQUEST_REPORT_APPROVAL',
        targetId: snapshot.reportId,
        after: {
          'reportType': reportType,
          'search': snapshot.search,
          'containerStatus': snapshot.containerStatus,
          'filterLabel': snapshot.filterLabel(),
          'period': snapshot.periodLabel,
          'periodPreset': periodPreset,
          'status': 'submitted',
          'municipality': municipality,
          'group': group,
          'cycle': cycle,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('تم إرسال التقرير إلى دورة المراجعة.')),
      );
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportApprovalScreen()));
    } catch (error) {
      _showMessage('تعذر إرسال التقرير للمراجعة: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: AppText(message)));
  }
  String _title()=>switch(reportType){'trips'=>'تقرير عمليات الترحيل','absence'=>'تقرير الغياب والحضور','containers'=>'تقرير الحاويات','work'=>'تقرير العمل والتشغيل','cycles'=>'تقرير الدورات','municipalities'=>'تقرير البلديات','groups'=>'تقرير المجموعات',_=>'التقرير التنفيذي الشامل'};
}
