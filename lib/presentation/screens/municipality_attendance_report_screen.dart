import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/data_service.dart';
import '../../core/services/pdf_file_saver.dart';
import '../widgets/app_design.dart';

/// Municipality roster and its actual attendance entries for twenty days.
class MunicipalityAttendanceReportScreen extends StatefulWidget {
  const MunicipalityAttendanceReportScreen({super.key});

  @override
  State<MunicipalityAttendanceReportScreen> createState() => _MunicipalityAttendanceReportScreenState();
}

class _MunicipalityAttendanceReportScreenState extends State<MunicipalityAttendanceReportScreen> {
  DateTime start = DateTime.now().subtract(const Duration(days: 19));
  List<Map<String, dynamic>> roster = [];
  bool loading = true;
  bool busy = false;
  String? loadError;

  @override
  void initState() {
    super.initState();
    _loadRoster();
  }

  String _value(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = '${row[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _name(Map<String, dynamic> row) => _value(row, ['name', 'workerName', 'username']);
  bool _hasRealName(Map<String, dynamic> row) {
    final name = _name(row);
    if (name.isEmpty || name == '${row['id']}') return false;
    return !RegExp(r'^(عامل|مشرف|worker|supervisor)\s*[-#]?\s*\d+$', caseSensitive: false).hasMatch(name);
  }
  String _day(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  DateTime? _date(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.tryParse('${raw ?? ''}');
  }

  Future<void> _loadRoster() async {
    final actor = context.read<AuthService>().currentUser;
    if (actor == null || actor.role != 'municipality_coordinator') {
      if (mounted) setState(() { loading = false; loadError = 'هذا التقرير متاح لمنسق البلدية فقط.'; });
      return;
    }
    if (Firebase.apps.isEmpty) {
      if (mounted) setState(() { loading = false; loadError = 'تعذر الاتصال بقاعدة بيانات الأسماء.'; });
      return;
    }
    if (mounted) setState(() { loading = true; loadError = null; });
    try {
      final people = <Map<String, dynamic>>[];
      for (final role in ['group_supervisor', 'worker', 'worker_with_cart']) {
        final query = await FirebaseFirestore.instance.collection('users')
            .where('role', isEqualTo: role)
            .where('municipalityCoordinatorId', isEqualTo: actor.id)
            .limit(1500).get();
        for (final doc in query.docs) {
          final data = doc.data();
          if (data['isActive'] == false) continue;
          people.add({...data, 'id': doc.id, 'reportRole': role});
        }
      }
      if (mounted) setState(() { roster = people; loading = false; });
    } catch (_) {
      if (mounted) setState(() {
        roster = [];
        loading = false;
        loadError = 'تعذر تحميل أسماء البلدية. تحقق من الاتصال والصلاحية ثم أعد المحاولة.';
      });
    }
  }

  String _kind(String status) {
    if (['present', 'حضور', 'late', 'متأخر'].contains(status)) return 'ح';
    if (['absent', 'غياب', 'excused_absence', 'unexcused_absence'].contains(status)) return 'غ';
    if (['leave', 'on_leave', 'إجازة', 'permission', 'إذن خاص'].contains(status)) return 'إ';
    if (['mission', 'on_duty', 'مهمة'].contains(status)) return 'م';
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final actor = context.watch<AuthService>().currentUser;
    final operations = context.watch<DataService>().operations;
    final end = start.add(const Duration(days: 19));
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final person in roster) {
      final group = _value(person, ['groupId']);
      if (group.isNotEmpty) groups.putIfAbsent(group, () => []).add(person);
    }
    final ids = roster.map((p) => '${p['id']}').toSet();
    final entries = <String, String>{};
    for (final row in operations) {
      if (row['_entity'] != 'attendance' || row['isDeleted'] == true) continue;
      final id = _value(row, ['workerId']);
      if (!ids.contains(id)) continue;
      final date = _date(row['date'] ?? row['createdAt'] ?? row['timestamp']);
      if (date == null || date.isBefore(DateTime(start.year, start.month, start.day)) ||
          !date.isBefore(DateTime(end.year, end.month, end.day + 1))) continue;
      entries['$id|${_day(date)}'] = _kind(_value(row, ['status']));
    }
    final missingNames = roster.where((p) => !_hasRealName(p)).length;
    final missingGroups = roster.length - groups.values.fold<int>(0, (sum, people) => sum + people.length);
    final ready = actor?.role == 'municipality_coordinator' && !loading && loadError == null &&
        roster.isNotEmpty && groups.isNotEmpty && missingNames == 0 && missingGroups == 0 && entries.isNotEmpty;
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      appBar: AppBar(title: const AppText('حضور وغياب البلدية - 20 يومًا')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('ملخص البلدية ثم كشف مستقل لكل مجموعة، يشمل المشرفين والعمال بأسمائهم المسجلة.'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy ? null : () async {
            final picked = await showDatePicker(context: context, initialDate: start,
                firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (picked != null && mounted) setState(() => start = picked);
          },
          icon: const Icon(Icons.date_range),
          label: Text('${_day(start)} — ${_day(end)}'),
        ),
        const SizedBox(height: 12),
        Text('المجموعات: ${groups.length} • الأفراد: ${roster.length} • تسجيلات الفترة: ${entries.length}'),
        if (loading) const LinearProgressIndicator(),
        if (loadError != null) Text(loadError!, style: const TextStyle(color: Colors.red)),
        if (!loading && loadError == null && roster.isEmpty) const Text('لا توجد أسماء مسجلة لهذه البلدية.'),
        if (missingNames > 0) Text('يوجد $missingNames فردًا بلا اسم فعلي أو باسم تجريبي. أكمل الأسماء قبل التصدير.'),
        if (missingGroups > 0) Text('يوجد $missingGroups فردًا بلا مجموعة. أكمل المجموعة قبل التصدير.'),
        if (!loading && roster.isNotEmpty && entries.isEmpty) const Text('لا توجد سجلات حضور في الفترة المختارة.'),
        TextButton.icon(onPressed: busy || loading ? null : _loadRoster,
            icon: const Icon(Icons.refresh), label: const Text('تحديث الأسماء')),
        FilledButton.icon(onPressed: !ready || busy ? null : () => _produce(groups, entries, preview: true),
            icon: const Icon(Icons.preview), label: const Text('معاينة وطباعة PDF')),
        FilledButton.tonalIcon(onPressed: !ready || busy ? null : () => _produce(groups, entries, preview: false),
            icon: const Icon(Icons.picture_as_pdf), label: const Text('تصدير PDF')),
      ]),
    ));
  }

  Future<void> _produce(Map<String, List<Map<String, dynamic>>> groups,
      Map<String, String> entries, {required bool preview}) async {
    setState(() => busy = true);
    try {
      final bytes = await _pdf(groups, entries);
      if (preview) {
        if (mounted) await Printing.layoutPdf(onLayout: (_) async => bytes);
      } else {
        final path = await savePdfBytes(bytes, 'municipality_attendance_${_day(start)}.pdf');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(path == null ? 'تعذر حفظ PDF' : 'تم إنشاء PDF: $path')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إنشاء التقرير: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Uint8List> _pdf(Map<String, List<Map<String, dynamic>>> groups,
      Map<String, String> entries) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));
    final prefs = await SharedPreferences.getInstance();
    pw.ImageProvider? logo(String key) {
      try {
        final raw = prefs.getString(key);
        return raw == null || raw.isEmpty ? null : pw.MemoryImage(base64Decode(raw));
      } catch (_) { return null; }
    }
    final municipality = _value(roster.first, ['municipalityName', 'municipality']).isNotEmpty
        ? _value(roster.first, ['municipalityName', 'municipality'])
        : prefs.getString('report_municipality_name') ?? 'البلدية';
    final council = _value(roster.first, ['councilName']).isNotEmpty
        ? _value(roster.first, ['councilName']) : prefs.getString('report_council_name') ?? 'المجلس';
    final cycle = _value(roster.first, ['cycleName', 'cycleId', 'cycle']).isNotEmpty
        ? _value(roster.first, ['cycleName', 'cycleId', 'cycle'])
        : prefs.getString('report_project_name') ?? 'غير محددة';
    final logos = [logo('report_municipality_logo_base64'), logo('report_council_logo_base64'), logo('report_unicef_logo_base64')];
    final days = List.generate(20, (i) => start.add(Duration(days: i)));
    String mark(Map<String, dynamic> person, DateTime day) => entries['${person['id']}|${_day(day)}'] ?? '—';
    int count(List<Map<String, dynamic>> people, String kind) => people.fold(0,
        (sum, p) => sum + days.where((day) => mark(p, day) == kind).length);
    pw.Widget txt(String value, {bool strong = false, double size = 8, PdfColor color = PdfColors.blueGrey900}) =>
        pw.Text(value, textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: strong ? bold : regular, fontSize: size, color: color));
    pw.Widget cell(String value, {bool strong = false, PdfColor color = PdfColors.blueGrey900}) =>
        pw.Container(alignment: pw.Alignment.center, height: 28,
            padding: const pw.EdgeInsets.symmetric(horizontal: 3), child: txt(value, strong: strong, size: 7.5, color: color));
    pw.Widget heading(String title) => pw.Directionality(textDirection: pw.TextDirection.rtl,
        child: pw.Column(children: [
          pw.Container(padding: const pw.EdgeInsets.all(7),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.teal100)),
              child: pw.Row(children: [
                for (var i = 0; i < 3; i++) pw.Expanded(child: pw.Row(children: [
                  if (logos[i] != null) pw.Container(width: 38, height: 38,
                      margin: const pw.EdgeInsets.only(left: 7), child: pw.Image(logos[i]!, fit: pw.BoxFit.contain)),
                  pw.Expanded(child: txt([municipality, council, 'اليونيسف UNICEF'][i], strong: true)),
                ])),
              ])),
          pw.SizedBox(height: 8), txt(title, strong: true, size: 16),
          pw.SizedBox(height: 4), txt('الدورة: $cycle   •   الفترة: ${_day(start)} — ${_day(days.last)}', size: 9),
          pw.SizedBox(height: 9),
        ]));
    pw.Widget footer(pw.Context context) => pw.Directionality(textDirection: pw.TextDirection.rtl,
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          txt('ح: حضور  •  غ: غياب  •  إ: إجازة/إذن  •  م: مهمة  •  —: لا يوجد تسجيل'),
          txt('صفحة ${context.pageNumber} من ${context.pagesCount}'),
        ]));
    final doc = pw.Document();
    final sorted = groups.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final all = sorted.expand((e) => e.value).toList();
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a3.landscape,
        margin: const pw.EdgeInsets.all(26), textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        header: (_) => heading('تقرير حضور وغياب البلدية'), footer: footer,
        build: (_) => [
          pw.Directionality(textDirection: pw.TextDirection.rtl, child: pw.Row(children: [
            for (final metric in ['${sorted.length} مجموعات', '${all.length} فردًا', '${count(all, 'ح')} حضور',
              '${count(all, 'غ')} غياب', '${count(all, 'إ')} إجازة', '${count(all, 'م')} مهمة'])
              pw.Expanded(child: pw.Container(padding: const pw.EdgeInsets.all(13),
                  margin: const pw.EdgeInsets.only(left: 6), color: PdfColors.teal50,
                  child: txt(metric, strong: true, size: 11))),
          ])),
          pw.SizedBox(height: 15),
          pw.Directionality(textDirection: pw.TextDirection.rtl, child: pw.Table(
            border: pw.TableBorder.all(color: PdfColors.teal100, width: .5), children: [
              pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.teal700),
                  children: [for (final h in ['المجموعة', 'المشرف', 'العمال', 'حضور', 'غياب', 'إجازة', 'مهمة', 'بدون تسجيل'])
                    cell(h, strong: true, color: PdfColors.white)]),
              for (final group in sorted) pw.TableRow(children: [
                cell(_value(group.value.first, ['groupName']).isNotEmpty
                    ? _value(group.value.first, ['groupName']) : group.key),
                cell(group.value.where((p) => p['reportRole'] == 'group_supervisor').map(_name).join('، ')),
                cell('${group.value.where((p) => p['reportRole'] != 'group_supervisor').length}'),
                for (final kind in ['ح', 'غ', 'إ', 'م', '—']) cell('${count(group.value, kind)}'),
              ]),
            ])),
          pw.SizedBox(height: 18),
          txt('كل صفحة تالية تعرض أسماء مشرفي وعمال المجموعة وحالتهم في الأيام العشرين. الخانات الخالية من التسجيل محددة بشرطة.', size: 9),
        ]));
    for (final group in sorted) {
      final people = [...group.value]..sort((a, b) {
        if (a['reportRole'] != b['reportRole']) return a['reportRole'] == 'group_supervisor' ? -1 : 1;
        return _name(a).compareTo(_name(b));
      });
      final name = _value(people.first, ['groupName']).isNotEmpty ? _value(people.first, ['groupName']) : group.key;
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a3.landscape,
          margin: const pw.EdgeInsets.all(26), textDirection: pw.TextDirection.rtl,
          theme: pw.ThemeData.withFont(base: regular, bold: bold),
          header: (_) => heading('كشف المجموعة: $name'), footer: footer,
          build: (_) => [
            pw.Directionality(textDirection: pw.TextDirection.rtl, child: pw.Table(
              border: pw.TableBorder.all(color: PdfColors.teal100, width: .5),
              columnWidths: {0: const pw.FixedColumnWidth(28), 1: const pw.FixedColumnWidth(160),
                2: const pw.FixedColumnWidth(52), for (var i = 3; i < 23; i++) i: const pw.FixedColumnWidth(30),
                for (var i = 23; i < 28; i++) i: const pw.FixedColumnWidth(40)},
              children: [
                pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.teal700), children: [
                  for (final h in ['#', 'الاسم', 'الصفة', ...days.map((d) => '${d.day}/${d.month}'),
                    'حضور', 'غياب', 'إجازة', 'مهمة', 'بدون']) cell(h, strong: true, color: PdfColors.white),
                ]),
                for (var i = 0; i < people.length; i++) pw.TableRow(
                  decoration: pw.BoxDecoration(color: people[i]['reportRole'] == 'group_supervisor'
                      ? PdfColors.teal50 : PdfColors.white), children: [
                    cell('${i + 1}'), cell(_name(people[i]), strong: true),
                    cell(people[i]['reportRole'] == 'group_supervisor' ? 'مشرف' : 'عامل'),
                    for (final day in days) cell(mark(people[i], day)),
                    for (final kind in ['ح', 'غ', 'إ', 'م', '—'])
                      cell('${days.where((day) => mark(people[i], day) == kind).length}'),
                  ]),
              ])),
          ]));
    }
    return Uint8List.fromList(await doc.save());
  }
}
