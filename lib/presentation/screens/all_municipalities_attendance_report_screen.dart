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

import '../../core/models/core_models.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/data_service.dart';
import '../../core/services/pdf_file_saver.dart';
import '../widgets/app_design.dart';

class _AttendanceCounts {
  int present = 0, absent = 0, leave = 0, mission = 0, noEntry = 0;

  void add(String status) {
    switch (status) {
      case 'ح': present++; break;
      case 'غ': absent++; break;
      case 'إ': leave++; break;
      case 'م': mission++; break;
      default: noEntry++;
    }
  }

  void include(_AttendanceCounts other) {
    present += other.present;
    absent += other.absent;
    leave += other.leave;
    mission += other.mission;
    noEntry += other.noEntry;
  }
}

class _GroupSummary {
  _GroupSummary(this.name);
  final String name;
  int workers = 0, supervisors = 0;
  final Map<String, _AttendanceCounts> byDay = {};
  final _AttendanceCounts total = _AttendanceCounts();
}

class _MunicipalitySummary {
  _MunicipalitySummary(this.name);
  final String name;
  final Map<String, _GroupSummary> groups = {};
  final _AttendanceCounts total = _AttendanceCounts();
  int get workers => groups.values.fold(0, (sum, g) => sum + g.workers);
  int get supervisors => groups.values.fold(0, (sum, g) => sum + g.supervisors);
}

/// Aggregate attendance for the municipalities visible to a council or donor.
/// No individual names or worker identifiers are written to the PDF.
class AllMunicipalitiesAttendanceReportScreen extends StatefulWidget {
  const AllMunicipalitiesAttendanceReportScreen({super.key});

  @override
  State<AllMunicipalitiesAttendanceReportScreen> createState() =>
      _AllMunicipalitiesAttendanceReportScreenState();
}

