import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart';
import '../constants/app_constants.dart';
import '../models/core_models.dart';
import 'data_service.dart';
import 'pdf_file_saver.dart';
import 'report_pdf_template.dart';

class ReportPeriodRange {
  final DateTime startDate;
  final DateTime endDate;
  const ReportPeriodRange({required this.startDate, required this.endDate});

  int get inclusiveDays =>
      DateTime(endDate.year, endDate.month, endDate.day)
          .difference(DateTime(startDate.year, startDate.month, startDate.day))
          .inDays +
      1;
}

class ReportPeriodPresets {
  static ReportPeriodRange daily(DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    return ReportPeriodRange(startDate: day, endDate: day);
  }

  static ReportPeriodRange weekly(DateTime now) {
    final end = DateTime(now.year, now.month, now.day);
    return ReportPeriodRange(
      startDate: end.subtract(const Duration(days: 6)),
      endDate: end,
    );
  }

  static ReportPeriodRange custom(DateTime start, DateTime end) {
    final normalizedStart = DateTime(start.year, start.month, start.day);
    final normalizedEnd = DateTime(end.year, end.month, end.day);
    if (normalizedEnd.isBefore(normalizedStart)) {
      return ReportPeriodRange(
        startDate: normalizedEnd,
        endDate: normalizedStart,
      );
    }
    return ReportPeriodRange(
      startDate: normalizedStart,
      endDate: normalizedEnd,
    );
  }
}

class ReportSnapshot {
  final int trips, alternativeTrips, attendance, absence, ppeCompliant, emergencies, emergencyOpen, emergencySecured;
  final int containersTotal, containersFull, containersPartial, containersEmpty, containerIssues;
  final int workers, supervisors, groups, municipalities, dumpsites, cycleCount;
  final List<String> municipalityNames;
  final Map<String, int> tripsByMunicipality;
  final Map<String, int> attendanceByMunicipality;
  final Map<String, int> absenceByGroup;
  final Map<String, int> containersByMunicipality;
  final Map<String, int> containersByGroup;
  final List<String> cycles;
  final String? selectedMunicipality, selectedGroup, selectedCycle, reportType;
  final double landfillCapacity, heavyMachineryHours;
  final Map<String, int> tripsByGroup;
  final Map<String, int> tripsByDay;
  final Map<String, int> attendanceByGroup;
  final Map<String, int> ppeByGroup;
  final Map<String, int> emergenciesByGroup;
  final Map<String, int> containerByStatus;
  final String reportId;
  final String periodLabel;
  final DateTime generatedAt;
  /// True when the online source reached its maximum fetch bound.
  final bool sourceMayBeIncomplete;

  const ReportSnapshot({
    required this.trips,
    required this.alternativeTrips,
    required this.attendance,
    required this.absence,
    required this.ppeCompliant,
    required this.emergencies,
    required this.emergencyOpen,
    required this.emergencySecured,
    required this.landfillCapacity,
    required this.heavyMachineryHours,
    required this.tripsByGroup,
    required this.tripsByDay,
    required this.attendanceByGroup,
    required this.ppeByGroup,
    required this.emergenciesByGroup,
    required this.containerByStatus,
    required this.containersTotal, required this.containersFull, required this.containersPartial, required this.containersEmpty, required this.containerIssues,
    required this.workers, required this.supervisors, required this.groups, required this.municipalities, required this.dumpsites, required this.cycleCount, required this.municipalityNames,
    required this.tripsByMunicipality, required this.attendanceByMunicipality, required this.absenceByGroup, required this.containersByMunicipality, required this.containersByGroup, required this.cycles,
    this.selectedMunicipality, this.selectedGroup, this.selectedCycle, this.reportType,
    required this.reportId,
    required this.periodLabel,
    required this.generatedAt,
    this.sourceMayBeIncomplete = false,
  });

  double get ppeRate => attendance == 0 ? 0 : (ppeCompliant / attendance).clamp(0.0, 1.0).toDouble();
  double get attendanceRate => attendance + absence == 0 ? 0 : (attendance / (attendance + absence)).clamp(0.0, 1.0).toDouble();
}

class ReportService {
  final DataService data;
  ReportService(this.data);

