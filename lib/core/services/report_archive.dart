part of 'report_service.dart';

/// Only fields used to render the submitted report leave the operational cache.
class ReportArchive {
  static Map<String, dynamic> _values(ReportSnapshot s) {
    List<Map<String, String>> records(List<Map<String, dynamic>> source) => [
          for (final row in source)
            {
              for (final key in const [
                'id',
                'locationName',
                'title',
                'location',
                'municipalityName',
                'groupName',
                'status'
              ])
                if (row[key] != null) key: row[key].toString(),
            }
        ]..sort((a, b) => (a['id'] ?? '').compareTo(b['id'] ?? ''));
    return {
      'trips': s.trips,
      'alternativeTrips': s.alternativeTrips,
      'attendance': s.attendance,
      'absence': s.absence,
      'ppeCompliant': s.ppeCompliant,
      'emergencies': s.emergencies,
      'emergencyOpen': s.emergencyOpen,
      'emergencySecured': s.emergencySecured,
      'containersTotal': s.containersTotal,
      'containersFull': s.containersFull,
      'containersPartial': s.containersPartial,
      'containersEmpty': s.containersEmpty,
      'containerIssues': s.containerIssues,
      'workers': s.workers,
      'supervisors': s.supervisors,
      'groups': s.groups,
      'municipalities': s.municipalities,
      'dumpsites': s.dumpsites,
      'cycleCount': s.cycleCount,
      'landfillCapacity': s.landfillCapacity,
      'heavyMachineryHours': s.heavyMachineryHours,
      'tripsByGroup': SplayTreeMap<String, int>.from(s.tripsByGroup),
      'tripsByDay': SplayTreeMap<String, int>.from(s.tripsByDay),
      'attendanceByGroup': SplayTreeMap<String, int>.from(s.attendanceByGroup),
      'ppeByGroup': SplayTreeMap<String, int>.from(s.ppeByGroup),
      'emergenciesByGroup':
          SplayTreeMap<String, int>.from(s.emergenciesByGroup),
      'containerByStatus': SplayTreeMap<String, int>.from(s.containerByStatus),
      'tripsByMunicipality':
          SplayTreeMap<String, int>.from(s.tripsByMunicipality),
      'attendanceByMunicipality':
          SplayTreeMap<String, int>.from(s.attendanceByMunicipality),
      'absenceByGroup': SplayTreeMap<String, int>.from(s.absenceByGroup),
      'containersByMunicipality':
          SplayTreeMap<String, int>.from(s.containersByMunicipality),
      'containersByGroup': SplayTreeMap<String, int>.from(s.containersByGroup),
      'municipalityNames': s.municipalityNames,
      'cycles': s.cycles,
      'councilLabel': s.councilLabel,
      'cycleLabel': s.cycleLabel,
      'selectedMunicipality': s.selectedMunicipality,
      'selectedGroup': s.selectedGroup,
      'selectedCycle': s.selectedCycle,
      'reportType': s.reportType,
      'periodLabel': s.periodLabel,
      'search': s.search,
      'containerStatus': s.containerStatus,
      'sourceMayBeIncomplete': s.sourceMayBeIncomplete,
      'containerRecords':
          s.reportType == 'containers' ? records(s.containerRecords) : [],
      'tripRecords': s.reportType == 'trips' ? records(s.tripRecords) : [],
      'completedTrips': s.completedTrips,
      'ratios': [
        for (final r in s.ratioInsights)
          [r.id, r.ar, r.en, r.value, r.basisAr, r.basisEn, r.signed, r.points]
      ],
    };
  }

