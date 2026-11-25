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
      'municipalityName': 'بلدية بني سهيلا', 'councilName': 'مجلس الخدمات المشترك لإدارة النفايات الصلبة',
      'cycleName': 'دورة توضيحية • بيانات تجريبية',
    };
    final people = <Map<String,dynamic>>[for (var i=0;i<12;i++) {
      ...person,'id':'p$i','workerId':'p$i','name':'عامل تجريبي ${i+1}','workerName':'عامل تجريبي ${i+1}',
      'groupId':'g${i%2}','groupName':i.isEven?'مجموعة الشرق':'مجموعة الغرب',
    }];
    final records = <Map<String,dynamic>>[for(var d=0;d<30;d++) for(var i=0;i<people.length;i++) {
      ...people[i], '_entity':'attendance','id':'att-$d-$i','createdAt':day.add(Duration(days:d,hours:8)),
      'status':const ['present','present','absent','present','leave','present','excused_absence','present','present','present','present','present'][(i+d)%12],
      'ppeComplete':(i+d)%4!=0,
      if(![2,4,6].contains((i+d)%12)) 'checkInAt':day.add(Duration(days:d,hours:8)).toIso8601String(),
      if(![2,4,6].contains((i+d)%12)) 'checkOutAt':day.add(Duration(days:d,hours:16)).toIso8601String(),
    }];
    String dateKey(dynamic raw) => (raw as DateTime).toIso8601String().substring(0,10);
    final statuses = {for(final r in records) "${r['workerId']}|${dateKey(r['createdAt'])}":r['status'].toString()};
    final marks = statuses.map((k,v)=>MapEntry(k,v=='present'?'ح':v=='leave'?'إ':'غ'));
    final today = records.take(12).toList();