  Future<ReportSnapshot> load({
    int days = 7,
    DateTime? startDate,
    DateTime? endDate,
    AppUser? user,
    String? municipality,
    String? group,
    String? cycle,
    String? reportType,
    String? reportId,
  }) async {
    final now = DateTime.now();
    final end = DateTime(endDate?.year ?? now.year, endDate?.month ?? now.month, endDate?.day ?? now.day, 23, 59, 59, 999);
    final start = DateTime(startDate?.year ?? now.subtract(Duration(days: math.max(1, days) - 1)).year, startDate?.month ?? now.subtract(Duration(days: math.max(1, days) - 1)).month, startDate?.day ?? now.subtract(Duration(days: math.max(1, days) - 1)).day);
    int trips = 0, alternativeTrips = 0, attendance = 0, absence = 0, ppe = 0, emergencies = 0, emergencyOpen = 0, emergencySecured = 0;
    int containersTotal = 0, containersFull = 0, containersPartial = 0, containersEmpty = 0, containerIssues = 0, dumpsites = 0;
    double landfill = 0, heavyMachineryHours = 0;
    final byGroup = <String, int>{}, byDay = <String, int>{}, attendanceByGroup = <String,int>{}, ppeByGroup = <String,int>{}, emergenciesByGroup = <String,int>{}, containerByStatus = <String,int>{};
    final tripsByMunicipality = <String,int>{}, attendanceByMunicipality = <String,int>{}, absenceByGroup = <String,int>{}, containersByMunicipality = <String,int>{}, containersByGroup = <String,int>{};
    final groups = <String>{}, municipalities = <String>{}, workers = <String>{}, supervisors = <String>{};

    // Firestore permits user-list queries only to management, and restricts
    // municipality coordinators to workforce profiles under their own UID.
    if (Firebase.apps.isNotEmpty &&
        const ['municipality_coordinator','jsc_coordinator','donor_manager']
            .contains(user?.role)) {
      try {
        Query<Map<String, dynamic>> usersQuery = FirebaseFirestore.instance
            .collection('users').limit(1000);
        if (user?.role == 'municipality_coordinator') {
          usersQuery = FirebaseFirestore.instance.collection('users')
              .where('municipalityCoordinatorId', isEqualTo: user!.id)
              .limit(1000);
        }
        final userSnap = await usersQuery.get();
        for (final d in userSnap.docs) {
          final m = d.data();
          if (m['isActive'] == false || !_inScope(m, user)) continue;
          final mun = '${m['municipalityName'] ?? m['municipality'] ?? m['scope'] ?? 'غير محددة'}';
          final grp = '${m['groupName'] ?? m['groupId'] ?? 'غير محددة'}';
          if (!_matchesFilters(m, municipality: municipality, group: group, cycle: cycle)) continue;
          if (mun != 'غير محددة') municipalities.add(mun);
          if (grp != 'غير محددة' && grp.isNotEmpty) groups.add(grp);
          final role = '${m['role'] ?? ''}';
          if (role == 'worker') workers.add(d.id);
          if (role == 'group_supervisor') supervisors.add(d.id);
        }
      } catch (_) {}
    }

    // Long custom cycles must not silently use only the first 1000 records.
    final cached = await data.refreshOperations(limit: 10000);
    final sourceMayBeIncomplete = data.online && data.operationsCapped;
    for (final m in cached) {
      if (m['isDeleted'] == true || !_inDateRange(m, start, end) || !_inScope(m, user)) continue;
      if (!_matchesFilters(m, municipality: municipality, group: group, cycle: cycle)) continue;
      final rawEntity = '${m['_entity'] ?? ''}';
      final entity = rawEntity == 'report' ? '${m['reportKind'] ?? 'report'}' : rawEntity;
      if (reportType == 'absence' && entity != 'attendance') continue;
      if (reportType == 'containers' && entity != 'container' && entity != 'containers') continue;
      if (reportType == 'work' && !['work_report', 'heavy_machinery', 'landfill_status'].contains(entity)) continue;
      if (reportType == 'cycles' && entity != 'work_cycle' && entity != 'cycle') continue;
      if (reportType == 'municipalities' && !['municipality', 'trip', 'trips', 'attendance', 'work_report'].contains(entity)) continue;
      if (reportType == 'groups' && !['group', 'trip', 'trips', 'attendance', 'work_report'].contains(entity)) continue;
      final mun = '${m['municipalityName'] ?? m['municipality'] ?? m['municipalityId'] ?? 'غير محددة'}';
      final grp = '${m['groupName'] ?? m['groupId'] ?? 'غير محددة'}';
      if (grp != 'غير محددة') groups.add(grp);
      if (mun != 'غير محددة') municipalities.add(mun);
      final workerId = '${m['workerId'] ?? m['userId'] ?? ''}';
      if (workerId.isNotEmpty) workers.add(workerId);
      if (entity == 'trip' || entity == 'trips') {
        trips++; if (m['alternative'] == true || m['cartType'] == 'alternative') alternativeTrips++;
        byGroup[grp]=(byGroup[grp]??0)+1; tripsByMunicipality[mun]=(tripsByMunicipality[mun]??0)+1;
        final created = _dateValue(m['createdAt'] ?? m['date'] ?? m['timestamp']) ?? now; final day=DateFormat('MM/dd').format(created); byDay[day]=(byDay[day]??0)+1;
      } else if (entity == 'attendance') {
        final status='${m['status']??''}';
        if (status == 'present' || status == 'حضور') { attendance++; attendanceByGroup[grp]=(attendanceByGroup[grp]??0)+1; attendanceByMunicipality[mun]=(attendanceByMunicipality[mun]??0)+1; if(m['ppeComplete']==true){ppe++; ppeByGroup[grp]=(ppeByGroup[grp]??0)+1;} }
        if (status == 'absent' || status == 'غياب' || status == 'excused_absence' || status == 'unexcused_absence') { absence++; absenceByGroup[grp]=(absenceByGroup[grp]??0)+1; }
      } else if (entity == 'work_report' && reportType == 'work') {
        trips += (m['trips'] as num?)?.toInt() ?? 0;
        attendance += (m['attendance'] as num?)?.toInt() ?? 0;
        absence += (m['absence'] as num?)?.toInt() ?? 0;
        final reportTrips = (m['trips'] as num?)?.toInt() ?? 0;
        if (reportTrips > 0) byGroup[grp] = (byGroup[grp] ?? 0) + reportTrips;
        final reportAttendance = (m['attendance'] as num?)?.toInt() ?? 0;
        if (reportAttendance > 0) attendanceByGroup[grp] = (attendanceByGroup[grp] ?? 0) + reportAttendance;
        final reportAbsence = (m['absence'] as num?)?.toInt() ?? 0;
        if (reportAbsence > 0) absenceByGroup[grp] = (absenceByGroup[grp] ?? 0) + reportAbsence;
      } else if (entity == 'emergency') {
        emergencies++; emergenciesByGroup[grp]=(emergenciesByGroup[grp]??0)+1; final status='${m['status']??'urgent'}'; if(status=='secured'||status=='مؤمنة') emergencySecured++; else emergencyOpen++;
      } else if (entity == 'heavy_machinery') { heavyMachineryHours += (m['hours'] as num?)?.toDouble() ?? 0; }
      else if (entity == 'landfill_status') { final c=(m['capacity'] as num?)?.toDouble(); if(c!=null) landfill=math.max(landfill,c.clamp(0.0,1.0).toDouble()); }
    }

    if (Firebase.apps.isNotEmpty) {
      try {
        Query<Map<String, dynamic>> containersQuery =
            FirebaseFirestore.instance.collection('containers');
        if (user?.role == 'worker' || user?.role == 'group_supervisor') {
          final groupId = (user?.groupId ?? '').trim();
          if (groupId.isEmpty) throw StateError('لا توجد مجموعة مرتبطة بالحساب.');
          containersQuery = containersQuery.where('groupId', isEqualTo: groupId);
        } else if (user?.role == 'municipality_coordinator') {
          containersQuery = containersQuery.where('municipalityId',
              isEqualTo: user!.id);
        }
        final snap = await containersQuery.get();
        for (final d in snap.docs) {
          final m={'id':d.id,...d.data()};
          final mun='${m['municipalityName'] ?? m['municipalityId'] ?? 'غير محددة'}'; final grp='${m['groupName'] ?? m['groupId'] ?? 'غير محددة'}';
          if (municipality != null && municipality.isNotEmpty && mun != municipality && '${m['municipalityId']}' != municipality) continue;
          if (group != null && group.isNotEmpty && grp != group && '${m['groupId']}' != group) continue;
          if (user != null) {
            final rowGroup = '${m['groupId'] ?? m['groupName'] ?? ''}'.trim();
            final rowOwner = '${m['municipalityCoordinatorId'] ?? m['reportedBy'] ?? ''}'.trim();
            if (user.role == 'worker' || user.role == 'group_supervisor') {
              if ((user.groupId ?? '').trim().isEmpty || rowGroup != user.groupId!.trim()) continue;
            } else if (user.role == 'municipality_coordinator') {
              final scope = user.scope.trim();
              final belongsByOwner = rowOwner == user.id || '${m['municipalityCoordinatorId'] ?? ''}' == user.id;
              final belongsByName = scope.isNotEmpty && scope != 'all' && scope != 'assigned_only' && (mun == scope || '${m['municipalityId'] ?? ''}' == scope);
              if (!belongsByOwner && !belongsByName) continue;
            } else if (user.role == 'jsc_coordinator') {
              final scope = user.scope.trim();
              final council = '${m['councilName'] ?? m['councilId'] ?? ''}'.trim();
              if (scope.isEmpty || scope == 'all' || scope == 'assigned_only' || (council != scope && mun != scope)) continue;
            }
          }
          containersTotal++; containersByMunicipality[mun]=(containersByMunicipality[mun]??0)+1; containersByGroup[grp]=(containersByGroup[grp]??0)+1;
          final status='${m['status']??'unknown'}'; containerByStatus[status]=(containerByStatus[status]??0)+1;
          if(status=='full') containersFull++; else if(status=='partial') containersPartial++; else if(status=='empty') containersEmpty++;
          if('${m['issueStatus']??'none'}' != 'none' && '${m['issueStatus']}' != 'verified_resolved') containerIssues++;
        }
      } catch (_) {}
    }

    if (Firebase.apps.isNotEmpty) {
      try {
        final dumpSnap = await FirebaseFirestore.instance.collection('dumpsites').where('isActive', isEqualTo: true).limit(500).get();
        for (final d in dumpSnap.docs) {
          final m = d.data();
          final mun = '${m['municipalityName'] ?? m['municipality'] ?? m['municipalityId'] ?? 'غير محددة'}';
          if (municipality != null && municipality.isNotEmpty && mun != municipality && '${m['municipalityId']}' != municipality) continue;
          if (user != null) {
            if ((user.role == 'worker' || user.role == 'group_supervisor')) continue;
            if (user.role == 'municipality_coordinator') {
              final scope = user.scope.trim();
              if (scope.isEmpty || scope == 'assigned_only' || (mun != scope && '${m['municipalityId'] ?? ''}' != scope)) continue;
            }
            if (user.role == 'jsc_coordinator') {
              final scope = user.scope.trim();
              final council = '${m['councilName'] ?? m['councilId'] ?? ''}'.trim();
              if (scope.isEmpty || scope == 'all' || scope == 'assigned_only' || (council != scope && mun != scope)) continue;
            }
          }
          dumpsites++;
          if (mun != 'غير محددة') municipalities.add(mun);
        }
      } catch (_) {}
    }

    List<String> cycles=[]; int cycleCount=0;
    if (Firebase.apps.isNotEmpty) { try { final snap=await FirebaseFirestore.instance.collection('work_cycles').orderBy('startDate', descending:true).limit(50).get(); cycles=[for(final d in snap.docs) '${d.data()['name'] ?? d.id}']; cycleCount=snap.docs.length; } catch (_) {} }
    if (user?.role == 'municipality_coordinator' && user!.scope.trim().isNotEmpty && user.scope != 'assigned_only' && user.scope != 'all') municipalities.add(user.scope.trim());
    final municipalityNames = municipalities.toList()..sort();
    if (municipality != null && municipality.isNotEmpty && !municipalityNames.contains(municipality)) municipalityNames.insert(0, municipality);
    return ReportSnapshot(trips: trips, alternativeTrips: alternativeTrips, attendance: attendance, absence: absence, ppeCompliant: ppe, emergencies: emergencies, emergencyOpen: emergencyOpen, emergencySecured: emergencySecured, landfillCapacity: landfill, heavyMachineryHours: heavyMachineryHours, tripsByGroup: byGroup, tripsByDay: byDay, attendanceByGroup: attendanceByGroup, ppeByGroup: ppeByGroup, emergenciesByGroup: emergenciesByGroup, containerByStatus: containerByStatus, containersTotal: containersTotal, containersFull: containersFull, containersPartial: containersPartial, containersEmpty: containersEmpty, containerIssues: containerIssues, workers: workers.length, supervisors: supervisors.length, groups: groups.length, municipalities: municipalities.length, dumpsites: dumpsites, cycleCount: cycleCount, municipalityNames: municipalityNames, tripsByMunicipality: tripsByMunicipality, attendanceByMunicipality: attendanceByMunicipality, absenceByGroup: absenceByGroup, containersByMunicipality: containersByMunicipality, containersByGroup: containersByGroup, cycles: cycles, selectedMunicipality: municipality, selectedGroup: group, selectedCycle: cycle, reportType: reportType, reportId: reportId ?? 'CO-${now.millisecondsSinceEpoch}', sourceMayBeIncomplete: sourceMayBeIncomplete, periodLabel: '${DateFormat('yyyy-MM-dd').format(start)} → ${DateFormat('yyyy-MM-dd').format(end)}', generatedAt: now);
  }

