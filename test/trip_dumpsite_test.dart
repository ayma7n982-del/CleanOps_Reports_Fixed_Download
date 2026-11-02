import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/trip_dumpsite.dart';

void main() {
  const a = TripDumpsite('a', 'المكب أ', 'موقع أ');
  const b = TripDumpsite('b', 'المكب ب', 'موقع ب');
  test(
    'only named active records become selectable, document ID is authoritative',
    () {
      expect(
        TripDumpsite.fromRecord('real-id', {
          'id': 'forged',
          'nameAr': 'مكب فعلي',
          'isActive': true,
        })!.id,
        'real-id',
      );
      for (final record in [
        {'nameAr': 'مغلق', 'isActive': false},
        {'nameAr': 'محذوف', 'isActive': true, 'isDeleted': true},
        {'isActive': true},
        {'nameAr': 'غير محدد'},
      ]) {
        expect(TripDumpsite.fromRecord('id', record), isNull);
      }
      expect(
        TripDumpsite.fromRecord('id', {
          'nameAr': ' ',
          'name': 'Legacy',
          'isActive': true,
        })!.name,
        'Legacy',
      );
    },
  );
  test(
    'saved destination keeps its ID and name snapshot for existing reports',
    () {
      final fields = Map<String, String>.from(a.tripFields);
      const renamed = TripDumpsite('a', 'اسم جديد', 'موقع جديد');
      expect(fields['dumpsiteId'], renamed.id);
      expect(fields['landfill'], 'المكب أ');
      expect(fields['dumpsiteName'], 'المكب أ');
      expect(fields['dumpsiteLocation'], 'موقع أ');
    },
  );
  test('no directive retains the explicitly chosen actual site', () {
    final route = applyDumpsiteRoutes(a.name, a.id, []);
    expect(resolveTripDestination([a, b], route).id, 'a');
    expect(route.containsKey('routeDecisionId'), isFalse);
  });
  test('redirect follows ID despite later name changes and keeps trace', () {
    final route = applyDumpsiteRoutes(a.name, a.id, [
      {
        'id': 'decision',
        'details': {
          'sourceId': 'a',
          'sourceName': 'Old A',
          'alternativeId': 'b',
          'alternativeName': 'Old B',
        },
      },
    ]);
    final destination = resolveTripDestination([a, b], route);
    expect(destination.tripFields['landfill'], b.name);
    expect(destination.id, 'b');
    expect(route['routeDecisionId'], 'decision');
  });
  test('same names cannot redirect a different ID', () {
    final route = applyDumpsiteRoutes(a.name, a.id, [
      {
        'id': 'other',
        'details': {
          'sourceId': 'other',
          'sourceName': a.name,
          'alternativeId': 'b',
          'alternativeName': b.name,
        },
      },
    ]);
    expect(route['dumpsiteId'], 'a');
  });
  test('chained redirects resolve final actual site; cycles are rejected', () {
    final routes = [
      {
        'id': 'one',
        'details': {
          'sourceId': 'a',
          'alternativeId': 'b',
          'alternativeName': b.name,
        },
      },
      {
        'id': 'two',
        'details': {
          'sourceId': 'b',
          'alternativeId': 'c',
          'alternativeName': 'C',
        },
      },
    ];
    expect(applyDumpsiteRoutes(a.name, a.id, routes)['dumpsiteId'], 'c');
    expect(
      () => applyDumpsiteRoutes(a.name, a.id, [
        ...routes,
        {
          'id': 'cycle',
          'details': {
            'sourceId': 'c',
            'alternativeId': 'a',
            'alternativeName': a.name,
          },
        },
      ]),
      throwsStateError,
    );
  });
  test(
    'inactive, removed, or ambiguous name-only destination blocks new trip',
    () {
      expect(
        () => resolveTripDestination([a], {'dumpsiteId': 'b'}),
        throwsStateError,
      );
      expect(
        () => resolveTripDestination([], {'landfill': a.name}),
        throwsStateError,
      );
      expect(
        () => resolveTripDestination(
          [a, TripDumpsite('other', a.name, '')],
          {'landfill': a.name},
        ),
        throwsStateError,
      );
    },
  );
}