"""
screen_cases = {
    'attendance_reports_home_screen': """
      final state = _AttendanceReportsHomeScreenState()..selectedDate = day;
      await save('10', await state._pdfBytes(today));
      await save('10-leave', await state._pdfBytes(records.where((r)=>r['status']=='leave' && dateKey(r['createdAt'])==dateKey(day)).toList(), leavesOnly:true));
    """,
    'monthly_attendance_report_screen': """
      final state = _MonthlyAttendanceReportScreenState()..month = day..roster = people;
      for (final mode in ['month','first','second']) {
        state.periodMode = mode;
        await save('11-$mode', await state._pdfBytes(MonthlyAttendanceRows(people,records), 30));
      }
    """,
    'group_attendance_report_screen': """
      final state = _GroupAttendanceReportScreenState()..start = day;
      await save('12', await state._buildPdf(persons: [for(final p in people.where((p)=>p['groupId']=='g0')) MapEntry(p['id'].toString(),p)],
        statuses: statuses, group: 'مجموعة الشرق',
        municipality: person['municipalityName'], council: person['councilName'], cycle: person['cycleName']));
    """,
    'municipality_attendance_report_screen': """
      final state = _MunicipalityAttendanceReportScreenState()..start = day..roster = people;
      await save('13', await state._pdf({for(final id in ['g0','g1']) id: people.where((p)=>p['groupId']==id).toList()}, marks));
    """,
    'all_municipalities_attendance_report_screen': """
      final state = _AllMunicipalitiesAttendanceReportScreenState()..start = day..roster = people;
      final actor = AppUser(id:'example-manager',username:'example',name:'مسؤول تجريبي',
        role:'donor_manager',scope:'all',policies:{});
      await save('14', await state._pdf(state._summaries(records), actor));
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
      'councilName':person['councilName'],'snapshot':{'trips':14,'attendance':18,'absence':2,'workers':20,'groups':2}});
    await save('09-legacy', await reports.buildOperationalPdfBytes(snapshot:legacy,
      user:user,title:'ملخص أرشيفي • نسخة تجريبية'));
    await save('15', await DailyWorkReportPdf.build({...person, '_entity':'work_report',
      'workDate': day.toIso8601String(), 'status':'draft', 'shiftSummary':'بيانات توضيحية','attendance':9,'absence':2,'trips':7,'specialLeave':1,'sickLeave':0,'otherAbsence':0,
      'reporterName':'مشرف تجريبي','shift':'08:00–16:00','workTasks':'جمع النفايات من مسارين وتفريغ الحاويات.',
      'completedWork':'أُنجز المسار الشرقي ونُقلت الحمولات إلى المكب.','workLocations':'مسارا الشرق والغرب',
      'containerStatus':'ثلاث حاويات ممتلئة قيد المتابعة.','landfillStatus':'المكب يعمل ضمن السعة التشغيلية.',
      'problems':'تأخر الوصول إلى نقطة جمع واحدة.','suggestions':'تقديم موعد المرور في المسار الغربي.',
      'sourceSnapshot':{'activeTrips':2,'cancelledTrips':1}}));
    final groups = [for(final p in people.take(2)) {...p,'_entity':'group','id':p['groupId'],
      'name':p['groupName'],'targetTrips':4,'targetTons':8}];
    final trips = [for(var d=0;d<14;d++) for(var n=0;n<2+d%4;n++) {
      ...people[n], 'id':'trip-$d-$n','status': n==4?'active':'completed','weightTons':1.5+n*.3,
      'startedAt':day.add(Duration(days:d,hours:9)), 'completedAt':day.add(Duration(days:d,hours:11)),
      'tripPpe':{'gloves':true,'boots':n!=2},'dumpsiteId':'site-1','targetDurationMinutes':90,
    }];
    final analytics = DecisionAnalytics.calculate(operations:[...groups,...records],users:people,
      containers:[for(var i=0;i<9;i++) {...people[i],'id':'bin-$i','status':['full','partial','empty'][i%3]}],
      dumpsites:[{'id':'site-1','name':'مكب تجريبي','capacity':200,'fillPercentage':65}],
      trips:trips,cycles:[{'id':'c1','status':'active','name':person['cycleName'],
        'startDate':day.subtract(const Duration(days:1)),'endDate':day.add(const Duration(days:30))}],
      now:day.add(const Duration(days:13,hours:15)),shiftText:'08:00 - 16:00');
    for (final section in ['all','operations','strategic','health','supply']) {
      await save('16-$section', await buildDecisionPdf(data:analytics, decisions:[for(final kind in ['collection','ppe','temporary_coverage']) {'kind':kind,'title':'متابعة وردية تجريبية','body':'توزيع المهام ومتابعة تنفيذها','coordinatorName':'منسق تجريبي','groupId':'g0','status':kind=='ppe'?'approved':'issued','createdAt':day}],
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
            setup = (setup.replace("Group A","المجموعة الأولى").replace("Group B","المجموعة الثانية").replace("Manager Test","معد التقرير التجريبي").replace("'Smoke Municipality'", "'بلدية بني سهيلا'").replace("'Cycle 1'", "'دورة توضيحية • بيانات تجريبية'")
                     .replace("reportType: type,", "councilLabel: 'مجلس الخدمات المشترك لإدارة النفايات الصلبة', reportType: type,"))
            start = setup.index("      containerRecords:")
            end = setup.index("      ratioInsights:", start)
            setup = setup[:start] + """
      containerRecords: [for(var i=0;i<15;i++) {'id':'C-${i+1}','locationName':'نقطة جمع ${i+1}',
        'groupName':i<8?'المجموعة الأولى':'المجموعة الثانية','status':i<3?'full':i<8?'partial':'empty'}],
      tripRecords: [for(var i=0;i<12;i++) {'id':'T-${i+1}','locationName':'مسار ${i%3+1}',
        'groupName':i<7?'المجموعة الأولى':'المجموعة الثانية','status':i<10?'completed':'active'}],
""" + setup[end:]
            setup = setup.replace("search: 'MAIN'", "search: ''")
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
