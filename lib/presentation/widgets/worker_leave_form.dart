import 'recoverable_form.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/services/attendance_entry_service.dart';
import 'app_design.dart';

class WorkerLeaveSelection {
  final Map<String, String> worker;
  final DateTime day;
  final String status, reason;
  final int? fromMinute, toMinute;
  const WorkerLeaveSelection({
    required this.worker,
    required this.day,
    required this.status,
    required this.reason,
    this.fromMinute,
    this.toMinute,
  });
}

/// Deliberately has no controls for other workers' attendance or PPE.
class WorkerLeaveForm extends StatefulWidget {
  final List<Map<String, String>> workers;
  final String shift;
  final bool locked;
  final Future<Map<String, dynamic>?> Function(
    Map<String, String> worker,
    DateTime day,
  )? onLoad;
  final Future<bool> Function(WorkerLeaveSelection selection) onSave;
  const WorkerLeaveForm({
    super.key,
    required this.workers,
    required this.shift,
    required this.onSave,
    this.locked = false,
    this.onLoad,
  });
  @override
  State<WorkerLeaveForm> createState() => _WorkerLeaveFormState();
}

class _WorkerLeaveFormState extends State<WorkerLeaveForm> with RecoverableForm<WorkerLeaveForm> {
  @override String get draftId => 'worker-leave:${widget.shift}';
  @override bool get draftBusy => saving || loading;
  @override Map<String, TextEditingController> get draftFields => {'reason': reason};
  @override Map<String, dynamic> get draftValues => {
    'worker': workerId, 'day': day.toIso8601String(), 'status': status, 'dirty': dirty,
    'from': from == null ? null : from!.hour * 60 + from!.minute,
    'to': to == null ? null : to!.hour * 60 + to!.minute,
  };
  @override void restoreDraftValues(Map<String, dynamic> v) {
    final id = v['worker'];
    workerId = widget.workers.any((w) => w['id'] == id) ? id as String? : null;
    day = DateTime.tryParse('${v['day']}') ?? day;
    status = v['status'] == 'permission' ? 'permission' : 'leave';
    TimeOfDay? time(dynamic minute) => minute is int && minute >= 0 && minute < 1440
        ? TimeOfDay(hour: minute ~/ 60, minute: minute % 60) : null;
    from = time(v['from']); to = time(v['to']);
    dirty = v['dirty'] == true;
  }
  final reason = TextEditingController();
  String? workerId;
  String status = 'leave', query = '';
  DateTime day = DateTime.now();
  TimeOfDay? from, to;
  bool saving = false, dirty = false, loading = false;
  String? existingStatus;
  String? error;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> _loadSelection() async {
    final selected =
        widget.workers.where((w) => w['id'] == workerId).firstOrNull;
    if (selected == null) return;
    setState(() {
      loading = true;
      error = null;
      existingStatus = null;
    });
    try {
      final previous = await widget.onLoad?.call(selected, day);
      if (!mounted) return;
      setState(() {
        existingStatus = previous?['status'] as String?;
        status = const ['leave', 'permission'].contains(existingStatus)
            ? existingStatus!
            : 'leave';
        reason.text = '${previous?['leaveReason'] ?? ''}';
        final start = previous?['permissionFromMinute'];
        final end = previous?['permissionToMinute'];
        from = start is int
            ? TimeOfDay(hour: start ~/ 60, minute: start % 60)
            : null;
        to = end is int && end < 1440
            ? TimeOfDay(hour: end ~/ 60, minute: end % 60)
            : null;
      });
    } catch (e) {
      if (mounted) setState(() => error = 'تعذر تحميل الحالة المسجلة: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save() async {
    if (saving || loading || widget.locked) return;
    final selected = widget.workers.where((w) => w['id'] == workerId).toList();
    final start = from == null ? null : from!.hour * 60 + from!.minute;
    final end = to == null ? null : to!.hour * 60 + to!.minute;
    if (selected.length != 1) {
      setState(() => error = 'اختر العامل المطلوب أولًا.');
      return;
    }
    if (status == 'permission' &&
        (start == null || end == null || end <= start)) {
      setState(
        () => error =
            'حدد بداية الإذن ونهايته؛ يجب أن تكون النهاية بعد البداية في اليوم نفسه.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final saved = await widget.onSave(
        WorkerLeaveSelection(
          worker: selected.single,
          day: day,
          status: status,
          reason: reason.text,
          fromMinute: start,
          toMinute: end,
        ),
      );
      if (mounted && saved) {
        setState(() { dirty = false; existingStatus = status; });
        await clearFormDraft();
      }
    } catch (e) {
      if (mounted) setState(() => error = 'تعذر الحفظ: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = saving || loading || widget.locked;
    final choices = widget.workers
        .where(
          (w) =>
              query.isEmpty ||
              '${w['name']} ${w['id']}'.toLowerCase().contains(
                    query.toLowerCase(),
                  ),
        )
        .toList();
    return protectDraft(ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          AiSectionCard(
            title: 'إجازة أو إذن لعامل واحد',
            feature: 'leave',
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppText(
                    'اختر العامل وسجل حالته مباشرة. تبقى حالات بقية عمال المجموعة كما هي.',
                  ),
                  if (widget.locked)
                    const AppText(
                        'التسجيل مقفل مؤقتًا بسبب تجميد المرحلة أو بلاغ طارئ مفتوح.'),
                  const SizedBox(height: 12),
                  AppText('الوردية: ${widget.shift}'),
                  TextButton.icon(
                    key: const ValueKey('leave-date'),
                    onPressed: disabled
                        ? null
                        : () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: day,
                              firstDate: DateTime.now().subtract(
                                const Duration(days: 366),
                              ),
                              lastDate: DateTime.now().add(
                                const Duration(days: 366),
                              ),
                            );
                            if (picked != null && mounted) {
                              setState(() {
                                day = picked;
                                dirty = true;
                              });
                              await _loadSelection();
                            }
                          },
                    icon: const Icon(Icons.calendar_today),
                    label: AppText(AttendanceEntryService.dayKey(day)),
                  ),
                  TextField(
                    key: const ValueKey('leave-search'),
                    enabled: !disabled,
                    decoration: InputDecoration(
                      labelText: tr('البحث عن عامل'),
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => query = value.trim()),
                  ),
                  if (workerId != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: AppText(
                        'العامل المحدد: ${widget.workers.where((w) => w['id'] == workerId).firstOrNull?['name'] ?? ''}',
                      ),
                    ),
                  if (widget.workers.isEmpty)
                    const AppText('لا يوجد عمال متاحون ضمن مجموعتك.')
                  else if (choices.isEmpty)
                    const AppText('لا يوجد عامل مطابق للبحث.')
                  else
                    SizedBox(
                      height: 180,
                      child: ListView(
                        children: [
                          for (final worker in choices)
                            RadioListTile<String>(
                              key: ValueKey('leave-worker-${worker['id']}'),
                              value: worker['id']!,
                              groupValue: workerId,
                              title: AppText(worker['name'] ?? ''),
                              subtitle: AppText(worker['job'] ?? worker['id']!),
                              onChanged: disabled
                                  ? null
                                  : (value) async {
                                      setState(() {
                                        workerId = value;
                                        dirty = true;
                                        error = null;
                                      });
                                      await _loadSelection();
                                    },
                            ),
                        ],
                      ),
                    ),
                  if (loading) const LinearProgressIndicator(),
                  if (existingStatus != null)
                    AppText(
                      'الحالة المسجلة: ${const {
                            'present': 'حضور',
                            'absent': 'غياب',
                            'leave': 'إجازة',
                            'permission': 'إذن خاص'
                          }[existingStatus] ?? existingStatus}',
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('leave-type'),
                    value: status,
                    decoration: InputDecoration(labelText: tr('نوع التسجيل')),
                    items: const [
                      DropdownMenuItem(value: 'leave', child: AppText('إجازة')),
                      DropdownMenuItem(
                        value: 'permission',
                        child: AppText('إذن خاص'),
                      ),
                    ],
                    onChanged: disabled
                        ? null
                        : (value) => setState(() {
                              status = value!;
                              dirty = true;
                            }),
                  ),
                  if (status == 'permission')
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          key: const ValueKey('permission-from'),
                          onPressed: disabled
                              ? null
                              : () async {
                                  final value = await showTimePicker(
                                    context: context,
                                    initialTime: from ??
                                        const TimeOfDay(hour: 8, minute: 0),
                                  );
                                  if (value != null && mounted)
                                    setState(() {
                                      from = value;
                                      dirty = true;
                                    });
                                },
                          child: AppText(
                            'من: ${from?.format(context) ?? 'اختيار الوقت'}',
                          ),
                        ),
                        TextButton(
                          key: const ValueKey('permission-to'),
                          onPressed: disabled
                              ? null
                              : () async {
                                  final value = await showTimePicker(
                                    context: context,
                                    initialTime: to ??
                                        const TimeOfDay(hour: 9, minute: 0),
                                  );
                                  if (value != null && mounted)
                                    setState(() {
                                      to = value;
                                      dirty = true;
                                    });
                                },
                          child: AppText(
                            'إلى: ${to?.format(context) ?? 'اختيار الوقت'}',
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('leave-reason'),
                    controller: reason,
                    enabled: !disabled,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: tr('السبب / ملاحظة (اختياري)'),
                    ),
                    onChanged: (_) => setState(() => dirty = true),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: AppText(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const ValueKey('save-worker-leave'),
                    onPressed:
                        disabled || widget.workers.isEmpty ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: AppText(
                      saving
                          ? 'جارٍ الحفظ...'
                          : status == 'leave'
                              ? 'حفظ الإجازة'
                              : 'حفظ الإذن',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ));
  }
}