  bool _matchesFilters(Map<String,dynamic> m, {String? municipality, String? group, String? cycle}) {
    final mun='${m['municipalityName'] ?? m['municipality'] ?? m['municipalityId'] ?? ''}'; final grp='${m['groupName'] ?? m['groupId'] ?? ''}'; final cyc='${m['cycleName'] ?? m['cycleId'] ?? ''}';
    if(municipality != null && municipality.isNotEmpty && mun != municipality && '${m['municipalityId']}' != municipality) return false;
    if(group != null && group.isNotEmpty && grp != group && '${m['groupId']}' != group) return false;
    if(cycle != null && cycle.isNotEmpty && cyc != cycle && '${m['cycleId']}' != cycle) return false;
    return true;
  }

  DateTime? _dateValue(dynamic raw) {
    if (raw is DateTime) return raw;
    if (raw is Timestamp) return raw.toDate();
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return DateTime.tryParse('${raw ?? ''}');
  }

  bool _inDateRange(Map<String, dynamic> data, DateTime start, DateTime end) {
    final isWorkReport = data['_entity'] == 'work_report' || data['reportKind'] == 'work_report';
    final value = _dateValue(isWorkReport
        ? (data['workDate'] ?? data['createdAt'] ?? data['date'] ?? data['timestamp'])
        : (data['createdAt'] ?? data['date'] ?? data['timestamp'] ?? data['workDate']));
    // Reports are period-scoped: undated legacy records must not be silently
    // counted inside an arbitrary date range.
    return value != null && !value.isBefore(start) && !value.isAfter(end);
  }

