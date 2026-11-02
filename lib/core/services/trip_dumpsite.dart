/// Destination snapshot for new trips. Historical trips keep their saved names.
class TripDumpsite {
  final String id, name, location;
  const TripDumpsite(this.id, this.name, this.location);

  static TripDumpsite? fromRecord(String id, Map<String, dynamic> data) {
    if (id.trim().isEmpty ||
        data['isActive'] != true ||
        data['isDeleted'] == true)
      return null;
    String value(String key) => '${data[key] ?? ''}'.trim();
    final name = [
      value('nameAr'),
      value('name'),
      value('nameEn'),
    ].firstWhere((s) => s.isNotEmpty, orElse: () => '');
    if (name.isEmpty) return null;
    return TripDumpsite(id, name, value('location'));
  }

  Map<String, String> get tripFields => {
    'dumpsiteId': id,
    'dumpsiteName': name,
    'dumpsiteLocation': location,
    // Retain the field used by current reports and older app versions.
    'landfill': name,
  };
}

TripDumpsite resolveTripDestination(
  List<TripDumpsite> sites,
  Map<String, String> route,
) {
  final id = route['dumpsiteId'] ?? '';
  final matches = sites
      .where(
        (site) =>
            id.isNotEmpty ? site.id == id : site.name == route['landfill'],
      )
      .toList();
  if (matches.length != 1) {
    throw StateError(
      'المكب المحدد أو المحوّل إليه غير متاح. حدّث القائمة وراجع المنسق.',
    );
  }
  return matches.single;
}

/// Apply already filtered, newest-first directives by ID; names support legacy
/// directives only. Identical names and later renames must not change routing.
Map<String, String> applyDumpsiteRoutes(
  String requested,
  String requestedId,
  List<Map<String, dynamic>> routes,
) {
  var name = requested, id = requestedId;
  final used = <String>[];
  final visited = <String>{id.isEmpty ? name : id};
  for (var step = 0; step < routes.length; step++) {
    Map<String, dynamic>? match;
    for (final route in routes) {
      final detail = route['details'];
      if (detail is! Map) continue;
      final sourceId = '${detail['sourceId'] ?? ''}';
      if (id.isNotEmpty && sourceId.isNotEmpty
          ? sourceId == id
          : detail['sourceName'] == name) {
        match = route;
        break;
      }
    }
    if (match == null) break;
    final detail = match['details'] as Map;
    name = '${detail['alternativeName'] ?? ''}'.trim();
    id = '${detail['alternativeId'] ?? ''}'.trim();
    if (name.isEmpty || !visited.add(id.isEmpty ? name : id)) {
      throw StateError(
        'يوجد تعارض في توجيهات المكبات. راجع المنسق قبل تسجيل النقلة.',
      );
    }
    used.add('${match['id']}');
  }
  return {
    'landfill': name,
    if (id.isNotEmpty) 'dumpsiteId': id,
    if (used.isNotEmpty) 'routeDecisionId': used.join(','),
  };
}