  static String documentId(ReportSnapshot s, String ownerId) =>
      'CO-${const Uuid().v5(Uuid.NAMESPACE_URL, jsonEncode([
                ownerId,
                s.reportId,
                _values(s)
              ]))}';

  static Map<String, dynamic> submission(ReportSnapshot s, {bool offline = false}) {
    final values = _values(s)
      ..['generatedAt'] = s.generatedAt.toIso8601String()
      ..['sourceMayBeIncomplete'] = offline || s.sourceMayBeIncomplete;
    final bytes = GZipEncoder().encode(utf8.encode(jsonEncode(values)))!;
    final packed = base64Encode(bytes);
    if (packed.length > 900000)
      throw StateError(
          'حجم النسخة يتجاوز سعة السجل. اختر فترة أقصر أو مجموعة محددة.');
    return {
      'archiveV1': packed,
      'partialSource': offline || s.sourceMayBeIncomplete,
      'snapshot': {
        'trips': s.trips,
        'completedTrips': s.completedTrips,
        'attendance': s.attendance,
        'absence': s.absence,
        'workers': s.workers,
        'supervisors': s.supervisors,
        'groups': s.groups,
        'containers': s.containersTotal,
        'emergencies': s.emergencies
      },
    };
  }

  static ReportSnapshot read(Map<String, dynamic> row) {
    final packed = row['archiveV1'];
    final legacy = packed == null;
    final m = legacy
        ? Map<String, dynamic>.from(row['snapshot'] as Map)
        : Map<String, dynamic>.from(jsonDecode(utf8.decode(
            GZipDecoder().decodeBytes(base64Decode(packed as String)))) as Map);
    Map<String, int> totals(String key) => Map<String, int>.from(m[key] ?? {});
    List<Map<String, dynamic>> records(String key) => [
          for (final r in m[key] ?? const [])
            Map<String, dynamic>.from(r as Map)
        ];
    final generated = m['generatedAt'] ?? row['createdAt'];
    return ReportSnapshot(
      reportId: row['id'] as String,
      generatedAt: generated is Timestamp
          ? generated.toDate()
          : DateTime.parse(generated.toString()),
      periodLabel: (m['periodLabel'] ?? row['period'] ?? '').toString(),
      legacyCounts: legacy ? m : null,
      reviewer: (row['approvedByName'] ?? row['approvedBy'])?.toString(),
      approvalTime: row['approvedAt']?.toString(),
      preparer: (row['requesterName'] ?? row['requestedBy'])?.toString(),
      archivedCompletedTrips: m['completedTrips'] as int?,
      search: (m['search'] ?? row['search'] ?? '').toString(),
      containerStatus:
          (m['containerStatus'] ?? row['containerStatus'] ?? 'all').toString(),
      sourceMayBeIncomplete: m['sourceMayBeIncomplete'] == true,
      ratioInsights: [
        for (final r in m['ratios'] ?? const [])
          ReportRatio(r[0], r[1], r[2], (r[3] as num?)?.toDouble(), r[4], r[5],
              signed: r[6], points: r[7])
      ],
      containerRecords: records('containerRecords'),
      tripRecords: records('tripRecords'),
      trips: (m['trips'] as num?)?.toInt() ?? 0,
      alternativeTrips: (m['alternativeTrips'] as num?)?.toInt() ?? 0,
      attendance: (m['attendance'] as num?)?.toInt() ?? 0,
      absence: (m['absence'] as num?)?.toInt() ?? 0,
      ppeCompliant: (m['ppeCompliant'] as num?)?.toInt() ?? 0,
      emergencies: (m['emergencies'] as num?)?.toInt() ?? 0,
      emergencyOpen: (m['emergencyOpen'] as num?)?.toInt() ?? 0,
      emergencySecured: (m['emergencySecured'] as num?)?.toInt() ?? 0,
      containersTotal:
          ((m['containersTotal'] ?? m['containers']) as num?)?.toInt() ?? 0,
      containersFull: (m['containersFull'] as num?)?.toInt() ?? 0,
      containersPartial: (m['containersPartial'] as num?)?.toInt() ?? 0,
      containersEmpty: (m['containersEmpty'] as num?)?.toInt() ?? 0,
      containerIssues: (m['containerIssues'] as num?)?.toInt() ?? 0,
      workers: (m['workers'] as num?)?.toInt() ?? 0,
      supervisors: (m['supervisors'] as num?)?.toInt() ?? 0,
      groups: (m['groups'] as num?)?.toInt() ?? 0,
      municipalities: (m['municipalities'] as num?)?.toInt() ?? 0,
      dumpsites: (m['dumpsites'] as num?)?.toInt() ?? 0,
      cycleCount: (m['cycleCount'] as num?)?.toInt() ?? 0,
      landfillCapacity: (m['landfillCapacity'] as num?)?.toDouble() ?? 0,
      heavyMachineryHours: (m['heavyMachineryHours'] as num?)?.toDouble() ?? 0,
      tripsByGroup: totals('tripsByGroup'),
      tripsByDay: totals('tripsByDay'),
      attendanceByGroup: totals('attendanceByGroup'),
      ppeByGroup: totals('ppeByGroup'),
      emergenciesByGroup: totals('emergenciesByGroup'),
      containerByStatus: totals('containerByStatus'),
      tripsByMunicipality: totals('tripsByMunicipality'),
      attendanceByMunicipality: totals('attendanceByMunicipality'),
      absenceByGroup: totals('absenceByGroup'),
      containersByMunicipality: totals('containersByMunicipality'),
      containersByGroup: totals('containersByGroup'),
      municipalityNames: List<String>.from(m['municipalityNames'] ?? []),
      cycles: List<String>.from(m['cycles'] ?? []),
      selectedMunicipality:
          (m['selectedMunicipality'] ?? row['municipality']) as String?,
      selectedGroup: (m['selectedGroup'] ?? row['group']) as String?,
      councilLabel: '${m['councilLabel'] ?? row['councilName'] ?? ''}',
      cycleLabel: '${m['cycleLabel'] ?? row['cycleName'] ?? ''}',
      selectedCycle: (m['selectedCycle'] ?? row['cycle']) as String?,
      reportType: (m['reportType'] ?? row['reportType']) as String?,
    );
  }
}
