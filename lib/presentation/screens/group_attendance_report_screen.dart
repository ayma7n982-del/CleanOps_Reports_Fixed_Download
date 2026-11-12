import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../core/services/report_branding_store.dart';

import '../../core/models/core_models.dart';
import '../../core/localization.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/data_service.dart';
import '../../core/services/pdf_file_saver.dart';
import '../widgets/app_design.dart';

/// One group, twenty consecutive calendar days. Blank cells mean no record.
class GroupAttendanceReportScreen extends StatefulWidget {
  const GroupAttendanceReportScreen({super.key});

  @override
  State<GroupAttendanceReportScreen> createState() => _GroupAttendanceReportScreenState();
}

class _GroupAttendanceReportScreenState extends State<GroupAttendanceReportScreen> {
  DateTime start = DateTime.now().subtract(const Duration(days: 19));
  String? groupId;
  List<Map<String, dynamic>> roster = [];
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _loadRoster();
  }

  Future<void> _loadRoster() async {
    final actor = context.read<AuthService>().currentUser;
    if (actor == null || Firebase.apps.isEmpty) return;
    try {
      final people = <Map<String, dynamic>>[];
      for (final role in ['group_supervisor', 'worker']) {
        Query<Map<String, dynamic>> query = FirebaseFirestore.instance
            .collection('users').where('role', isEqualTo: role).limit(1500);
        if (actor.role == 'municipality_coordinator') {
          query = query.where('municipalityCoordinatorId', isEqualTo: actor.id);
        } else if (actor.role == 'group_supervisor' || actor.role == 'worker') {
          if ((actor.groupId ?? '').isEmpty) return;
          query = query.where('groupId', isEqualTo: actor.groupId);
        } else if (actor.role != 'donor_manager' && actor.role != 'jsc_coordinator') {
          return;
        }
        for (final doc in (await query.get()).docs) {
          final person = doc.data();
          if (person['isActive'] == false) continue;
          if (actor.role == 'jsc_coordinator') {
            final council = '${person['councilName'] ?? person['councilId'] ?? ''}';
            final municipality = '${person['municipalityName'] ?? person['municipality'] ?? ''}';
            if (actor.scope.isEmpty || actor.scope == 'all' ||
                actor.scope == 'assigned_only' ||
                (council != actor.scope && municipality != actor.scope)) continue;
          }
          people.add({'id': doc.id, ...person, 'role': role});
        }
      }
      if (mounted) setState(() => roster = people);
    } catch (_) {
      // Cached attendance remains visible when the roster cannot be fetched.
    }
  }

  DateTime? _date(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.tryParse('${raw ?? ''}');
  }

  bool _visible(Map<String, dynamic> row, AppUser actor) {
    final id = '${row['groupId'] ?? ''}'.trim();
    if (id.isEmpty) return false;
    if (actor.role == 'worker' || actor.role == 'group_supervisor') {
      return id == actor.groupId;
    }
    if (actor.role == 'municipality_coordinator') {
      final owner = '${row['municipalityCoordinatorId'] ?? ''}'.trim();
      return owner == actor.id || (owner.isEmpty && actor.scope.isNotEmpty &&
          actor.scope != 'all' && actor.scope != 'assigned_only' &&
          '${row['municipalityName'] ?? row['municipality'] ?? ''}' == actor.scope);
    }
    if (actor.role == 'jsc_coordinator') {
      return actor.scope.isNotEmpty && actor.scope != 'all' &&
          actor.scope != 'assigned_only' &&
          ('${row['councilName'] ?? row['councilId'] ?? ''}' == actor.scope ||
           '${row['municipalityName'] ?? row['municipality'] ?? ''}' == actor.scope);
    }
    return actor.role == 'donor_manager';
  }

  String _group(Map<String, dynamic> row) => '${row['groupId'] ?? ''}'.trim();
  String _name(Map<String, dynamic> row) => '${row['name'] ?? row['workerName'] ?? row['username'] ?? ''}'.trim();
  String _personId(Map<String, dynamic> row) => '${row['workerId'] ?? row['id'] ?? ''}'.trim();

  @override
  Widget build(BuildContext context) {
    final actor = context.watch<AuthService>().currentUser;
    final end = start.add(const Duration(days: 19));
    final operations = context.watch<DataService>().operations;
    final visibleRoster = actor == null ? <Map<String, dynamic>>[] : roster.where((r) => _visible(r, actor)).toList();
    final records = actor == null ? <Map<String, dynamic>>[] : operations.where((r) {
      if (r['_entity'] != 'attendance' || r['isDeleted'] == true || !_visible(r, actor)) return false;
      final day = _date(r['date'] ?? r['createdAt'] ?? r['timestamp']);
      return day != null && !day.isBefore(DateTime(start.year, start.month, start.day)) &&
          day.isBefore(end.add(const Duration(days: 1)));
    }).toList();
    final groups = <String, String>{};
    for (final r in [...visibleRoster, ...records]) {
      final id = _group(r);
      if (id.isNotEmpty) groups[id] = '${r['groupName'] ?? id}'.trim();
    }
    final selected = groupId != null && groups.containsKey(groupId) ? groupId :
        (actor?.role == 'group_supervisor' || actor?.role == 'worker') && groups.containsKey(actor?.groupId)
            ? actor!.groupId : (groups.length == 1 ? groups.keys.first : null);
    final people = <String, Map<String, dynamic>>{};
    for (final r in visibleRoster.where((r) => _group(r) == selected)) {
      final id = '${r['id'] ?? ''}'.trim();
      if (id.isNotEmpty) people[id] = r;
    }
    final relevant = records.where((r) => _group(r) == selected).toList();
    for (final r in relevant) {
      final id = _personId(r);
      if (id.isNotEmpty) people.putIfAbsent(id, () => r);
    }
    final persons = people.entries.toList()..sort((a, b) {
      final aSupervisor = '${a.value['role'] ?? a.value['workerRole'] ?? ''}' == 'group_supervisor';
      final bSupervisor = '${b.value['role'] ?? b.value['workerRole'] ?? ''}' == 'group_supervisor';
      if (aSupervisor != bSupervisor) return aSupervisor ? -1 : 1;
      return _name(a.value).compareTo(_name(b.value));
    });
    final statuses = <String, String>{};
    for (final r in relevant) {
      final day = _date(r['date'] ?? r['createdAt'] ?? r['timestamp']);
      if (day == null || _personId(r).isEmpty) continue;
      statuses['${_personId(r)}|${DateFormat('yyyy-MM-dd').format(day)}'] = '${r['status'] ?? ''}';
    }
    final metadata = [...visibleRoster, ...relevant].where((r) => _group(r) == selected).toList();
    String firstValue(List<String> fields) {
      for (final row in metadata) {
        for (final field in fields) {
          final value = '${row[field] ?? ''}'.trim();
          if (value.isNotEmpty) return value;
        }
      }
      return '';
    }
    return Scaffold(
      appBar: AppBar(title: const AppText('حضور وغياب المجموعة - 20 يومًا')),
      body: Directionality(textDirection: ui.TextDirection.rtl, child: ListView(
        padding: const EdgeInsets.all(16), children: [
          const Text('اختر المجموعة وبداية فترة التقرير. تُعرض السجلات الفعلية؛ الخانة الخالية تعني عدم وجود تسجيل.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: selected,
            decoration: const InputDecoration(labelText: 'المجموعة', border: OutlineInputBorder()),
            items: groups.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: busy ? null : (value) => setState(() => groupId = value),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: busy ? null : () async {
            final picked = await showDatePicker(context: context, initialDate: start,
                firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (picked != null && mounted) setState(() => start = picked);
          }, icon: const Icon(Icons.date_range),
          label: Text('${DateFormat('yyyy-MM-dd').format(start)} - ${DateFormat('yyyy-MM-dd').format(end)}')),
          const SizedBox(height: 12),
          Text('الأفراد: ${persons.length} • السجلات: ${relevant.length}'),
          if (selected == null) const Padding(padding: EdgeInsets.all(12), child: Text('اختر مجموعة لعرض التقرير.')),
          if (selected != null && relevant.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد سجلات حضور لهذه المجموعة في الفترة المحددة.')),
          FilledButton.icon(
            onPressed: busy || selected == null || relevant.isEmpty ? null : () async {
              setState(() => busy = true);
              try {
                final pdf = await _buildPdf(
                  persons: persons, statuses: statuses, group: groups[selected] ?? selected!,
                  municipality: firstValue(['municipalityName', 'municipality']),
                  council: firstValue(['councilName']),
                  cycle: firstValue(['cycleName', 'cycleId', 'cycle']),
                );
                if (!context.mounted) return;
                await Printing.layoutPdf(onLayout: (_) async => pdf);
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذرت معاينة التقرير: $e')));
              } finally { if (mounted) setState(() => busy = false); }
            }, icon: const Icon(Icons.preview), label: const Text('معاينة وطباعة PDF'),
          ),
          FilledButton.tonalIcon(
            onPressed: busy || selected == null || relevant.isEmpty ? null : () async {
              setState(() => busy = true);
              try {
                final pdf = await _buildPdf(
                  persons: persons, statuses: statuses, group: groups[selected] ?? selected!,
                  municipality: firstValue(['municipalityName', 'municipality']),
                  council: firstValue(['councilName']),
                  cycle: firstValue(['cycleName', 'cycleId', 'cycle']),
                );
                final path = await savePdfBytes(pdf, 'group_attendance_${selected}_${DateFormat('yyyyMMdd').format(start)}.pdf');
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(path == null ? 'تعذر حفظ PDF' : 'تم إنشاء PDF: $path')));
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تصدير التقرير: $e')));
              } finally { if (mounted) setState(() => busy = false); }
            }, icon: const Icon(Icons.picture_as_pdf), label: const Text('تصدير PDF'),
          ),
        ],
      )),
    );
  }

  Future<Uint8List> _buildPdf({
    required List<MapEntry<String, Map<String, dynamic>>> persons,
    required Map<String, String> statuses,
    required String group,
    required String municipality,
    required String council,
    required String cycle,
  }) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));
    final prefs = await ReportBrandingStore.read(municipality: municipality, council: council, project: cycle);
    pw.ImageProvider? logo(String key) {
      try {
        final encoded = prefs.getString(key);
        return encoded == null || encoded.isEmpty ? null : pw.MemoryImage(base64Decode(encoded));
      } catch (_) { return null; }
    }
    final municipalityLogo = logo('report_municipality_logo_base64');
    final councilLogo = logo('report_council_logo_base64');
    final unicefLogo = logo('report_unicef_logo_base64');
    final municipalityLabel = municipality.isNotEmpty ? municipality : (prefs.getString('report_municipality_name') ?? 'غير محددة');
    final councilLabel = council.isNotEmpty ? council : (prefs.getString('report_council_name') ?? 'غير محدد');
    final cycleLabel = cycle.isNotEmpty ? cycle : (prefs.getString('report_project_name') ?? 'غير محددة');
    final days = List.generate(20, (i) => start.add(Duration(days: i)));
    String status(String id, DateTime day) => statuses['$id|${DateFormat('yyyy-MM-dd').format(day)}'] ?? '';
    bool present(String s) => ['present', 'حضور', 'late', 'متأخر'].contains(s);
    bool absent(String s) => ['absent', 'غياب', 'excused_absence', 'unexcused_absence'].contains(s);
    bool leave(String s) => ['leave', 'on_leave', 'إجازة', 'permission', 'إذن خاص'].contains(s);
    bool mission(String s) => ['mission', 'on_duty', 'مهمة'].contains(s);
    final all = [for (final p in persons) for (final day in days) status(p.key, day)];
    final presence = all.where(present).length, absence = all.where(absent).length;
    final leaveCount = all.where(leave).length, missionCount = all.where(mission).length;
    final rate = persons.isEmpty ? 0 : (presence * 100 / (persons.length * 20)).round();
    pw.Widget label(String value, {double size = 9, PdfColor color = PdfColors.blueGrey900, bool strong = false}) =>
        pw.Text(value, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: strong ? bold : regular, fontSize: size, color: color));
    pw.Widget metric(String title, String value, PdfColor color) => pw.Expanded(child: pw.Container(
      padding: const pw.EdgeInsets.all(9), margin: const pw.EdgeInsets.only(left: 5),
      decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(7)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [label(title, size: 8), label(value, size: 17, color: color, strong: true)]),
    ));
    pw.Widget cell(String value, {PdfColor? bg, PdfColor color = PdfColors.blueGrey900, bool strong = false}) =>
        pw.Container(height: 30, alignment: pw.Alignment.center, padding: const pw.EdgeInsets.symmetric(horizontal: 3),
          color: bg, child: label(value, size: 7.6, color: color, strong: strong));
    pw.Widget mark(String s) {
      if (present(s)) return cell('ح', bg: PdfColors.green50, color: PdfColors.green700, strong: true);
      if (absent(s)) return cell('غ', bg: PdfColors.red50, color: PdfColors.red700, strong: true);
      if (leave(s)) return cell('إ', bg: PdfColors.orange50, color: PdfColors.orange800, strong: true);
      if (mission(s)) return cell('م', bg: PdfColors.purple50, color: PdfColors.purple700, strong: true);
      return cell('—', color: PdfColors.grey500);
    }
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a3.landscape, margin: const pw.EdgeInsets.all(26),
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      header: (_) => pw.Directionality(textDirection: pw.TextDirection.rtl, child: pw.Column(children: [
        pw.Container(padding: const pw.EdgeInsets.all(8), decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.teal100), borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Row(children: [
            for (final pair in [(municipalityLogo, municipalityLabel), (councilLogo, councilLabel), (unicefLogo, 'اليونيسف (UNICEF)')])
              pw.Expanded(child: pw.Row(children: [
                if (pair.$1 != null) pw.Container(width: 43, height: 43, margin: const pw.EdgeInsets.only(left: 7), child: pw.Image(pair.$1!, fit: pw.BoxFit.contain)),
                pw.Expanded(child: label(pair.$2, size: 8, strong: true)),
              ])),
          ])),
        pw.SizedBox(height: 8),
        label('تقرير حضور وغياب المجموعة', size: 16, strong: true),
        pw.SizedBox(height: 6),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          label('الدورة: $cycleLabel   •   البلدية: $municipalityLabel   •   المجموعة: $group', size: 9),
          label('الفترة: ${DateFormat('yyyy-MM-dd').format(start)} - ${DateFormat('yyyy-MM-dd').format(days.last)}', size: 9),
        ]),
        pw.SizedBox(height: 8),
        pw.Row(children: [metric('عدد الأفراد', '${persons.length}', PdfColors.teal700), metric('نسبة الحضور', '$rate%', PdfColors.green700),
          metric('إجمالي الغياب', '$absence', PdfColors.red700), metric('إجازة / مهمة', '${leaveCount + missionCount}', PdfColors.orange800)]),
        pw.SizedBox(height: 10),
      ])),
      footer: (_) => pw.Directionality(textDirection: pw.TextDirection.rtl, child: pw.Column(children: [
        pw.Divider(color: PdfColors.teal100),
        label('ح: حاضر   غ: غائب   إ: إجازة/إذن   م: مهمة   —: لا يوجد تسجيل', size: 8),
        pw.SizedBox(height: 16),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          label('إعداد مشرف المجموعة: ______________', size: 8),
          label('مراجعة منسق البلدية: ______________', size: 8),
          label('اعتماد مجلس الخدمات: ______________', size: 8),
        ]),
      ])),
      build: (_) => [pw.Directionality(textDirection: pw.TextDirection.rtl, child: pw.Table(
        border: pw.TableBorder.all(color: PdfColors.teal100, width: .5),
        columnWidths: {0: const pw.FixedColumnWidth(32), 1: const pw.FixedColumnWidth(130), 2: const pw.FixedColumnWidth(55),
          for (var i = 3; i < 23; i++) i: const pw.FixedColumnWidth(30),
          23: const pw.FixedColumnWidth(42), 24: const pw.FixedColumnWidth(42),
          25: const pw.FixedColumnWidth(42), 26: const pw.FixedColumnWidth(45)},
        children: [
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.teal700), children: [
            for (final h in ['#', 'الاسم', 'الصفة', ...days.map((d) => '${d.day}/${d.month}'), 'حضور', 'غياب', 'إجازة', 'النسبة'])
              cell(h, color: PdfColors.white, strong: true),
          ]),
          for (var i = 0; i < persons.length; i++)
            pw.TableRow(decoration: pw.BoxDecoration(color: '${persons[i].value['role'] ?? persons[i].value['workerRole']}' == 'group_supervisor'
                ? PdfColors.teal50 : PdfColors.white), children: [
              cell('${i + 1}'), cell(_name(persons[i].value), strong: true),
              cell('${persons[i].value['role'] ?? persons[i].value['workerRole']}' == 'group_supervisor' ? 'مشرف' : 'عامل'),
              for (final day in days) mark(status(persons[i].key, day)),
              cell('${days.where((d) => present(status(persons[i].key, d))).length}'),
              cell('${days.where((d) => absent(status(persons[i].key, d))).length}'),
              cell('${days.where((d) => leave(status(persons[i].key, d))).length}'),
              cell('${(days.where((d) => present(status(persons[i].key, d))).length * 100 / 20).round()}%'),
            ]),
        ],
      ))],
    ));
    return Uint8List.fromList(await doc.save());
  }
}
