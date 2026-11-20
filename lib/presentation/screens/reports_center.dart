import 'dart:async';
import '../widgets/container_status_picker.dart';
import '../widgets/app_navigation_bar.dart';
import 'dart:typed_data';
import '../../core/localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../widgets/app_design.dart';
import '../widgets/eco_shortcuts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/core_models.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/data_service.dart';
import '../../core/services/report_service.dart';
import '../../core/services/report_content.dart';
import '../../core/services/report_ratios.dart';
import '../widgets/report_ratio_panel.dart';
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
  int _recordsPage = 0;
  static const _recordsPageSize = 25;
  bool _compareMunicipalities = false;
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
  bool _loading = true, _previewing = false;

  @override void initState() { super.initState(); _reload(); }
  void _reload() {
    final data = context.read<DataService>(); final user = context.read<AuthService>().currentUser;
    _loading = true;
    _recordsPage = 0;
    final request = ReportService(data).load(days: days, startDate: startDate, endDate: endDate, user: user, municipality: municipality, group: group, cycle: cycle, reportType: reportType, reportId: 'operational-v2', search: search, containerStatus: reportType == 'containers' ? containerStatus : 'all');
    future = request;
    request.then((snapshot) {
      if (mounted && identical(future, request)) setState(() { lastSnapshot = snapshot; _loading = false; });
    }, onError: (Object error, StackTrace stack) {
      if (mounted && identical(future, request)) setState(() { _loading = false; lastSnapshot = null; });
    });
  }
  void _refresh() {
    if (!mounted) return;
    setState(_reload);
  }

  void _applyPeriodPreset(String preset) {
    final now = DateTime.now();
    final range = preset == 'daily'
        ? ReportPeriodPresets.daily(now)
        : preset == 'monthly' ? ReportPeriodPresets.monthly(now)
        : preset == 'twenty' ? ReportPeriodPresets.custom(DateTime(now.year, now.month, now.day).subtract(const Duration(days: 19)), now)
        : ReportPeriodPresets.weekly(now);
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
    if (periodPreset == 'weekly') return 'آخر 7 أيام';
    if (periodPreset == 'twenty') return 'آخر 20 يومًا';
    final range = ReportPeriodPresets.custom(startDate, endDate);
    return 'فترة مخصصة (${range.inclusiveDays} يوم)';
  }

  Map<String, dynamic>? _approvedRecord(ReportSnapshot snapshot, AppUser user) {
    final data = context.read<DataService>();
    if (!user.can('reports', 'export')) return null;
    final matches = data.operations.where((row) =>
      row['selectionKey'] == snapshot.reportId && ReportApprovalScreen.canView(row, user) &&
      (user.role == 'municipality_coordinator' ? row['requestedBy'] == user.id : snapshot.selectedMunicipality != null) &&
      ReportApprovalScreen.canExport(row, user, data)).toList()
      ..sort((a,b) => '${b['approvedAt'] ?? b['createdAt']}'.compareTo('${a['approvedAt'] ?? a['createdAt']}'));
    return matches.firstOrNull;
  }

  Future<String> _councilForReport(AppUser user, String? municipalityName) async {
    final requested = _namedScope(municipalityName ?? user.scope);
    final councils = <String>{};
    for (final row in context.read<DataService>().operations) {
      if (row['isDeleted'] == true) continue;
      final belongs = requested.isEmpty
          ? row['municipalityCoordinatorId'] == user.id
          : [row['municipalityName'], row['municipality'], row['municipalityId']].contains(requested);
      final council = '${row['councilName'] ?? row['councilId'] ?? ''}'.trim();
      if (belongs && council.isNotEmpty) councils.add(council);
    }
    if (councils.length == 1) return councils.single;
    if (Firebase.apps.isNotEmpty) {
      final profile = (await FirebaseFirestore.instance.collection('users').doc(user.id).get()).data();
      for (final key in ['councilName','council','councilId']) {
        final value = '${profile?[key] ?? ''}'.trim();
        if (value.isNotEmpty) return value;
      }
    }
    return '';
  }

  String _namedScope(String value) => ['assigned_only','all'].contains(value.trim()) ? '' : value.trim();

  @override Widget build(BuildContext context) {
    final rtl = context.watch<LocaleController>().isArabic;
    context.watch<DataService>();
    return Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: Scaffold(
      appBar: widget.embedded ? null : AppBar(bottom: const AppNavigationBar(), title: const AppText('التقارير')),
      bottomNavigationBar: widget.embedded ? null : _quickPreview(),
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
      _compareMunicipalities = value == 'municipalities';
      if (value != 'containers') containerStatus = 'all';
      if (value == 'containers') cycle = null;
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
      ReportRatioPanel(ratios: ReportContent.ratios(s), english: !context.read<LocaleController>().isArabic),
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
    final count = (rows.length / _recordsPageSize).ceil();
    final page = count == 0 ? 0 : _recordsPage.clamp(0, count - 1).toInt();
    final english = !context.read<LocaleController>().isArabic;
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(english ? 'Detailed records (${rows.length})' : 'السجلات التفصيلية (${rows.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
      if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: AppText('لا توجد نتائج مطابقة. جرّب مسح الفلاتر أو تغيير الفترة.')),
      for (final row in rows.skip(page * _recordsPageSize).take(_recordsPageSize)) ListTile(
        title: AppText('${row['locationName'] ?? row['title'] ?? row['location'] ?? row['id'] ?? ''}'),
        subtitle: AppText(reportType == 'containers'
          ? (containerStatusLabels['${row['status']}'] ?? 'غير محددة')
          : '${row['municipalityName'] ?? ''} • ${row['groupName'] ?? ''}'),
      ),
      if (rows.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        TextButton(onPressed: page == 0 ? null : () => setState(() => _recordsPage = page - 1),
            child: Text(english ? 'Previous' : 'السابق')),
        Text(english ? 'Page ${page + 1} of $count' : 'صفحة ${page + 1} من $count'),
        TextButton(onPressed: page + 1 >= count ? null : () => setState(() => _recordsPage = page + 1),
            child: Text(english ? 'Next' : 'التالي')),
      ]),
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

  Widget _quickPreview() {
    final user = context.read<AuthService>().currentUser;
    final snapshot = lastSnapshot;
    return SafeArea(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: FilledButton.icon(
        onPressed: _loading || _previewing || snapshot == null || user == null
            ? null : () => _previewReport(snapshot, user),
        icon: _previewing
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.preview_outlined),
        label: AppText(_loading ? 'تحديث نتائج التقرير…' : _previewing ? 'تجهيز المعاينة…' : 'معاينة التقرير الحالي'),
      ),
    ));
  }

  Widget _filterChips() {
    void remove(String key) {
      searchTimer?.cancel();
      setState(() {
        switch (key) {
          case 'municipality': municipality = null; group = null; break;
          case 'group': group = null; break;
          case 'cycle': cycle = null; break;
          case 'search': search = ''; searchController.clear(); break;
          case 'status': containerStatus = 'all'; break;
          case 'period':
            final range = ReportPeriodPresets.daily(DateTime.now());
            startDate = range.startDate; endDate = range.endDate; periodPreset = 'daily'; break;
        }
        _reload();
      });
    }
    final labels = <String, String>{
      if (reportType != 'containers' && periodPreset != 'daily') 'period': _periodPresetLabel(),
      if (municipality != null) 'municipality': '${tr('البلدية')}: $municipality',
      if (group != null) 'group': '${tr('المجموعة')}: $group',
      if (reportType != 'containers' && cycle != null) 'cycle': '${tr('الدورة')}: $cycle',
      if (search.isNotEmpty) 'search': '${tr('البحث')}: $search',
      if (reportType == 'containers' && containerStatus != 'all') 'status':
        '${tr('الحالة')}: ${tr(const {'full':'ممتلئة', 'partial':'نصف ممتلئة', 'empty':'فارغة', 'stale':'لم تُحدّث اليوم'}[containerStatus] ?? containerStatus)}',
    };
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final entry in labels.entries) InputChip(
        label: AppText(entry.value, maxLines: 2, overflow: TextOverflow.ellipsis),
        deleteButtonTooltipMessage: tr('إزالة هذا الفلتر'),
        onDeleted: () => remove(entry.key),
      ),
    ]);
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
            for (final entry in const {'daily':'اليوم', 'weekly':'آخر 7 أيام', 'twenty':'آخر 20 يومًا', 'monthly':'هذا الشهر'}.entries)
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
                    searchTimer?.cancel();
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
        if (filterCount > 0) ...[const SizedBox(height: 12), _filterChips()],
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
    final cards = [for (final metric in ReportContent.metrics(s))
      _k(metric.label(context.read<LocaleController>().isArabic == false), metric.value,
        switch (metric.id) { 'absence' || 'full' || 'issues' => red, 'municipalities' => gold, _ => green },
        switch (metric.id) {
          'trips' => Icons.local_shipping_outlined,
          'groups' => Icons.groups_outlined,
          'municipalities' => Icons.location_city_outlined,
          'containers' || 'full' || 'partial' || 'issues' => Icons.delete_outline,
          'cycles' => Icons.event_repeat_outlined,
          'absence' => Icons.person_off_outlined,
          _ => Icons.how_to_reg,
        }),
    ];
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
      'work' => '${s.trips} نقلة مكتملة في تقارير العمل',
      _ => '${s.completedTrips} نقلة مكتملة من ${s.trips} نقلة مسجلة',
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
        _donut(s), _rank(s.absenceByGroup, 'الحصة من إجمالي سجلات الغياب حسب المجموعة', red)]));
      case 'trips': return _section('حركة الترحيلات', Column(children: [_lineTrips(s), _comparativeBarChart(s)]));
      case 'containers': return _section('توزيع الحاويات', Column(children: [_containerStatus(s), _comparativeBarChart(s)]));
      case 'work': return _section('الأعمال خلال الفترة', Column(children: [_lineTrips(s), _comparativeBarChart(s)]));
      case 'cycles': return _section('دورات العمل', _cycleSummary(s));
      case 'municipalities': return _section('مقارنة البلديات', _comparativeBarChart(s));
      case 'groups': return _section('مقارنة المجموعات', Column(children: [
        _comparativeBarChart(s), _rank(s.absenceByGroup, 'الحصة من إجمالي سجلات الغياب', red)]));
      default: return _section('تفاصيل المشهد التشغيلي', Column(children: [
        _lineTrips(s), _comparativeBarChart(s), const Divider(height: 30), _donut(s),
        const Divider(height: 30), _containerStatus(s)]));
    }
  }

  Widget _comparativeBarChart(ReportSnapshot s) {
    final english = !context.read<LocaleController>().isArabic;
    final values = reportType == 'containers'
        ? (_compareMunicipalities ? s.containersByMunicipality : s.containersByGroup)
        : (_compareMunicipalities ? s.tripsByMunicipality : s.tripsByGroup);
    final entries = values.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (a, b) => a + b.value);
    final shown = entries.take(8).toList();
    return Padding(padding: const EdgeInsets.only(top: 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(english ? 'Share of filtered records' : 'الحصة من السجلات المطابقة للفلاتر', style: const TextStyle(fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      SegmentedButton<bool>(segments: [
        ButtonSegment(value: true, label: Text(english ? 'Municipalities' : 'البلديات')),
        ButtonSegment(value: false, label: Text(english ? 'Groups' : 'المجموعات')),
      ], selected: {_compareMunicipalities}, onSelectionChanged: (v) => setState(() => _compareMunicipalities = v.first)),
      const SizedBox(height: 14),
      if (total == 0) Text(english ? 'No records to compare.' : 'لا توجد سجلات للمقارنة.')
      else SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(
        width: shown.length * 88.0 + 42, height: 260,
        child: BarChart(BarChartData(maxY: 100, minY: 0,
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(enabled: false),
          gridData: const FlGridData(drawVerticalLine: false),
          barGroups: [for (var i = 0; i < shown.length; i++) BarChartGroupData(x: i,
            barRods: [BarChartRodData(toY: RatioMath.percent(shown[i].value, total) ?? 0, width: 25,
                color: green, borderRadius: const BorderRadius.vertical(top: Radius.circular(5)))])],
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 42, interval: 25,
                getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 10)))),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 74,
              getTitlesWidget: (v, _) {
                final index = v.round();
                if (index < 0 || index >= shown.length) return const SizedBox.shrink();
                return SizedBox(width: 82, child: Padding(padding: const EdgeInsets.only(top: 7),
                  child: Text('${shown[index].key}\n${shown[index].value} • ${RatioMath.display(RatioMath.percent(shown[index].value, total))}',
                    maxLines: 4, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10))));
              })),
          ),
        )),
      )),
      const SizedBox(height: 8),
      Text(english ? 'Denominator: all $total filtered records, including elements outside the top 8.'
          : 'المقام: جميع السجلات المطابقة ($total)، بما فيها العناصر خارج أعلى 8.', style: const TextStyle(fontSize: 11)),
      if (entries.length > 8) ExpansionTile(title: Text(english ? 'All shares' : 'جميع الحصص'),
        children: [for (final entry in entries) ListTile(title: Text(entry.key),
          trailing: Text('${entry.value} • ${RatioMath.display(RatioMath.percent(entry.value, total))}'))]),
    ]));
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
  Widget _containerStatus(ReportSnapshot s) {
    final english = !context.read<LocaleController>().isArabic;
    final counts = [s.containersFull, s.containersPartial, s.containersEmpty,
      (s.containersTotal - s.containersFull - s.containersPartial - s.containersEmpty).clamp(0, s.containersTotal)];
    final colors = [red, orange, green, Colors.blueGrey];
    final labels = english ? ['Full', 'Half full', 'Empty', 'Unknown'] : ['ممتلئة', 'نصف ممتلئة', 'فارغة', 'غير محددة'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(english ? 'Container composition' : 'التوزيع النسبي للحاويات', style: const TextStyle(fontWeight: FontWeight.w900)),
      const SizedBox(height: 12),
      if (s.containersTotal > 0) ClipRRect(borderRadius: BorderRadius.circular(7), child: Row(children: [
        for (var i = 0; i < counts.length; i++) if (counts[i] > 0)
          Expanded(flex: counts[i].toInt(), child: Container(height: 18, color: colors[i])),
      ])),
      const SizedBox(height: 10),
      Wrap(spacing: 14, runSpacing: 8, children: [for (var i = 0; i < counts.length; i++)
        Text('● ${labels[i]} ${counts[i]} • ${RatioMath.display(RatioMath.percent(counts[i], s.containersTotal))}',
            style: TextStyle(color: colors[i], fontSize: 12))]),
      const SizedBox(height: 10),
      Text(english ? 'With issues: ${s.containerIssues} (overlaps fill states)' : 'ذات مشكلات: ${s.containerIssues} (قد تتداخل مع حالات الامتلاء)',
          style: TextStyle(color: Colors.deepPurple.shade600, fontSize: 12)),
    ]);
  }
  Widget _rank(Map<String, int> map, String title, Color color) {
    final entries = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maximum = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    Widget row(MapEntry<String, int> entry, int index) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${index + 1}'.padLeft(2, '0'), style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          Expanded(child: Text(entry.key)),
          const SizedBox(width: 12),
          Text('${entry.value} • ${RatioMath.display(RatioMath.percent(entry.value, maximum))}', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15)),
        ]),
        const SizedBox(height: 7),
        ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(
          value: (maximum == 0 ? 0.0 : entry.value / maximum).clamp(0.0, 1.0), minHeight: 6,
          color: color, backgroundColor: color.withOpacity(.08))),
      ]),
    );
    return Padding(padding: const EdgeInsets.only(top: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppText(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        if (entries.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 14),
          child: AppText('لا توجد سجلات متاحة لهذه المقارنة.')),
        for (var i = 0; i < entries.length && i < 8; i++) row(entries[i], i),
        if (entries.length > 8) ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: AppText('عرض البقية (${entries.length - 8})'),
          children: [for (var i = 8; i < entries.length; i++) row(entries[i], i)]),
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
    final approved = _approvedRecord(snapshot, user) != null;
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
            onPressed: _previewing ? null : () => _previewReport(snapshot, user),
            icon: const Icon(Icons.preview_outlined),
            label: const AppText('معاينة البيانات الحالية'),
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
                  ? 'التصدير يستخدم آخر نسخة معتمدة محفوظة لهذه الفلاتر.'
                  : !user.can('reports', 'export')
                      ? 'المعاينة متاحة. التصدير الرسمي غير متاح ضمن صلاحيات حسابك.'
                      : 'التصدير الرسمي يتاح بعد اعتماد التقرير. يمكنك معاينته الآن.',
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
    if (_previewing) return;
    setState(() => _previewing = true);
    try {
      final bytes = await ReportService(context.read<DataService>()).buildOperationalPdfBytes(
        snapshot: snapshot,
        user: user,
        title: exportLanguage == 'en' ? 'Draft preview — CleanOps' : 'معاينة غير معتمدة — ${_title()}',
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
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _exportPdf(ReportSnapshot snapshot, AppUser user) async {
    final row = _approvedRecord(snapshot, user);
    if (row == null) return;
    try {
      snapshot = ReportArchive.read(row);
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
    final row = _approvedRecord(snapshot, user);
    if (row == null) return;
    try {
      snapshot = ReportArchive.read(row);
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
    final row = _approvedRecord(snapshot, user);
    if (row == null) return;
    try {
      snapshot = ReportArchive.read(row);
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
      final id = ReportArchive.documentId(snapshot, user.id);
      final returned = data.operations.any((r) => r['selectionKey'] == snapshot.reportId &&
          r['requestedBy'] == user.id && r['status'] == 'needs_edits' && r['isDeleted'] != true);
      if (returned || data.operations.any((r) => r['id'] == id && r['isDeleted'] != true)) {
        _showMessage(returned ? 'افتح التقرير المعاد لتصحيحه وإرساله.' : 'هذه النسخة موجودة في دورة الاعتماد.');
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportApprovalScreen()));
        return;
      }
      final council = await _councilForReport(user, municipality);
      if (!mounted || context.read<AuthService>().currentUser?.id != user.id || !identical(snapshot, lastSnapshot)) return;
      if (council.isEmpty) throw StateError('تعذر تحديد المجلس من سجلات البلدية. حدد البلدية المرتبطة بالمجلس.');
      await data.enqueue('report_approval', 'create', {
        'id': id, 'selectionKey': snapshot.reportId,
        'periodStart': startDate.toIso8601String(), 'periodEnd': endDate.toIso8601String(),
        'title': '${_periodPresetLabel()} — ${_title()}',
        'reportType': reportType,
        'search': snapshot.search,
        'containerStatus': snapshot.containerStatus,
        'filterLabel': snapshot.filterLabel(),
        'period': snapshot.periodLabel,
        'municipality': municipality,
        'group': group,
        'cycle': cycle,
        'requestedBy': user.id, 'requesterName': user.name,
        'municipalityCoordinatorId': user.id,
        'municipalityName': municipality ?? (user.scope != 'assigned_only' ? user.scope : ''),
        'councilName': council,
        ...ReportArchive.submission(snapshot, offline: !data.online),
        'createdAt': now,
        'status': 'submitted',
        'isDeleted': false,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('حُفظ طلب المراجعة للمزامنة. تظهر حالته بعد تأكيد الخادم.')),
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