  bool _inScope(Map<String, dynamic> data, AppUser? user) {
    if (user == null) return false;
    final role = user.role;
    final groupId = '${data['groupId'] ?? data['groupName'] ?? ''}'.trim();
    final municipality = '${data['municipalityName'] ?? data['municipality'] ?? data['municipalityId'] ?? ''}'.trim();
    final owner = '${data['municipalityCoordinatorId'] ?? data['reportedBy'] ?? data['requestedBy'] ?? data['supervisorId'] ?? data['generatedBy'] ?? ''}'.trim();
    if (role == 'donor_manager') return true;
    if (role == 'worker' || role == 'group_supervisor') {
      final assignedGroup = (user.groupId ?? '').trim();
      return assignedGroup.isNotEmpty && groupId == assignedGroup;
    }
    if (role == 'municipality_coordinator') {
      final scope = user.scope.trim();
      if (owner == user.id || '${data['municipalityCoordinatorId'] ?? ''}' == user.id) return true;
      if (scope.isEmpty || scope == 'assigned_only' || scope == 'all') return false;
      return municipality == scope || '${data['municipalityId'] ?? ''}' == scope;
    }
    if (role == 'jsc_coordinator') {
      final scope = user.scope.trim();
      if (scope.isEmpty || scope == 'all' || scope == 'assigned_only') return false;
      final council = '${data['councilName'] ?? data['councilId'] ?? ''}'.trim();
      return council == scope || municipality == scope;
    }
    return false;
  }

