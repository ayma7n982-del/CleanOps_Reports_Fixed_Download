import '../widgets/recoverable_form.dart';
import '../widgets/app_navigation_bar.dart';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/core_models.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/config_service.dart';
import '../../core/services/data_service.dart';
import '../../core/localization.dart';
import '../../core/services/work_report_sources.dart';
import '../../core/services/work_report_summary.dart';
import '../widgets/work_report_summary_card.dart';
import 'level1_supervisor.dart';

class WorkEntryFormScreen extends StatefulWidget {
  const WorkEntryFormScreen({super.key});
  @override
  State<WorkEntryFormScreen> createState() => _WorkEntryFormScreenState();
}

class _WorkEntryFormScreenState extends State<WorkEntryFormScreen> with RecoverableForm<WorkEntryFormScreen> {
  @override String get draftId => 'daily-work';
  @override bool get draftBusy => _saving;
  @override Map<String, TextEditingController> get draftFields => {
    'group': _group, 'tasks': _tasks, 'landfill': _landfill, 'containers': _containers,
    'locations': _locations, 'completed': _completed, 'problems': _problems, 'suggestions': _suggestions,
  };
  @override Map<String, dynamic> get draftValues => {
    'date': _workDate.toIso8601String(), 'cycle': _cycleId, 'shift': _shift, 'groupName': _groupName,
  };
  @override void restoreDraftValues(Map<String, dynamic> v) {
    _workDate = DateTime.tryParse('${v['date']}') ?? _workDate;
    _cycleId = v['cycle'] as String? ?? '';
    _shift = v['shift'] as String? ?? _shift;
    _groupName = v['groupName'] as String? ?? _group.text;
    _sources.bind(_group.text);
  }
  final _group = TextEditingController();
  final _tasks = TextEditingController();
  final _landfill = TextEditingController();
  final _containers = TextEditingController();
  final _locations = TextEditingController();
  final _completed = TextEditingController();
  final _problems = TextEditingController();
  final _suggestions = TextEditingController();
  bool _saving = false;
  late final WorkReportSources _sources;
  String _shift = '', _groupName = '';
  Stream<QuerySnapshot<Map<String, dynamic>>>? _groupsStream;
  DateTime _workDate = DateTime.now();
  String _cycleId = '';
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _cycles = [];

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthService>().currentUser;
    _group.text = user?.role == 'group_supervisor' ? (user?.groupId ?? '') : '';
    _groupName = _group.text;
    _shift = context.read<ConfigService>().shift;
    _sources = WorkReportSources(context.read<DataService>())
      ..addListener(_sourcesChanged);
    _sources.bind(_group.text);
    if (user?.role == 'municipality_coordinator' && Firebase.apps.isNotEmpty) {
      _groupsStream = FirebaseFirestore.instance
          .collection('operations')
          .where('_entity', isEqualTo: 'group')
          .where('municipalityCoordinatorId', isEqualTo: user!.id)
          .snapshots();
    }
    _loadCycles();
  }

  Future<void> _loadCycles() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('work_cycles')
          .where('status', isEqualTo: 'active')
          .limit(100)
          .get();
      if (!mounted) return;
      setState(() {
        _cycles = snap.docs;
      });
    } catch (_) {}
  }

  void _sourcesChanged() {
    if (mounted) setState(() {});
  }

  WorkReportSummary get _summary => WorkReportSummary.build(
    records: _sources.records,
    groupId: _group.text.trim(),
    day: _workDate,
    shift: _shift,
    serverConfirmed: _sources.serverConfirmed,
  );
  @override
  void dispose() {
    _sources.removeListener(_sourcesChanged);
    _sources.dispose();
    for (final c in [
      _group,
      _tasks,
      _landfill,
      _containers,
      _locations,
      _completed,
      _problems,
      _suggestions,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _selectedCycleName {
    for (final c in _cycles) {
      if (c.id == _cycleId) return '${c.data()['name'] ?? c.id}';
    }
    return '';
  }

  Future<void> _save() async {
    if (_saving) return;
    final auth = context.read<AuthService>();
    final AppUser? user = auth.currentUser;
    if (user == null) return;
    if (user.role != 'group_supervisor' &&
        user.role != 'municipality_coordinator') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('ليس لديك صلاحية تسجيل تقرير العمل.')),
      );
      return;
    }
    if (_group.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('اختر المجموعة المسجلة أولًا.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final summary = _summary;
      final duplicate = _sources.records.any(
        (r) =>
            WorkReportSummary.isWorkReport(r) &&
            r['isDeleted'] != true &&
            r['recordType'] == 'daily_work' &&
            WorkReportSummary.dayKey(
                  WorkReportSummary.date(r['workDate']) ?? DateTime(1900),
                ) ==
                WorkReportSummary.dayKey(_workDate) &&
            ('${r['shift'] ?? ''}'.isEmpty || r['shift'] == _shift),
      );
      if (duplicate)
        throw StateError(
          'يوجد تقرير لهذه المجموعة والتاريخ والوردية. راجعه من لوحة تقارير العمل.',
        );
      if (user.role == 'group_supervisor' && _group.text.trim() != user.groupId)
        throw StateError('اختر مجموعتك المخصصة فقط.');
      Map<String, dynamic> profile = <String, dynamic>{};
      if (Firebase.apps.isNotEmpty) {
        try {
          final profileSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.id)
              .get(
                context.read<DataService>().online
                    ? const GetOptions()
                    : const GetOptions(source: Source.cache),
              )
              .timeout(const Duration(seconds: 5));
          profile = profileSnap.data() ?? <String, dynamic>{};
        } catch (_) {
          /* Offline entry remains possible; scope metadata is kept conservative. */
        }
      }
      final coordinatorId =
          '${profile['municipalityCoordinatorId'] ?? user.municipalityCoordinatorId ?? (user.role == 'municipality_coordinator' ? user.id : '')}'
              .trim();
      Map<String, dynamic> coordinatorProfile = <String, dynamic>{};
      if (Firebase.apps.isNotEmpty &&
          coordinatorId.isNotEmpty &&
          coordinatorId != user.id) {
        try {
          final coordinatorSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(coordinatorId)
              .get(
                context.read<DataService>().online
                    ? const GetOptions()
                    : const GetOptions(source: Source.cache),
              )
              .timeout(const Duration(seconds: 5));
          coordinatorProfile = coordinatorSnap.data() ?? <String, dynamic>{};
        } catch (_) {
          /* Use metadata already present in the cached profile when offline. */
        }
      }
      final profileMunicipality =
          '${profile['municipalityName'] ?? profile['municipality'] ?? coordinatorProfile['municipalityName'] ?? coordinatorProfile['municipality'] ?? ''}'
              .trim();
      final scopeMunicipality =
          user.scope.trim().isNotEmpty &&
              user.scope != 'assigned_only' &&
              user.scope != 'all'
          ? user.scope.trim()
          : '';
      final municipalityName = profileMunicipality.isNotEmpty
          ? profileMunicipality
          : scopeMunicipality;
      final councilName =
          '${profile['councilName'] ?? profile['council'] ?? coordinatorProfile['councilName'] ?? coordinatorProfile['council'] ?? ''}'
              .trim();
      final councilId =
          '${profile['councilId'] ?? coordinatorProfile['councilId'] ?? ''}'
              .trim();
      final record = <String, dynamic>{
        'id': const Uuid().v4(),
        'recordType': 'daily_work',
        'status': 'draft',
        'groupName': _groupName,
        'groupId': _group.text.trim(),
        'shift': _shift,
        'municipalityName': municipalityName,
        'municipalityCoordinatorId': coordinatorId,
        'councilName': councilName,
        'councilId': councilId,
        'cycleId': _cycleId,
        'cycleName': _selectedCycleName,
        'reportedBy': user.id,
        'reporterName': user.name,
        ...summary.counts,
        'sourceSnapshot': summary.snapshot(),
        'countsMode': 'operational_sources_v1',
        'workTasks': _tasks.text.trim(),
        'landfillStatus': _landfill.text.trim(),
        'containerStatus': _containers.text.trim(),
        'workLocations': _locations.text.trim(),
        'completedWork': _completed.text.trim(),
        'problems': _problems.text.trim(),
        'suggestions': _suggestions.text.trim(),
        'createdAt': now.toIso8601String(),
        'workDate': DateTime(
          _workDate.year,
          _workDate.month,
          _workDate.day,
        ).toIso8601String(),
        'isDeleted': false,
      };
      await context.read<DataService>().enqueue(
        'work_report',
        'create',
        record,
      );
      await clearFormDraft();
      await context.read<DataService>().addActivity(
        'تقرير العمل اليومي',
        'حُفظ تقرير مجموعة ${_groupName} للمراجعة.',
        level: 'success',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('تم حفظ تقرير العمل في قائمة المزامنة بحالة مسودة.'),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: AppText('تعذر حفظ تقرير العمل: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => protectDraft(Scaffold(
    appBar: AppBar(
      bottom: const AppNavigationBar(),
      title: const AppText('تسجيل تقرير العمل اليومي'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const AppText(
          'اختر المجموعة والتاريخ والوردية. تُجمع الأعداد من سجلاتها تلقائيًا؛ أضف وصف العمل والملاحظات ثم احفظ المسودة.',
          style: TextStyle(height: 1.45),
        ),
        const SizedBox(height: 12),
        _groupPicker(),
        OutlinedButton.icon(
          onPressed: _saving
              ? null
              : () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _workDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null && mounted)
                    setState(() => _workDate = picked);
                },
          icon: const Icon(Icons.calendar_month),
          label: Text(
            'تاريخ العمل: ${_workDate.year}-${_workDate.month.toString().padLeft(2, '0')}-${_workDate.day.toString().padLeft(2, '0')}',
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _cycles.any((c) => c.id == _cycleId) ? _cycleId : null,
          items: _cycles
              .map(
                (c) => DropdownMenuItem(
                  value: c.id,
                  child: Text('${c.data()['name'] ?? c.id}'),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _cycleId = v ?? ''),
          decoration: const InputDecoration(
            labelText: 'دورة العمل',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        _shiftPicker(),
        WorkReportSummaryCard(summary: _summary, sourceError: _sources.error),
        if (context.read<AuthService>().currentUser?.role == 'group_supervisor')
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const Level1SupervisorScreen(
                            initialAction: 'attendance',
                          ),
                        ),
                      ),
                icon: const Icon(Icons.people_outline),
                label: const AppText('استكمال كشف الحضور'),
              ),
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const Level1SupervisorScreen(
                            initialAction: 'trips',
                          ),
                        ),
                      ),
                icon: const Icon(Icons.local_shipping_outlined),
                label: const AppText('سجل النقلات'),
              ),
            ],
          ),
        TextButton.icon(
          onPressed: _saving
              ? null
              : () {
                  final s = _summary;
                  final text =
                      'توثق سجلات المجموعة بتاريخ ${WorkReportSummary.dayKey(_workDate)} في الوردية $_shift: حضور ${s.counts['attendance'] ?? 'غير مكتمل'}، وغياب دون إجازات ${s.counts['absence'] ?? 'غير مكتمل'}، ونقلات مكتملة ${s.counts['trips'] ?? 'غير مكتمل'}، ونقلات جارية ${s.activeTrips}. ${s.issues.isEmpty ? '' : 'توجد سجلات تحتاج مراجعة قبل الإرسال.'}';
                  if (_completed.text.trim().isEmpty) {
                    _completed.text = text;
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: AppText(
                          'حقل الإنجاز يحتوي نصًا؛ راجعه قبل إضافة ملخص جديد.',
                        ),
                      ),
                    );
                  }
                },
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const AppText('صياغة ملخص من الأرقام الحالية'),
        ),
        _field(_tasks, 'المهام المنفذة / المخطط لها', lines: 3),
        _field(_landfill, 'حالة المكب'),
        _field(_containers, 'حالة الحاويات'),
        _field(_locations, 'مواقع العمل'),
        _field(_completed, 'الأعمال المكتملة', lines: 3),
        _field(_problems, 'المشكلات أو العوائق', lines: 3),
        _field(_suggestions, 'المقترحات', lines: 3),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: const AppText('حفظ المسودة'),
        ),
      ],
    ),
  ));
  Widget _groupPicker() {
    final user = context.read<AuthService>().currentUser;
    if (user?.role != 'municipality_coordinator')
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'المجموعة المخصصة',
            border: OutlineInputBorder(),
          ),
          child: AppText(
            _groupName.isEmpty ? 'لم تُخصص مجموعة للحساب' : _groupName,
          ),
        ),
      );
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _groupsStream,
      builder: (context, snap) {
        final groups =
            snap.data?.docs
                .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
                .toList() ??
            context
                .read<DataService>()
                .operations
                .where(
                  (r) =>
                      r['_entity'] == 'group' &&
                      r['municipalityCoordinatorId'] == user!.id,
                )
                .toList();
        final visible = groups
            .where((r) => r['isDeleted'] != true && r['isActive'] != false)
            .toList();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DropdownButtonFormField<String>(
            value: visible.any((r) => r['id'] == _group.text)
                ? _group.text
                : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'مجموعة من بلديتك *',
              border: const OutlineInputBorder(),
              helperText: snap.hasError
                  ? 'تعذر تحديث القائمة؛ المتاح من الجهاز ظاهر'
                  : null,
            ),
            items: visible
                .map(
                  (r) => DropdownMenuItem(
                    value: '${r['id']}',
                    child: AppText(
                      '${r['name'] ?? r['groupName'] ?? r['number'] ?? r['id']}',
                    ),
                  ),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) {
                    if (value == null) return;
                    final selected = visible.firstWhere(
                      (r) => r['id'] == value,
                    );
                    setState(() {
                      _group.text = value;
                      _groupName =
                          '${selected['name'] ?? selected['groupName'] ?? selected['number'] ?? value}';
                      _sources.bind(value);
                    });
                  },
          ),
        );
      },
    );
  }

  Widget _shiftPicker() {
    final values = <String>{
      _shift,
      context.read<ConfigService>().shift,
      for (final r in _sources.records)
        if (r['_entity'] == 'attendance' || r['_entity'] == 'trip')
          '${r['shift'] ?? ''}',
    }..remove('');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: values.contains(_shift) ? _shift : null,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'الوردية',
          border: OutlineInputBorder(),
        ),
        items: values
            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
            .toList(),
        onChanged: _saving
            ? null
            : (value) => setState(() => _shift = value ?? _shift),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool numeric = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: c,
      keyboardType: numeric ? TextInputType.number : TextInputType.multiline,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}
