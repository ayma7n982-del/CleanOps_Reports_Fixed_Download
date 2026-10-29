import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/fast_smart_search.dart';

void main() {
  group('FastSmartSearch Arabic offline index', () {
    late FastSmartSearch index;

    setUp(() {
      index = FastSmartSearch();
      index.replaceSource('users', 'عامل', [
        {'id': 'worker-1', 'fullName': 'محمد صالح', 'role': 'worker'},
        {'id': 'worker-2', 'fullName': 'أحمد عبد الرحمن', 'role': 'worker'},
        {'id': 'deleted', 'fullName': 'عامل محذوف', 'isDeleted': true},
      ]);
      index.replaceSource('dumpsites', 'مكب', [
        {'id': 'dump-1', 'name': 'مكب دير البلح', 'status': 'full'},
      ]);
      index.replaceSource('containers', 'حاوية', [
        {'id': 'container-1', 'locationName': 'حاوية شارع المدارس', 'status': 'empty'},
      ]);
      index.replaceSource('equipment', 'معدة', [
        {'id': 'cart-1', 'equipmentName': 'كارة المجموعة الثالثة'},
      ]);
    });

    test('starts finding names from the very first Arabic character', () {
      expect(index.find('م').map((r) => r.id), contains('worker-1'));
      expect(index.find('أح').map((r) => r.id), contains('worker-2'));
      expect(index.find('دير').map((r) => r.id), contains('dump-1'));
    });

    test('normalizes hamza, diacritics, ta marbuta and Arabic digits', () {
      expect(FastSmartSearch.normalize('إِدَارَة ١٢'), 'اداره 12');
      expect(index.find('حاويه').map((r) => r.id), contains('container-1'));
      expect(index.find('احمد').map((r) => r.id), contains('worker-2'));
    });

    test('accepts typos and adjacent character transposition', () {
      expect(index.find('البلخ').map((r) => r.id), contains('dump-1'));
      expect(index.find('مكباات').map((r) => r.id), contains('dump-1'));
      expect(index.find('المدارس').map((r) => r.id), contains('container-1'));
    });

    test('recognizes waste-management synonyms and dialect words', () {
      expect(index.find('مطمر').map((r) => r.id), contains('dump-1'));
      expect(index.find('كونتينر').map((r) => r.id), contains('container-1'));
      expect(index.find('عربة').map((r) => r.id), contains('cart-1'));
      expect(index.find('موظف').map((r) => r.id), contains('worker-1'));
    });

    test('multiple query tokens must all be present or synonymous', () {
      expect(index.find('مكب البلح').first.id, 'dump-1');
      expect(index.find('مكب المدارس'), isEmpty);
    });

    test('ranks exact names first and excludes deleted documents', () {
      final names = index.find('محمد').map((r) => r.title).toList();
      expect(names.first, 'محمد صالح');
      expect(index.find('محذوف'), isEmpty);
    });

    test('replaces source atomically without retaining obsolete records', () {
      index.replaceSource('dumpsites', 'مكب', [
        {'id': 'dump-2', 'name': 'مكب جديد'},
      ]);
      expect(index.find('دير البلح'), isEmpty);
      expect(index.find('جديد').map((r) => r.id), contains('dump-2'));
    });

    test('does not show other collections unless actually supplied', () {
      final isolated = FastSmartSearch()
        ..replaceSource('containers', 'حاوية', [
          {'id': 'own-1', 'locationName': 'حاوية المجموعة'},
        ]);
      expect(isolated.find('محمد'), isEmpty);
      expect(isolated.find('حاويه').single.id, 'own-1');
    });
  });
}