  Future<String> createSmartReport({
    required AppUser user,
    required ReportSnapshot snapshot,
    String? municipality,
    String? group,
    String? cycle,
    String? periodPreset,
  }) async {
    final attendanceText = snapshot.attendanceRate >= .95 ? 'التزام حضور مرتفع' : 'تحتاج الحضور إلى متابعة';
    final ppeText = snapshot.ppeRate >= .95 ? 'التزام PPE جيد' : 'يوجد احتياج لمراجعة PPE';
    final emergencyText = snapshot.emergencies == 0
        ? 'لا توجد بلاغات طوارئ ضمن البيانات المتاحة'
        : 'توجد بلاغات طوارئ تحتاج متابعة';
    final objective = municipality == null
        ? 'تنفيذ وتوثيق أعمال جمع النفايات ومراقبة السلامة والنقلات.'
        : 'متابعة أداء البلدية وتوثيق الإنجاز الميداني ضمن النطاق المحدد.';
    final summary = 'تم تسجيل ${snapshot.trips} نقلة، مع ${snapshot.alternativeTrips} نقلة بكارة بديلة. $attendanceText، $ppeText. $emergencyText.';
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final queueEntity =
        user.role == 'municipality_coordinator' ? 'work_report' : 'report';
    await data.enqueue(queueEntity, 'create', {
      'id': id,
      'type': 'smart_operational',
      'scope': user.scope,
      'municipality': municipality,
      'municipalityName': municipality ??
          (user.role == 'municipality_coordinator' &&
                  user.scope != 'assigned_only' &&
                  user.scope != 'all'
              ? user.scope
              : null),
      'municipalityCoordinatorId':
          user.role == 'municipality_coordinator' ? user.id : null,
      'group': group,
      'groupId': group,
      'cycle': cycle,
      'reportId': snapshot.reportId,
      'reportType': snapshot.reportType ?? 'all',
      'period': snapshot.periodLabel,
      'periodPreset': periodPreset ?? 'custom',
      'generatedBy': user.id,
      'reportedBy': user.id,
      'workDate': DateTime.now().toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
      'objectives': objective,
      'results': summary,
      'shiftSummary': 'موجز الوردية: $summary',
      'status': 'draft',
    });
    await data.writeAudit(actorId: user.id, operation: 'CREATE_SMART_REPORT', targetId: id, after: {
      'type': 'smart_operational',
      'reportId': snapshot.reportId,
      'period': snapshot.periodLabel,
      'periodPreset': periodPreset ?? 'custom',
    });
    return summary;
  }

