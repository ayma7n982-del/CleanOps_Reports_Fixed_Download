import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/data_service.dart';

/// Manual attendance entry for cycles of arbitrary length (including 60+ days).
/// Missing entries are never treated as absences.
class CycleManualAttendanceScreen extends StatefulWidget {
  final List<Map<String, dynamic>> people;
  const CycleManualAttendanceScreen({super.key, required this.people});

  @override
  State<CycleManualAttendanceScreen> createState() => _CycleManualAttendanceScreenState();
}

class _CycleManualAttendanceScreenState extends State<CycleManualAttendanceScreen> {
  DateTime start = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime end = DateTime.now();
  bool saving = false;
  final Map<String, String> edits = {};
  static const statuses = <String, String>{
    'present': 'حاضر', 'absent': 'غائب', 'late': 'متأخر', 'leave': 'إجازة',
  };

  String _date(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  DateTime _day(int offset) => DateTime(start.year, start.month, start.day + offset);
  int get dayCount => end.difference(start).inDays + 1;

  Future<void> _pick(bool beginning) async {
    final d = await showDatePicker(context: context, initialDate: beginning ? start : end,
      firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d == null || !mounted) return;
    setState(() {
      if (beginning) {
        start = d;
        if (end.isBefore(start)) end = start;
      } else {
        end = d.isBefore(start) ? start : d;
      }
      edits.clear();
    });
  }

  String _key(String id, DateTime day) => '$id|${_date(day)}';

  Future<void> _save() async {
    if (edits.isEmpty || saving) return;
    setState(() => saving = true);
    try {
      final data = context.read<DataService>();
      final now = DateTime.now().toIso8601String();
      for (final entry in edits.entries) {
        final separator = entry.key.indexOf('|');
        if (separator < 0) continue;
        final id = entry.key.substring(0, separator);
        final date = entry.key.substring(separator + 1);
        final person = widget.people.firstWhere((p) => '${p['id'] ?? ''}' == id, orElse: () => <String, dynamic>{});
        if (person.isEmpty) continue;
        await data.enqueue('attendance', 'create', <String, dynamic>{
          'id': 'manual_${id}_${date.replaceAll('-', '')}',
          'workerId': id,
          'workerName': person['name'] ?? person['username'] ?? id,
          'workerRole': person['workerRole'] ?? person['role'] ?? 'worker',
          'groupId': person['groupId'] ?? '',
          'groupName': person['groupName'] ?? '',
          'municipalityCoordinatorId': person['municipalityCoordinatorId'] ?? '',
          'municipalityName': person['municipalityName'] ?? person['municipality'] ?? '',
          'status': entry.value,
          'date': date,
          'createdAt': '${date}T12:00:00',
          'updatedAt': now,
          'source': 'manual_cycle',
          'cycleStart': _date(start),
          'cycleEnd': _date(end),
        });
      }
      if (!mounted) return;
      setState(() => edits.clear());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة المدخلات إلى قائمة المزامنة')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = context.watch<DataService>().operations.where((r) =>
      r['_entity'] == 'attendance' && r['isDeleted'] != true).toList();
    final existingByKey = <String, String>{};
    for (final row in existing) {
      final id = '${row['workerId'] ?? ''}';
      final raw = '${row['date'] ?? row['createdAt'] ?? ''}';
      if (id.isNotEmpty && raw.length >= 10) existingByKey['$id|${raw.substring(0, 10)}'] = '${row['status'] ?? ''}';
    }
    return Scaffold(
      appBar: AppBar(title: const Text('الإدخال اليدوي لدورة الحضور')),
      body: Directionality(textDirection: TextDirection.rtl, child: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: () => _pick(true), icon: const Icon(Icons.event), label: Text('بداية الدورة: ${_date(start)}')),
          OutlinedButton.icon(onPressed: () => _pick(false), icon: const Icon(Icons.event), label: Text('نهاية الدورة: ${_date(end)}')),
          Chip(label: Text('عدد الأيام: $dayCount')),
          FilledButton.icon(onPressed: saving || edits.isEmpty ? null : _save,
            icon: const Icon(Icons.save), label: Text('حفظ ${edits.length} إدخال')),
        ])),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child:
          Text('الأيام الفارغة تعني لم يُسجّل، وليست غيابًا. يمكن تمرير الجدول أفقيًا.')),
        Expanded(child: widget.people.isEmpty
          ? const Center(child: Text('لا توجد أسماء متاحة للإدخال ضمن صلاحياتك'))
          : SingleChildScrollView(scrollDirection: Axis.horizontal, child:
            SingleChildScrollView(child: DataTable(
              columnSpacing: 8,
              columns: [
                const DataColumn(label: Text('العامل / المشرف')),
                for (var d = 0; d < dayCount; d++)
                  DataColumn(label: Text('${d + 1}\n${_date(_day(d))}', textAlign: TextAlign.center)),
              ],
              rows: [
                for (final person in widget.people)
                  DataRow(cells: [
                    DataCell(SizedBox(width: 140, child: Text('${person['name'] ?? person['username'] ?? person['id'] ?? ''}'))),
                    for (var d = 0; d < dayCount; d++)
                      DataCell(SizedBox(width: 92, child: DropdownButton<String>(
                        isExpanded: true,
                        value: (() {
                          final key = _key('${person['id'] ?? ''}', _day(d));
                          final value = edits[key] ?? existingByKey[key];
                          return statuses.containsKey(value) ? value : null;
                        })(),
                        hint: const Text('—'),
                        items: [
                          const DropdownMenuItem<String>(value: '', child: Text('—')),
                          ...statuses.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
                        ],
                        onChanged: saving ? null : (value) {
                          final key = _key('${person['id'] ?? ''}', _day(d));
                          setState(() {
                            if (value == null || value.isEmpty) {
                              edits.remove(key);
                            } else {
                              edits[key] = value;
                            }
                          });
                        },
                      ))),
                  ]),
              ],
            )),
          )),
      ])),
    );
  }
}
