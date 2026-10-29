import 'dart:typed_data';
import '../../core/localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import '../widgets/app_design.dart';
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
  const ReportsCenterScreen({super.key});
  @override State<ReportsCenterScreen> createState() => _ReportsCenterState();
}

class _ReportsCenterState extends State<ReportsCenterScreen> {
  late Future<ReportSnapshot> future;
  int days = 30;
  DateTime startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime endDate = DateTime.now();
  String reportType = 'all';
  String exportLanguage = 'ar';
  String periodPreset = 'custom';
  String? municipality, group, cycle;

  @override void initState() { super.initState(); _reload(); }
  void _reload() {
    final data = context.read<DataService>(); final user = context.read<AuthService>().currentUser;
    future = ReportService(data).load(days: days, startDate: startDate, endDate: endDate, user: user, municipality: municipality, group: group, cycle: cycle, reportType: reportType, reportId: _stableReportId(data));
  }
  void _refresh() => _reload();

  void _applyPeriodPreset(String preset) {
    final now = DateTime.now();
    final range = preset == 'daily'
        ? ReportPeriodPresets.daily(now)
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
    if (periodPreset == 'daily') return 'تقرير يومي';
    if (periodPreset == 'weekly') return 'تقرير أسبوعي';
    final range = ReportPeriodPresets.custom(startDate, endDate);
    return 'فترة مخصصة (${range.inclusiveDays} يوم)';
  }