class _AllMunicipalitiesAttendanceReportScreenState
    extends State<AllMunicipalitiesAttendanceReportScreen> {
  DateTime start = DateTime.now().subtract(const Duration(days: 19));
  List<Map<String, dynamic>> roster = [];
  bool loading = true, ready = false, busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _value(Map<String, dynamic> row, List<String> fields) {
    for (final field in fields) {
      final value = '${row[field] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _day(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  DateTime? _date(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.tryParse('${raw ?? ''}');
  }

  bool _visible(Map<String, dynamic> person, AppUser actor) {
    if (actor.role == 'donor_manager') return true;
    if (actor.role != 'jsc_coordinator') return false;
    final scope = actor.scope.trim();
    if (scope.isEmpty || scope == 'all' || scope == 'assigned_only') return false;
    return scope == _value(person, ['councilName', 'councilId']) ||
        scope == _value(person, ['municipalityName', 'municipality']);
  }

  Future<void> _load() async {
    final actor = context.read<AuthService>().currentUser;
    if (actor == null || !const ['jsc_coordinator', 'donor_manager'].contains(actor.role) ||
        !actor.can('reports', 'export')) {
      if (mounted) setState(() { loading = false; error = 'ليس لديك صلاحية تصدير التقرير الشامل.'; });
      return;
    }
    if (Firebase.apps.isEmpty) {
      if (mounted) setState(() { loading = false; error = 'تعذر الاتصال بقاعدة البيانات.'; });
      return;
    }
    setState(() { loading = true; ready = false; error = null; });
    try {
      final data = context.read<DataService>();
      if (!data.online) throw StateError('لا يوجد اتصال.');
      final people = <Map<String, dynamic>>[];
      for (final role in ['group_supervisor', 'worker', 'worker_with_cart']) {
        final snapshot = await FirebaseFirestore.instance.collection('users')
            .where('role', isEqualTo: role).limit(1500)
            .get(const GetOptions(source: Source.server));
        if (snapshot.docs.length == 1500) throw StateError('قد تكون قائمة الأفراد غير مكتملة.');
        for (final doc in snapshot.docs) {
          final person = doc.data();
          if (person['isActive'] == false || !_visible(person, actor)) continue;
          people.add({...person, 'id': doc.id, 'reportRole': role});
        }
      }
      if (people.any((p) => _value(p, ['municipalityName', 'municipality']).isEmpty ||
          _value(p, ['groupId']).isEmpty || _value(p, ['groupName']).isEmpty)) {
        throw StateError('أسماء البلديات أو المجموعات غير مكتملة.');
      }
      final previousRefresh = data.lastDataRefresh;
      await data.refreshOperations(limit: 10000);
      if (data.operationsCapped || data.lastDataRefresh == previousRefresh) {
        throw StateError('قد تكون سجلات الحضور غير مكتملة.');
      }
      if (mounted) setState(() { roster = people; ready = true; loading = false; });
    } catch (_) {
      if (mounted) setState(() {
        roster = [];
        ready = false;
        loading = false;
        error = 'تعذر تأكيد اكتمال البلديات والمجموعات والحضور. تحقق من الاتصال والبيانات ثم أعد المحاولة.';
      });
    }
  }

  String _kind(String status) {
    if (['present', 'حضور', 'late', 'متأخر'].contains(status)) return 'ح';
    if (['absent', 'غياب', 'excused_absence', 'unexcused_absence'].contains(status)) return 'غ';
    if (['leave', 'on_leave', 'إجازة', 'permission', 'إذن خاص'].contains(status)) return 'إ';
    if (['mission', 'on_duty', 'external_task', 'مهمة', 'مهمة خارج المجموعة'].contains(status)) return 'م';
    return '—';
  }

  List<_MunicipalitySummary> _summaries(List<Map<String, dynamic>> operations) {
    final end = start.add(const Duration(days: 19));
    final days = List.generate(20, (i) => start.add(Duration(days: i)));
    final personIds = roster.map((p) => '${p['id']}').toSet();
    final statuses = <String, String>{};
    for (final row in operations) {
      if (row['_entity'] != 'attendance' || row['isDeleted'] == true) continue;
      final id = _value(row, ['workerId']);
      if (!personIds.contains(id)) continue;
      final date = _date(row['date'] ?? row['createdAt'] ?? row['timestamp']);
      if (date == null || date.isBefore(DateTime(start.year, start.month, start.day)) ||
          !date.isBefore(DateTime(end.year, end.month, end.day + 1))) continue;
      statuses['$id|${_day(date)}'] = _kind(_value(row, ['status']));
    }
    final cities = <String, _MunicipalitySummary>{};
    for (final person in roster) {
      final municipalityName = _value(person, ['municipalityName', 'municipality']);
      final municipalityKey = _value(person, ['municipalityCoordinatorId']).isNotEmpty
          ? _value(person, ['municipalityCoordinatorId']) : municipalityName;
      final city = cities.putIfAbsent(municipalityKey, () => _MunicipalitySummary(municipalityName));
      final groupId = _value(person, ['groupId']);
      final group = city.groups.putIfAbsent(groupId,
          () => _GroupSummary(_value(person, ['groupName'])));
      if (person['reportRole'] == 'group_supervisor') { group.supervisors++; }
      else { group.workers++; }
      for (final day in days) {
        final key = _day(day);
        final kind = statuses['${person['id']}|$key'] ?? '—';
        group.byDay.putIfAbsent(key, _AttendanceCounts.new).add(kind);
        group.total.add(kind);
        city.total.add(kind);
      }
    }
    return cities.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Widget build(BuildContext context) {
    final actor = context.watch<AuthService>().currentUser;
    final operations = context.watch<DataService>().operations;
    final cities = ready ? _summaries(operations) : <_MunicipalitySummary>[];
    final end = start.add(const Duration(days: 19));
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      appBar: AppBar(title: const AppText('تقرير حضور وغياب البلديات الشامل')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('ملخص البلديات ثم كشف المجموعات والأيام. يعرض أعداد الحالات فقط من دون أسماء الأفراد.'),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: busy ? null : () async {
          final picked = await showDatePicker(context: context, initialDate: start,
              firstDate: DateTime(2020), lastDate: DateTime(2100));
          if (picked != null && mounted) setState(() => start = picked);
        }, icon: const Icon(Icons.date_range), label: Text('${_day(start)} — ${_day(end)}')),
        const SizedBox(height: 12),
        Text('البلديات: ${cities.length} • المجموعات: ${cities.fold<int>(0, (n, c) => n + c.groups.length)} • العمال: ${cities.fold<int>(0, (n, c) => n + c.workers)}'),
        if (loading) const LinearProgressIndicator(),
        if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
        if (ready && cities.isEmpty) const Text('لا توجد بلديات مسجلة ضمن نطاق الحساب.'),
        TextButton.icon(onPressed: busy || loading ? null : _load,
            icon: const Icon(Icons.refresh), label: const Text('تحديث البيانات')),
        FilledButton.icon(onPressed: !ready || cities.isEmpty || busy || actor == null ? null
            : () => _produce(cities, actor, preview: true),
            icon: const Icon(Icons.preview), label: const Text('معاينة وطباعة PDF')),
        FilledButton.tonalIcon(onPressed: !ready || cities.isEmpty || busy || actor == null ? null
            : () => _produce(cities, actor, preview: false),
            icon: const Icon(Icons.picture_as_pdf), label: const Text('تصدير PDF')),
      ]),
    ));
  }

  Future<void> _produce(List<_MunicipalitySummary> cities, AppUser actor,
      {required bool preview}) async {
    setState(() => busy = true);
    try {
      final bytes = await _pdf(cities, actor);
      if (preview) {
        if (mounted) await Printing.layoutPdf(onLayout: (_) async => bytes);
      } else {
        final path = await savePdfBytes(bytes, 'all_municipalities_attendance_${_day(start)}.pdf');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(path == null ? 'تعذر حفظ PDF' : 'تم إنشاء PDF: $path')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إنشاء التقرير: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Uint8List> _pdf(List<_MunicipalitySummary> cities, AppUser actor) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));
    final prefs = await SharedPreferences.getInstance();
    pw.ImageProvider? logo(String key) {
      try {
        final raw = prefs.getString(key);
        return raw == null || raw.isEmpty ? null : pw.MemoryImage(base64Decode(raw));
      } catch (_) { return null; }
    }
    final councilLogo = logo('report_council_logo_base64');
    final unicefLogo = logo('report_unicef_logo_base64');
    final council = actor.role == 'jsc_coordinator' ? actor.scope : 'مجالس الخدمات';
    final cycles = roster.map((p) => _value(p, ['cycleName', 'cycleId', 'cycle']))
        .where((name) => name.isNotEmpty).toSet();
    final cycle = cycles.length == 1 ? cycles.first : cycles.isEmpty
        ? prefs.getString('report_project_name') ?? 'غير محددة' : 'دورات متعددة';
    final days = List.generate(20, (i) => start.add(Duration(days: i)));
    const weekdays = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
    pw.Widget txt(String value, {bool strong = false, double size = 8, PdfColor color = PdfColors.blueGrey900}) =>
        pw.Text(value, textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: strong ? bold : regular, fontSize: size, color: color));
    pw.Widget cell(String value, {bool strong = false, PdfColor color = PdfColors.blueGrey900,
        PdfColor? background, double height = 29}) => pw.Container(
          height: height, alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(horizontal: 3), color: background,
          child: txt(value, strong: strong, color: color, size: 7.5));
    pw.Widget dayHeading(DateTime day) => pw.Container(height: 38,
        alignment: pw.Alignment.center,
        color: day.weekday == DateTime.friday ? PdfColors.teal900 : PdfColors.teal700,
        child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
          txt(weekdays[day.weekday - 1], strong: true, size: 6.1, color: PdfColors.white),
          pw.SizedBox(height: 2), txt('${day.day}/${day.month}', strong: true, size: 7.4, color: PdfColors.white),
        ]));
    pw.Widget header(String title) => pw.Directionality(textDirection: pw.TextDirection.rtl,
        child: pw.Column(children: [
          pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: pw.BoxDecoration(color: PdfColors.teal50,
                  borderRadius: pw.BorderRadius.circular(9)), child: pw.Row(children: [
                pw.Expanded(child: txt('البلديات', strong: true, size: 9)),
                pw.Expanded(child: pw.Row(children: [
                  if (councilLogo != null) pw.Container(width: 35, height: 35,
                      margin: const pw.EdgeInsets.only(left: 7), child: pw.Image(councilLogo)),
                  pw.Expanded(child: txt(council, strong: true, size: 9)),
                ])),
                pw.Expanded(child: pw.Row(children: [
                  if (unicefLogo != null) pw.Container(width: 35, height: 35,
                      margin: const pw.EdgeInsets.only(left: 7), child: pw.Image(unicefLogo)),
                  pw.Expanded(child: txt('اليونيسف UNICEF', strong: true, size: 9)),
                ])),
              ])),
          pw.SizedBox(height: 8),
          pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: pw.BoxDecoration(color: PdfColors.teal800,
                  borderRadius: pw.BorderRadius.circular(8)),
              child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                txt(title, strong: true, size: 16, color: PdfColors.white),
                txt('الدورة: $cycle   |   ${_day(start)} - ${_day(days.last)}',
                    size: 9, color: PdfColors.white),
              ])),
          pw.SizedBox(height: 11),
        ]));
    pw.Widget footer(pw.Context context) => pw.Directionality(textDirection: pw.TextDirection.rtl,
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          txt('الأعداد يومية للأفراد، المشرفون ضمن الحالات • ح/غ = حضور/غياب • — = لا يوجد تسجيل', size: 8),
          txt('صفحة ${context.pageNumber} من ${context.pagesCount}', size: 8),
        ]));
    pw.Widget metric(String label, String number) => pw.Expanded(child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const pw.EdgeInsets.only(left: 7),
        decoration: pw.BoxDecoration(color: PdfColors.teal50,
            borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          txt(label, size: 8, color: PdfColors.teal800),
          pw.SizedBox(height: 3), txt(number, strong: true, size: 18),
        ])));
    final total = _AttendanceCounts();
    for (final city in cities) { total.include(city.total); }
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a3.landscape,
        margin: const pw.EdgeInsets.all(26), textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        header: (_) => header('تقرير حضور وغياب البلديات الشامل'), footer: footer,
        build: (_) => [
          pw.Directionality(textDirection: pw.TextDirection.rtl, child: pw.Row(children: [
            metric('البلديات', '${cities.length}'),
            metric('المجموعات', '${cities.fold<int>(0, (n, c) => n + c.groups.length)}'),
            metric('العمال', '${cities.fold<int>(0, (n, c) => n + c.workers)}'),
            metric('المشرفون', '${cities.fold<int>(0, (n, c) => n + c.supervisors)}'),
            metric('حضور', '${total.present}'), metric('غياب', '${total.absent}'),
          ])),
          pw.SizedBox(height: 18), txt('ملخص البلديات', strong: true, size: 12),
          pw.SizedBox(height: 8),
          pw.Directionality(textDirection: pw.TextDirection.rtl, child: pw.Table(
            border: pw.TableBorder.all(color: PdfColors.teal100, width: .5),
            children: [
              pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.teal700),
                  children: [for (final h in ['البلدية', 'المجموعات', 'العمال', 'المشرفون',
                    'حضور', 'غياب', 'إجازة', 'مهمة', 'بدون تسجيل'])
                    cell(h, strong: true, color: PdfColors.white)]),
              for (final city in cities) pw.TableRow(children: [
                cell(city.name, strong: true), cell('${city.groups.length}'),
                cell('${city.workers}'), cell('${city.supervisors}'),
                cell('${city.total.present}'), cell('${city.total.absent}'),
                cell('${city.total.leave}'), cell('${city.total.mission}'),
                cell('${city.total.noEntry}'),
              ]),
            ])),
          pw.SizedBox(height: 17),
          pw.Container(padding: const pw.EdgeInsets.all(13),
              decoration: pw.BoxDecoration(color: PdfColors.teal50,
                  borderRadius: pw.BorderRadius.circular(8)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                txt('طريقة قراءة التقرير', strong: true, size: 10),
                pw.SizedBox(height: 5),
                txt('كل عدد حالة فرد في يوم واحد. عدم التسجيل منفصل عن الغياب. صفحات البلديات تعرض المجموعات فقط، بلا أسماء أفراد.', size: 9),
                pw.SizedBox(height: 3),
                txt('أيام الفترة من اليمين إلى اليسار، اسم اليوم فوق التاريخ، والجمعة مميزة بلون أغمق.', size: 9),
              ])),
        ]));
    for (final city in cities) {
      final groups = city.groups.values.toList()..sort((a, b) => a.name.compareTo(b.name));
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a3.landscape,
          margin: const pw.EdgeInsets.all(26), textDirection: pw.TextDirection.rtl,
          theme: pw.ThemeData.withFont(base: regular, bold: bold),
          header: (_) => header('كشف البلدية: ${city.name}'), footer: footer,
          build: (_) => [
            pw.Directionality(textDirection: pw.TextDirection.rtl, child: pw.Row(children: [
              metric('المجموعات', '${groups.length}'), metric('العمال', '${city.workers}'),
              metric('المشرفون', '${city.supervisors}'), metric('حضور', '${city.total.present}'),
              metric('غياب', '${city.total.absent}'), metric('بدون تسجيل', '${city.total.noEntry}'),
            ])),
            pw.SizedBox(height: 14),
            txt('كل خانة يومية: حضور / غياب للمجموعة  •  الإجازة والمهمة وعدم التسجيل في المجاميع الأخيرة.', size: 9),
            pw.SizedBox(height: 9),
            pw.Directionality(textDirection: pw.TextDirection.rtl, child: pw.Table(
              border: pw.TableBorder.all(color: PdfColors.teal100, width: .5),
              columnWidths: {0: const pw.FixedColumnWidth(150),
                1: const pw.FixedColumnWidth(50), 2: const pw.FixedColumnWidth(50),
                for (var i = 3; i < 23; i++) i: const pw.FixedColumnWidth(33),
                for (var i = 23; i < 28; i++) i: const pw.FixedColumnWidth(44)},
              children: [
                pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.teal700), children: [
                  for (final h in ['المجموعة', 'عمال', 'مشرفون']) cell(h, strong: true, color: PdfColors.white, height: 38),
                  for (final day in days) dayHeading(day),
                  for (final h in ['حضور', 'غياب', 'إجازة', 'مهمة', 'بدون'])
                    cell(h, strong: true, color: PdfColors.white, height: 38),
                ]),
                for (final group in groups) pw.TableRow(children: [
                  cell(group.name, strong: true), cell('${group.workers}'), cell('${group.supervisors}'),
                  for (final day in days) cell(
                    '${group.byDay[_day(day)]?.present ?? 0}/${group.byDay[_day(day)]?.absent ?? 0}',
                    background: day.weekday == DateTime.friday ? PdfColors.teal50 : null),
                  cell('${group.total.present}'), cell('${group.total.absent}'),
                  cell('${group.total.leave}'), cell('${group.total.mission}'),
                  cell('${group.total.noEntry}'),
                ]),
              ])),
          ]));
    }
    return Uint8List.fromList(await doc.save());
  }
}
