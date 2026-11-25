"""Export the Arabic report catalogue using Flutter's production PDF builders.

Run at the repository root with Flutter and pypdf installed. Temporary test
entry points live beside the source so private screen exporters can be exercised
without opening accounts, contacting Firebase, or changing the application API.
"""
from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess
from pypdf import PdfWriter

screens = Path('lib/presentation/screens')
fixture = """
    final day = DateTime(2026, 11, 1);
    final person = <String, dynamic>{
      'id': 'example-1', 'workerId': 'example-1', 'name': 'عامل تجريبي',
      'workerName': 'عامل تجريبي', 'role': 'worker', 'workerRole': 'worker',
      'groupId': 'group-1', 'groupName': 'المجموعة التجريبية',
      'municipalityName': 'بلدية تجريبية', 'councilName': 'مجلس خدمات تجريبي',
      'cycleName': 'دورة توضيحية • بيانات تجريبية',
    };
    final entry = {...person, '_entity': 'attendance', 'createdAt': day, 'status': 'present'};
"""
screen_cases = {
    'attendance_reports_home_screen': """
      final state = _AttendanceReportsHomeScreenState()..selectedDate = day;
      await save('10', await state._pdfBytes([entry]));
      await save('10-leave', await state._pdfBytes([{...entry,'status':'leave'}], leavesOnly:true));
    """,
    'monthly_attendance_report_screen': """
      final state = _MonthlyAttendanceReportScreenState()..month = day..roster = [person];
      for (final mode in ['month','first','second']) {
        state.periodMode = mode;
        await save('11-$mode', await state._pdfBytes(MonthlyAttendanceRows([person],[entry]), 30));
      }
    """,
    'group_attendance_report_screen': """
      final state = _GroupAttendanceReportScreenState()..start = day;
      await save('12', await state._buildPdf(persons: [MapEntry('example-1', person)],
        statuses: {'example-1|2026-11-01':'present'}, group: 'المجموعة التجريبية',
        municipality: person['municipalityName'], council: person['councilName'], cycle: person['cycleName']));
    """,
    'municipality_attendance_report_screen': """
      final state = _MunicipalityAttendanceReportScreenState()..start = day..roster = [person];
      await save('13', await state._pdf({'group-1':[person]}, {'example-1|2026-11-01':'ح'}));
    """,
    'all_municipalities_attendance_report_screen': """
      final state = _AllMunicipalitiesAttendanceReportScreenState()..start = day..roster = [person];
      final actor = AppUser(id:'example-manager',username:'example',name:'مسؤول تجريبي',
        role:'donor_manager',scope:'all',policies:{});
      await save('14', await state._pdf(state._summaries([entry]), actor));
    """,
}
titles = {
    'all': 'التقرير التنفيذي الشامل', 'absence': 'تقرير الغياب والحضور',
    'trips': 'تقرير عمليات الترحيل', 'containers': 'تقرير الحاويات',
    'work': 'تقرير العمل والتشغيل', 'cycles': 'تقرير الدورات',
    'municipalities': 'تقرير البلديات', 'groups': 'تقرير المجموعات',
}
extra = """
    final archived = ReportArchive.read({...ReportArchive.submission(snapshotFor('all')),
      'id':'مثال-معتمد','approvedByName':'مراجع تجريبي','approvedAt':'2026-11-01'});
    await save('09-approved', await reports.buildOperationalPdfBytes(snapshot:archived,
      user:user,title:'التقرير التنفيذي الشامل • نسخة معتمدة تجريبية'));
    final legacy = ReportArchive.read({'id':'مثال-أرشيف','createdAt':'2026-11-01',
      'municipality':person['municipalityName'],'cycleName':person['cycleName'],
      'councilName':person['councilName'],'snapshot':{'trips':4,'attendance':3}});
    await save('09-legacy', await reports.buildOperationalPdfBytes(snapshot:legacy,
      user:user,title:'ملخص أرشيفي • نسخة تجريبية'));
    await save('15', await DailyWorkReportPdf.build({...person, '_entity':'work_report',
      'workDate': day.toIso8601String(), 'status':'draft', 'shiftSummary':'بيانات توضيحية'}));
    final analytics = DecisionAnalytics.calculate(
      operations:[{...person,'_entity':'group','id':'group-1','name':'المجموعة التجريبية'}],
      users:[person],containers:[], dumpsites:[], trips:[], cycles:[{'id':'c1','status':'active',
        'name':person['cycleName'],'startDate':day.subtract(const Duration(days:1)),
        'endDate':day.add(const Duration(days:30))}], now:day,shiftText:'08:00 - 16:00');
    for (final section in ['all','operations','strategic','health','supply']) {
      await save('16-$section', await buildDecisionPdf(data:analytics, decisions:[],
        coordinator:'منسق تجريبي',quality:'بيانات تجريبية',section:section));
    }
"""
imports = """
import 'dart:io' as gallery_io;
import 'package:flutter_test/flutter_test.dart' as gallery;
import 'package:shared_preferences/shared_preferences.dart' as gallery_prefs;
"""
def run():
    out = Path('build/report-collection')
    out.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(dir=out) as tmp:
        directory = Path(tmp).resolve()
        paths = []
        def entry(path, source, body):
            target = path.with_name('gallery_' + path.stem + '_test.dart')
            if target.exists():
                raise FileExistsError(target)
            paths.append(target)
            helper = f"""
Future<void> save(String name, List<int> bytes) async {{
  gallery.expect(bytes.take(5).toList(), [37,80,68,70,45]);
  await gallery_io.File('{directory}/$name.pdf').writeAsBytes(bytes);
}}
"""
            target.write_text(imports + source + helper + """
void main() {
  gallery.TestWidgetsFlutterBinding.ensureInitialized();
  gallery.test('render production reports', () async {
    gallery_prefs.SharedPreferences.setMockInitialValues({});
""" + fixture + body + """
  }, timeout: const gallery.Timeout(Duration(minutes: 4)));
}
""")
        try:
            for name, body in screen_cases.items():
                path = screens / (name + '.dart')
                entry(path, path.read_text(), body)
            source = Path('test/report_pdf_export_test.dart').read_text()
            setup = source[source.index('    final directory ='):source.index('    final snapshot = snapshotFor')]
            setup = (setup.replace("Group A","المجموعة الأولى").replace("Group B","المجموعة الثانية").replace("Manager Test","معد التقرير التجريبي").replace("'Smoke Municipality'", "'بلدية تجريبية'").replace("'Cycle 1'", "'دورة توضيحية • بيانات تجريبية'")
                     .replace("reportType: type,", "councilLabel: 'مجلس خدمات تجريبي', reportType: type,"))
            ops = ''.join(f"    await save('0{i}', await reports.buildOperationalPdfBytes(snapshot:snapshotFor('{k}'), user:user, title:'{v}'));\n"
                          for i, (k, v) in enumerate(titles.items(), 1))
            entry(Path('test/catalogue.dart'), source[:source.index('void main()')] + """
import 'package:solid_waste_operations/core/services/decision_analytics.dart';
import 'package:solid_waste_operations/core/services/decision_pdf_export.dart';
import 'package:solid_waste_operations/core/services/daily_work_report_pdf.dart';
""", setup + "    try {\n" + ops + extra + """
    } finally {data.dispose(); await box.close(); await directory.delete(recursive:true);}
""")
            subprocess.run(['flutter', 'test', '--reporter', 'expanded', *map(str, paths)], check=True)
            parts = sorted(directory.glob('*.pdf'))
            if len(parts) != 24:
                raise RuntimeError(f'Expected 24 reports, got {len(parts)}')
            labels = {f'0{i}': title for i, title in enumerate(titles.values(), 1)}
            labels.update({
                '09-approved': 'النسخة المعتمدة', '09-legacy': 'الملخص الأرشيفي',
                '10': 'الحضور والغياب التفصيلي', '10-leave': 'الإجازات والأذونات',
                '11-month': 'الحضور الشهري', '11-first': 'النصف الأول من الشهر',
                '11-second': 'النصف الثاني من الشهر', '12': 'حضور المجموعة',
                '13': 'حضور البلدية', '14': 'حضور جميع البلديات', '15': 'الأعمال اليومية',
                '16-all': 'لوحة القرارات الشاملة', '16-operations': 'العمليات الميدانية',
                '16-strategic': 'التخطيط الاستراتيجي', '16-health': 'القرارات الصحية والبيئية',
                '16-supply': 'سلسلة الإمداد',
            })
            assert set(labels) == {p.stem for p in parts}
            writer = PdfWriter()
            writer.add_metadata({'/Title':'تقارير إدارة النفايات', '/Subject':'بيانات تجريبية'})
            for key, label in labels.items():
                writer.append(directory / (key + '.pdf'), outline_item=label)
            writer.write(directory/'combined.pdf')
            writer.close()
            (directory/'combined.pdf').replace(out/'all-reports.pdf')
        finally:
            for path in paths:
                path.unlink(missing_ok=True)

if __name__ == '__main__':
    run()