  String _stableReportId(DataService data) {
    String dateKey(DateTime d) => '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    final operationKeys = data.operations.where((e) => e['isDeleted'] != true && e['reportKind'] != 'report_approval' && e['_entity'] != 'report_approval').map((e) {
      final entity = '${e['_entity'] ?? ''}';
      return '${e['id'] ?? ''}:${e['createdAt'] ?? ''}:${e['checkInAt'] ?? ''}:${e['checkOutAt'] ?? ''}:${e['trips'] ?? ''}:${e['attendance'] ?? ''}:${e['absence'] ?? ''}:${entity == 'attendance' ? e['status'] ?? '' : ''}';
    }).toList()..sort();
    final source = '${dateKey(startDate)}|${dateKey(endDate)}|$reportType|${municipality ?? 'all'}|${group ?? 'all'}|${cycle ?? 'all'}|${operationKeys.join(';')}';
    var hash = 0;
    for (final unit in source.codeUnits) { hash = (hash * 31 + unit) & 0x7fffffff; }
    return 'CO-${hash.toRadixString(16)}';
  }

  bool _isApproved(ReportSnapshot snapshot) => context.watch<DataService>().operations.any((e) =>
      '${e['id'] ?? ''}' == snapshot.reportId &&
      (e['reportKind'] == 'report_approval' || e['_entity'] == 'report_approval') &&
      ['approved', 'closed'].contains('${e['status'] ?? ''}'));

  bool _canExportOfficial(ReportSnapshot snapshot, AppUser user) =>
      ['municipality_coordinator', 'jsc_coordinator', 'donor_manager'].contains(user.role) && _isApproved(snapshot);

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
      appBar: AppBar(title: const AppText('مركز التقارير والتحليلات')), 
      body: FutureBuilder<ReportSnapshot>(future: future, builder: (context, snap) {
        if (snap.hasError) return Center(child: AppText('تعذر تحميل التقارير: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return _body(snap.data!);
      }),
    ));
  }

  Widget _body(ReportSnapshot s) {
    final u = context.read<AuthService>().currentUser!;
    return RefreshIndicator(onRefresh: () async { _refresh(); await future; }, child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 120), children: [
      _hero(s), const SizedBox(height: 12), _specializedReports(), const SizedBox(height: 12), _filters(s), const SizedBox(height: 12),
      _typeCards(), const SizedBox(height: 12), _kpis(s), const SizedBox(height: 12),
      _selectedReport(s), const SizedBox(height: 12), _charts(s), const SizedBox(height: 12), _actions(s, u),
    ]));
  }

  Widget _hero(ReportSnapshot s) => Card(color: navy, child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [
    const Icon(Icons.analytics_rounded, color: gold, size: 42), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const AppText('مركز التقارير والتحليلات', style: TextStyle(color: cleanOpsSurface, fontSize: 24, fontWeight: FontWeight.w900)),
      AppText('بيانات فعلية من العمليات والحاويات والدورات', style: const TextStyle(color: cleanOpsMuted)),
      const SizedBox(height: 5), AppText(s.periodLabel, style: const TextStyle(color: gold)),
      const SizedBox(height: 3), AppText(_periodPresetLabel(), style: const TextStyle(color: Colors.white70, fontSize: 11)),
    ])),
    IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh, color: cleanOpsSurface)),
  ])));

  Widget _specializedReports() => Wrap(spacing: 8, runSpacing: 8, children: [
    OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceReportsHomeScreen())), icon: const Icon(Icons.fact_check_outlined), label: const AppText('تقارير الحضور')),
    OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MonthlyAttendanceReportScreen())), icon: const Icon(Icons.calendar_month), label: const AppText('التقرير الشهري التقويمي')),
    OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkReportsDashboard())), icon: const Icon(Icons.assignment_turned_in_outlined), label: const AppText('لوحة تقارير العمل')),
    OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportBrandingSettingsScreen())), icon: const Icon(Icons.branding_watermark_outlined), label: const AppText('شعارات وهوية التقرير')),
    OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportApprovalScreen())), icon: const Icon(Icons.fact_check_outlined), label: const AppText('اعتماد التقارير')),
  ]);

  Widget _filters(ReportSnapshot s) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const AppText('فلاتر التقرير', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
    Wrap(spacing: 8, runSpacing: 8, children: [
      ChoiceChip(
        label: const AppText('اليوم'),
        selected: periodPreset == 'daily',
        onSelected: (_) => _applyPeriodPreset('daily'),
      ),
      ChoiceChip(
        label: const AppText('آخر 7 أيام'),
        selected: periodPreset == 'weekly',
        onSelected: (_) => _applyPeriodPreset('weekly'),
      ),
      ActionChip(
        avatar: const Icon(Icons.date_range_rounded, size: 18),
        label: AppText(_periodPresetLabel()),
        onPressed: _pickCustomPeriod,
      ),
    ]),
    const SizedBox(height: 8),
    Wrap(spacing: 8, runSpacing: 8, children: [
      _dateField('من تاريخ', startDate, (v) { if (v != null) { setState(() { periodPreset = 'custom'; startDate = v; if (endDate.isBefore(startDate)) endDate = startDate; }); _refresh(); } }),
      _dateField('إلى تاريخ', endDate, (v) { if (v != null) { setState(() { periodPreset = 'custom'; endDate = v.isBefore(startDate) ? startDate : v; }); _refresh(); } }),
      _drop<String>('لغة التصدير', exportLanguage, const {'ar':'العربية','en':'English'}, (v){if(v!=null)setState(()=>exportLanguage=v);}),
      _drop<String>('البلدية', municipality, <String?,String>{null:'كل البلديات', ...{for(final x in s.municipalityNames) x:x}}, (v){setState(() { municipality=v; group=null; }); _refresh();}),
      _drop<String>('المجموعة', group, <String?,String>{null:'كل المجموعات', ...{for(final x in _availableGroups()) x:x}}, (v){setState(()=>group=v); _refresh();}),
      _drop<String>('الدورة', cycle, <String?,String>{null:'كل الدورات', ...{for(final x in s.cycles) x:x}}, (v){setState(()=>cycle=v); _refresh();}),
    ]),
  ])));

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

  Widget _dateField(String label, DateTime value, ValueChanged<DateTime?> onPicked) => SizedBox(width: 190, child: OutlinedButton.icon(
    onPressed: () async { final picked = await showDatePicker(context: context, initialDate: value, firstDate: DateTime(2020), lastDate: DateTime(2100)); if (picked != null) onPicked(picked); },
    icon: const Icon(Icons.calendar_month), label: Text('$label: ${value.year}-${value.month.toString().padLeft(2,'0')}-${value.day.toString().padLeft(2,'0')}', overflow: TextOverflow.ellipsis),
  ));

  Widget _drop<T>(String label, T? value, Map<T?,String> items, ValueChanged<T?> onChanged) => SizedBox(width: 190, child: DropdownButtonFormField<T>(value: value, isExpanded: true, decoration: InputDecoration(labelText: label, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)), items: items.entries.map((e)=>DropdownMenuItem<T>(value:e.key, child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(), onChanged: onChanged));

  Widget _typeCards() {
    final types = <(String, String, IconData)>[
      ('all', 'كل التقارير', Icons.dashboard_customize_rounded),
      ('absence', 'الحضور والغياب', Icons.fact_check_rounded),
      ('containers', 'تقارير الحاويات', Icons.delete_sweep_rounded),
      ('work', 'تقارير العمل', Icons.local_shipping_rounded),
      ('cycles', 'دورات العمل', Icons.event_repeat_rounded),
      ('municipalities', 'تقارير البلديات', Icons.location_city_rounded),
      ('groups', 'تقارير المجموعات', Icons.groups_rounded),
    ];
    return LayoutBuilder(builder: (context, constraints) => GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: types.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: constraints.maxWidth < 300 ? 1 : 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: constraints.maxWidth < 300 ? 2.8 : 1.65,
      ),
      itemBuilder: (context, index) {
        final item = types[index];
        final selected = reportType == item.$1;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: selected
                  ? [const Color(0xFF09293A), const Color(0xFF103E4B)]
                  : [const Color(0xFF071D30), const Color(0xFF0A2A3B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: selected ? const Color(0xFF36C9AF) : Colors.white24, width: selected ? 2 : 1),
            boxShadow: selected ? [BoxShadow(color: const Color(0xFF36C9AF).withOpacity(.18), blurRadius: 14)] : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                if (item.$1 == 'absence') { Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceReportsHomeScreen())); return; }
                if (item.$1 == 'work') { Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkReportsDashboard())); return; }
                setState(() => reportType = item.$1); _refresh();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(item.$3, size: 28, color: selected ? const Color(0xFF58E3CA) : Colors.white),
                  const SizedBox(height: 7),
                  AppText(item.$2, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                ]),
              ),
            ),
          ),
        );
      },
    ));
  }

  Widget _kpis(ReportSnapshot s) => Wrap(spacing:8, runSpacing:8, children: [
    _k('الترحيلات', '${s.trips}', navy, Icons.local_shipping_outlined), _k('الحضور', '${(s.attendanceRate*100).toStringAsFixed(0)}%', green, Icons.how_to_reg), _k('الغياب','${s.absence}',red,Icons.person_off),
    _k('الحاويات','${s.containersTotal}',navy,Icons.delete_outline), _k('ممتلئة','${s.containersFull}',red,Icons.warning_amber), _k('مشكلات الحاويات','${s.containerIssues}',orange,Icons.build_circle_outlined),
    _k('المجموعات','${s.groups}',green,Icons.groups), _k('المشرفون','${s.supervisors}',aiCyan,Icons.supervisor_account), _k('العمال','${s.workers}',aiGreen,Icons.people_alt), _k('البلديات','${s.municipalities}',gold,Icons.location_city), _k('المكبات','${s.dumpsites}',orange,Icons.delete_sweep),
  ]);
  Widget _k(String a,String b,Color c,IconData icon)=>SizedBox(width:145,child:Card(child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[Icon(icon,color:c),const SizedBox(width:8),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[AppText(a,style:const TextStyle(fontSize:13)),AppText(b,style:TextStyle(fontSize:26,fontWeight:FontWeight.w900,color:c))]))]))));

  Widget _selectedReport(ReportSnapshot s) {
    switch(reportType){
      case 'absence': return _section('تقرير الغياب والحضور', Column(children:[_donut(s),_rank(s.absenceByGroup,'أعلى مجموعات الغياب',red)]));
      case 'containers': return _section('تقرير الحاويات', Column(children:[_containerStatus(s),_rank(s.containersByMunicipality,'توزيع الحاويات حسب البلدية',navy),_rank(s.containersByGroup,'توزيع الحاويات حسب المجموعة',green)]));
      case 'work': return _section('تقرير العمل والتشغيل', Column(children:[_lineTrips(s),_rank(s.tripsByGroup,'الترحيلات حسب المجموعة',green),_rank(s.tripsByMunicipality,'الترحيلات حسب البلدية',navy)]));
      case 'cycles': return _section('تقرير دورات العمل', Column(children:[_cycleSummary(s),_lineTrips(s)]));
      case 'municipalities': return _section('تقرير البلديات', _rank(s.tripsByMunicipality,'الأداء حسب البلدية',gold));
      case 'groups': return _section('تقرير المجموعات', Column(children:[_rank(s.tripsByGroup,'الترحيلات حسب المجموعة',green),_rank(s.absenceByGroup,'الغياب حسب المجموعة',red)]));
      default: return _section('نظرة تنفيذية شاملة', Column(children:[_lineTrips(s),_donut(s),_containerStatus(s)]));
    }
  }
  Widget _section(String title,Widget child)=>AiSectionCard(title:title,feature:'reports',child:child);

  Widget _charts(ReportSnapshot s)=>Column(children:[if(reportType=='all'||reportType=='municipalities'||reportType=='groups') _section('مقارنة الأداء',_bar(s)), if(reportType=='all') ...[_section('الحاويات',_containerStatus(s))]]);

  Widget _bar(ReportSnapshot s){final labels=s.tripsByGroup.keys.toList(); final vals=s.tripsByGroup.values.toList(); final data=vals.isEmpty?[0]:vals; final max=data.reduce((a,b)=>a>b?a:b); return SizedBox(height:220,child:BarChart(BarChartData(maxY:(max+2).toDouble(),barGroups:[for(var i=0;i<data.length;i++)BarChartGroupData(x:i,barRods:[BarChartRodData(toY:data[i].toDouble(),width:22,borderRadius:BorderRadius.circular(5))])],titlesData:FlTitlesData(bottomTitles:AxisTitles(sideTitles:SideTitles(showTitles:true,getTitlesWidget:(v,m)=>AppText(v.toInt()<labels.length?labels[v.toInt()]:'',style:const TextStyle(fontSize:9))))))));}
  Widget _lineTrips(ReportSnapshot s){final p=s.tripsByDay.entries.toList(); final spots=p.isEmpty?[const FlSpot(0,0)]:[for(var i=0;i<p.length;i++)FlSpot(i.toDouble(),p[i].value.toDouble())]; return SizedBox(height:210,child:LineChart(LineChartData(minY:0,lineBarsData:[LineChartBarData(spots:spots,isCurved:true,barWidth:3,dotData:const FlDotData(show:true))],titlesData:const FlTitlesData(bottomTitles:AxisTitles(sideTitles:SideTitles(showTitles:false)),rightTitles:AxisTitles(sideTitles:SideTitles(showTitles:false)),topTitles:AxisTitles(sideTitles:SideTitles(showTitles:false))))));}
  Widget _donut(ReportSnapshot s)=>SizedBox(height:220,child:PieChart(PieChartData(centerSpaceRadius:45,sections:[PieChartSectionData(value:s.attendance.toDouble().clamp(0.1,double.infinity).toDouble(),title:'حضور',radius:62),PieChartSectionData(value:s.absence.toDouble().clamp(0.1,double.infinity).toDouble(),title:'غياب',radius:62),PieChartSectionData(value:s.ppeCompliant.toDouble().clamp(0.1,double.infinity).toDouble(),title:'PPE',radius:62)])));
  Widget _containerStatus(ReportSnapshot s)=>Wrap(spacing:8,runSpacing:8,children:[_mini('فارغة',s.containersEmpty,green),_mini('جزئية',s.containersPartial,orange),_mini('ممتلئة',s.containersFull,red),_mini('مشكلات',s.containerIssues,red)]);
  Widget _mini(String t,int v,Color c)=>Container(width:125,padding:const EdgeInsets.all(12),decoration:BoxDecoration(borderRadius:BorderRadius.circular(14),border:Border.all(color:c.withOpacity(.3))),child:Column(children:[AppText(t),AppText('$v',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900,color:c))]));
  Widget _rank(Map<String,int> map,String title,Color color){ final entries=map.entries.toList()..sort((a,b)=>b.value.compareTo(a.value)); return Padding(padding:const EdgeInsets.only(top:10),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[AppText(title,style:const TextStyle(fontWeight:FontWeight.w900)),...entries.take(7).map((e)=>ListTile(dense:true,leading:Icon(Icons.circle,size:10,color:color),title:AppText(e.key),trailing:AppText('${e.value}',style:TextStyle(fontWeight:FontWeight.w900,color:color))))])); }
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

  Widget _actions(ReportSnapshot s, AppUser u)=>_section('التصدير والاعتماد',Wrap(spacing:8,runSpacing:8,children:[OutlinedButton.icon(
  onPressed: u.can('reports', 'create')
      ? () => _createSmartDraft(s, u)
      : null,
  icon: const Icon(Icons.auto_awesome_rounded),
  label: const AppText('حفظ مسودة ذكية'),
),OutlinedButton.icon(onPressed:()async{final bytes=await ReportService(context.read<DataService>()).buildOperationalPdfBytes(snapshot:s,user:u,title:'${_title()} — CleanOps', languageCode: exportLanguage);if(!mounted)return;Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(title:const AppText('معاينة التقرير')),body:PdfPreview(build:(_)=>Uint8List.fromList(bytes)))));},icon:const Icon(Icons.preview_outlined),label:const AppText('معاينة / طباعة')),FilledButton.icon(onPressed:_canExportOfficial(s,u)?()async{try{final path=await ReportService(context.read<DataService>()).exportOperationalPdf(snapshot:s,user:u,title:'${_title()} — CleanOps', languageCode: exportLanguage);if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:AppText(path==null?'تعذر إنشاء PDF':'تم إنشاء PDF: $path')));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:AppText('فشل إنشاء PDF: $e')));}}:null,icon:const Icon(Icons.picture_as_pdf),label:const AppText('تصدير PDF')),OutlinedButton.icon(onPressed:_canExportOfficial(s,u)?()async{try{final path=await ReportService(context.read<DataService>()).exportOperationalExcel(snapshot:s,user:u,languageCode:exportLanguage);if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:AppText(path==null?'تعذر إنشاء Excel':'تم إنشاء Excel: $path')));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:AppText('فشل تصدير Excel: $e')));}}:null,icon:const Icon(Icons.table_view_outlined),label:const AppText('تصدير Excel')),OutlinedButton.icon(onPressed:_canExportOfficial(s,u)?()async{try{final path=await ReportService(context.read<DataService>()).exportOperationalCsv(snapshot:s,user:u,languageCode:exportLanguage);if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:AppText(path==null?'تعذر إنشاء CSV':'تم إنشاء CSV: $path')));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:AppText('فشل تصدير CSV: $e')));}}:null,icon:const Icon(Icons.file_download_outlined),label:const AppText('تصدير CSV')),OutlinedButton.icon(onPressed:u.role == 'municipality_coordinator' ? ()async{final now=DateTime.now().toIso8601String();await context.read<DataService>().enqueue('report_approval','create',{'id':s.reportId,'title':'${_periodPresetLabel()} — ${_title()}','reportType':reportType,'period':s.periodLabel,'municipality':municipality,'group':group,'cycle':cycle,'requestedBy':u.id,'municipalityCoordinatorId':u.id,'municipalityName': municipality ?? (u.scope != 'assigned_only' ? u.scope : ''),'councilName': _councilForReport(municipality ?? u.scope),'snapshot': {'trips': s.trips, 'attendance': s.attendance, 'absence': s.absence, 'workers': s.workers, 'supervisors': s.supervisors, 'groups': s.groups, 'containers': s.containersTotal, 'emergencies': s.emergencies},'createdAt':now,'status':'submitted','isDeleted':false});await context.read<DataService>().writeAudit(actorId:u.id,operation:'REQUEST_REPORT_APPROVAL',targetId:s.reportId,after:{'reportType':reportType,'period':s.periodLabel,'periodPreset':periodPreset,'status':'submitted','municipality':municipality,'group':group,'cycle':cycle});if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:AppText('تم إرسال التقرير إلى دورة المراجعة.')));Navigator.push(context,MaterialPageRoute(builder:(_)=>const ReportApprovalScreen()));}} : null,icon:const Icon(Icons.verified_outlined),label:const AppText('إرسال التقرير للمراجعة'))]));
  String _title()=>switch(reportType){'absence'=>'تقرير الغياب والحضور','containers'=>'تقرير الحاويات','work'=>'تقرير العمل والتشغيل','cycles'=>'تقرير الدورات','municipalities'=>'تقرير البلديات','groups'=>'تقرير المجموعات',_=>'التقرير التنفيذي الشامل'};
}
