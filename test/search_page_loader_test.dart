import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/search_page_loader.dart';
import 'package:solid_waste_operations/core/services/fast_smart_search.dart';

void main() {
  test('finds the final record beyond the former 800 and 1000 caps', () async {
    final index = FastSmartSearch();
    final rows = <Map<String, dynamic>>[];
    final cursors = <int?>[];
    await for (final page in readSearchPages<int>(
      fetchPage: (after, size) async {
        cursors.add(after);
        final start = (after ?? -1) + 1;
        return List.generate((2501 - start).clamp(0, size), (i) => start + i);
      },
    )) {
      rows.addAll(page.map((id) => {'id': '$id', 'name': 'عامل $id'}));
      index.replaceSource('users', 'عامل', rows);
    }
    expect(cursors, [null, 399, 799, 1199, 1599, 1999, 2399]);
    expect(index.recordCount, 2501);
    expect(index.find('2500').first.id, '2500');
  });

  test(
    'checks an empty last page when total is an exact page multiple',
    () async {
      var requests = 0;
      final pages = await readSearchPages<int>(
        pageSize: 2,
        fetchPage: (after, _) async {
          requests++;
          return after == null
              ? [0, 1]
              : after == 1
              ? [2, 3]
              : [];
        },
      ).toList();
      expect(pages, [
        [0, 1],
        [2, 3],
      ]);
      expect(requests, 3);
    },
  );

  test('retains emitted pages and reports later-page failure', () async {
    final loaded = <int>[];
    await expectLater(() async {
      await for (final page in readSearchPages<int>(
        pageSize: 2,
        fetchPage: (after, _) async {
          if (after != null) throw StateError('offline');
          return [0, 1];
        },
      )) {
        loaded.addAll(page);
      }
    }(), throwsStateError);
    expect(loaded, [0, 1]);
  });

  test('does not fetch another page after cancellation', () async {
    var active = true;
    var requests = 0;
    await for (final _ in readSearchPages<int>(
      pageSize: 2,
      isActive: () => active,
      fetchPage: (after, _) async {
        requests++;
        return [0, 1];
      },
    )) {
      active = false;
    }
    expect(requests, 1);
  });

  test('global results include every category beyond first 100 matches', () {
    final index = FastSmartSearch()
      ..replaceSource(
        'users',
        'عامل',
        List.generate(150, (id) => {'id': '$id', 'name': 'مشترك عامل $id'}),
      )
      ..replaceSource('equipment', 'معدة', [
        {'id': 'last', 'name': 'مشترك معدة متأخرة'},
      ]);
    final results = index.find('مشترك', limit: index.recordCount);
    expect(results.length, 151);
    expect(results.where((row) => row.category == 'معدة').single.id, 'last');
  });

  test(
    'deduplicates cache/server copies by path, preserving other collections',
    () {
      final index = FastSmartSearch()
        ..replaceSource('operations', 'عملية', [
          {'id': 'same', 'name': 'مميز محلي'},
        ])
        ..replaceSource('remote_operations', 'عملية', [
          {'id': 'same', 'name': 'مميز خادم'},
        ], collection: 'operations')
        ..replaceSource('equipment', 'معدة', [
          {'id': 'same', 'name': 'مميز معدات'},
        ]);
      final results = index.find('مميز');
      expect(results.length, 2);
      expect(
        results.map((row) => '${row.collection}/${row.id}'),
        containsAll(['operations/same', 'equipment/same']),
      );
      expect(
        results.firstWhere((row) => row.collection == 'operations').title,
        'مميز محلي',
      );
    },
  );
}