  String autoCaption({required String phase, required String streetName}) =>
      phase == 'before'
          ? 'توثيق حالة الشارع قبل التنفيذ${streetName.isEmpty ? '' : ' — $streetName'}'
          : 'توثيق حالة الشارع بعد التنفيذ${streetName.isEmpty ? '' : ' — $streetName'}';

  Future<List<int>> buildOperationalPdfBytes({ReportSnapshot? snapshot, AppUser? user, String title = 'التقرير التشغيلي لمنظومة جمع النفايات', String languageCode = 'ar'}) async {
    final s = snapshot ?? await load(user: user);
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));
    final prefs = await SharedPreferences.getInstance();
    pw.ImageProvider? readLogo(String key) {
      final encoded = prefs.getString(key);
      if (encoded == null || encoded.isEmpty) return null;
      try { return pw.MemoryImage(base64Decode(encoded)); } catch (_) { return null; }
    }
    final municipalityLogo = readLogo('report_municipality_logo_base64');
    final councilLogo = readLogo('report_council_logo_base64');
    final unicefLogo = readLogo('report_unicef_logo_base64');
    final configuredMunicipality = prefs.getString('report_municipality_name') ?? '';
    final municipalityName = configuredMunicipality.isNotEmpty ? configuredMunicipality : (s.selectedMunicipality ?? (s.municipalityNames.length == 1 ? s.municipalityNames.first : ''));
    final councilName = prefs.getString('report_council_name') ?? '';
    final projectName = (s.selectedCycle != null && s.selectedCycle!.isNotEmpty) ? s.selectedCycle! : (prefs.getString('report_project_name') ?? '');
    final exportTitle = languageCode == 'en' ? _englishReportTitle(title) : title;
    final doc = pw.Document();
    doc.addPage(ReportPdfTemplate(regular: regular, bold: bold, user: user, title: exportTitle, snapshot: s, languageCode: languageCode, municipalityName: municipalityName, councilName: councilName, projectName: projectName, municipalityLogo: municipalityLogo, councilLogo: councilLogo, unicefLogo: unicefLogo).page());
    return doc.save();
  }

  Future<String?> exportOperationalPdf({ReportSnapshot? snapshot, AppUser? user, String title = 'التقرير التشغيلي لمنظومة جمع النفايات', String languageCode = 'ar'}) async {
    try {
      final s = snapshot ?? await load(user: user);
      final bytes = await buildOperationalPdfBytes(snapshot: s, user: user, title: title, languageCode: languageCode);
      final file = await savePdfBytes(bytes, 'operational_report_${user?.role ?? 'report'}_${DateTime.now().millisecondsSinceEpoch}.pdf');
      if (user != null) await data.writeAudit(actorId: user.id, operation: 'EXPORT_OPERATIONAL_PDF', targetId: s.reportId, after: {'role': user.role, 'period': s.periodLabel, 'languageCode': languageCode});
      return file;
    } catch (e) {
      throw Exception('فشل إنشاء التقرير PDF: $e');
    }
  }

  List<int> buildOperationalCsvBytes(ReportSnapshot s, {String languageCode = 'ar'}) {
    final en = languageCode == 'en';
    final rows = <List<String>>[
      [en ? 'Metric' : 'المؤشر', en ? 'Value' : 'القيمة'],
      [en ? 'Report ID' : 'معرّف التقرير', s.reportId],
      [en ? 'Period' : 'الفترة', s.periodLabel],
      [en ? 'Municipality' : 'البلديات', s.selectedMunicipality ?? s.municipalityNames.join('، ')],
      [en ? 'Groups' : 'المجموعات', '${s.groups}'],
      [en ? 'Workers' : 'العمال', '${s.workers}'],
      [en ? 'Supervisors' : 'المشرفون', '${s.supervisors}'],
      [en ? 'Trips' : 'النقلات', '${s.trips}'],
      [en ? 'Alternative trips' : 'النقلات البديلة', '${s.alternativeTrips}'],
      [en ? 'Present records' : 'سجلات الحضور', '${s.attendance}'],
      [en ? 'Absence records' : 'سجلات الغياب', '${s.absence}'],
      [en ? 'Containers' : 'الحاويات', '${s.containersTotal}'],
      [en ? 'Full containers' : 'حاويات ممتلئة', '${s.containersFull}'],
      [en ? 'Partial containers' : 'حاويات نصف ممتلئة', '${s.containersPartial}'],
      [en ? 'Empty containers' : 'حاويات فارغة', '${s.containersEmpty}'],
      [en ? 'Container issues' : 'مشكلات الحاويات', '${s.containerIssues}'],
      [en ? 'Emergencies' : 'الطوارئ', '${s.emergencies}'],
      [en ? 'Open emergencies' : 'الطوارئ المفتوحة', '${s.emergencyOpen}'],
      [en ? 'Secured emergencies' : 'الطوارئ المؤمنة', '${s.emergencySecured}'],
      [en ? 'PPE compliance rate' : 'نسبة الالتزام بمعدات الوقاية', '${(s.ppeRate * 100).toStringAsFixed(1)}%'],
      [en ? 'Attendance rate' : 'نسبة الحضور', '${(s.attendanceRate * 100).toStringAsFixed(1)}%'],
    ];
    String quote(String value) { final q = String.fromCharCode(34); return q + value.replaceAll(q, q + q) + q; }
    final csv = rows.map((row) => row.map(quote).join(',')).join('\r\n');
    return <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(csv)];
  }

  List<int> buildOperationalExcelBytes(ReportSnapshot s, {String languageCode = 'ar'}) {
    final en = languageCode == 'en';
    final excel = Excel.createExcel();
    final sheet = excel['Report'];
    sheet.appendRow([TextCellValue(en ? 'Metric' : 'المؤشر'), TextCellValue(en ? 'Value' : 'القيمة')]);
    final rows = <List<String>>[
      [en ? 'Report ID' : 'معرّف التقرير', s.reportId],
      [en ? 'Period' : 'الفترة', s.periodLabel],
      [en ? 'Municipality' : 'البلديات', s.selectedMunicipality ?? s.municipalityNames.join('، ')],
      [en ? 'Groups' : 'المجموعات', '${s.groups}'], [en ? 'Workers' : 'العمال', '${s.workers}'],
      [en ? 'Supervisors' : 'المشرفون', '${s.supervisors}'], [en ? 'Trips' : 'النقلات', '${s.trips}'],
      [en ? 'Alternative trips' : 'النقلات البديلة', '${s.alternativeTrips}'],
      [en ? 'Present records' : 'سجلات الحضور', '${s.attendance}'], [en ? 'Absence records' : 'سجلات الغياب', '${s.absence}'],
      [en ? 'Containers' : 'الحاويات', '${s.containersTotal}'], [en ? 'Full containers' : 'حاويات ممتلئة', '${s.containersFull}'],
      [en ? 'Partial containers' : 'حاويات نصف ممتلئة', '${s.containersPartial}'], [en ? 'Empty containers' : 'حاويات فارغة', '${s.containersEmpty}'],
      [en ? 'Container issues' : 'مشكلات الحاويات', '${s.containerIssues}'], [en ? 'Emergencies' : 'الطوارئ', '${s.emergencies}'],
      [en ? 'Open emergencies' : 'الطوارئ المفتوحة', '${s.emergencyOpen}'], [en ? 'Secured emergencies' : 'الطوارئ المؤمنة', '${s.emergencySecured}'],
      [en ? 'PPE compliance rate' : 'نسبة الالتزام بمعدات الوقاية', '${(s.ppeRate * 100).toStringAsFixed(1)}%'],
      [en ? 'Attendance rate' : 'نسبة الحضور', '${(s.attendanceRate * 100).toStringAsFixed(1)}%'],
    ];
    for (final row in rows) { sheet.appendRow(row.map((v) => TextCellValue(v)).toList()); }
    final bytes = excel.encode();
    if (bytes == null) throw StateError('تعذر إنشاء ملف Excel.');
    return bytes;
  }

  Future<String?> exportOperationalCsv({required ReportSnapshot snapshot, required AppUser user, String languageCode = 'ar'}) async {
    final bytes = buildOperationalCsvBytes(snapshot, languageCode: languageCode);
    final path = await saveReportBytes(bytes, 'operational_report_${DateTime.now().millisecondsSinceEpoch}_$languageCode.csv', mimeType: 'text/csv; charset=utf-8');
    await data.writeAudit(actorId: user.id, operation: 'EXPORT_OPERATIONAL_CSV', targetId: snapshot.reportId, after: {'period': snapshot.periodLabel, 'languageCode': languageCode});
    return path;
  }

  Future<String?> exportOperationalExcel({required ReportSnapshot snapshot, required AppUser user, String languageCode = 'ar'}) async {
    final bytes = buildOperationalExcelBytes(snapshot, languageCode: languageCode);
    final path = await saveReportBytes(bytes, 'operational_report_${DateTime.now().millisecondsSinceEpoch}_$languageCode.xlsx', mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    await data.writeAudit(actorId: user.id, operation: 'EXPORT_OPERATIONAL_EXCEL', targetId: snapshot.reportId, after: {'period': snapshot.periodLabel, 'languageCode': languageCode});
    return path;
  }

  String _englishReportTitle(String title) {
    const map = <String, String>{
      'تقرير الغياب والحضور — CleanOps': 'Attendance & Absence Report — CleanOps',
      'تقرير الحاويات — CleanOps': 'Container Report — CleanOps',
      'تقرير العمل والتشغيل — CleanOps': 'Work & Operations Report — CleanOps',
      'تقرير الدورات — CleanOps': 'Work Cycles Report — CleanOps',
      'تقرير البلديات — CleanOps': 'Municipality Report — CleanOps',
      'تقرير المجموعات — CleanOps': 'Groups Report — CleanOps',
      'التقرير التنفيذي الشامل — CleanOps': 'Executive Summary Report — CleanOps',
    };
    return map[title] ?? title.replaceAll('التقرير التشغيلي لمنظومة جمع النفايات', 'Solid Waste Operations Report');
  }

}
