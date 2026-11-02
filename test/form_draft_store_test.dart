import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solid_waste_operations/core/services/form_draft_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'scope separates users, roles, groups, records, days and delimiters',
    () {
      final scopes = [
        ['a', 'role', 'g', 'attendance:2026-11-02:morning'],
        ['b', 'role', 'g', 'attendance:2026-11-02:morning'],
        ['a', 'other', 'g', 'attendance:2026-11-02:morning'],
        ['a', 'role', 'h', 'attendance:2026-11-02:morning'],
        ['a', 'role', 'g', 'attendance:2026-11-03:morning'],
        ['a', 'role', 'g', 'attendance:2026-11-02:evening'],
        ['a|role', 'g'],
        ['a', 'role|g'],
      ];
      expect(scopes.map(FormDraftStore.key).toSet().length, scopes.length);
    },
  );
  test(
    'rapid edits are snapshotted and a reopen waits for the latest write',
    () async {
      final key = FormDraftStore.key(['user', 'daily-work']);
      final state = <String, dynamic>{
        'fields': {'quantity': '12'},
        'values': {'date': '2026-11-02'},
      };
      final first = FormDraftStore.write(key, state);
      (state['fields'] as Map)['quantity'] = '15';
      final last = FormDraftStore.write(key, state);
      final restored = await FormDraftStore.read(key);
      await Future.wait([first, last]);
      expect(restored?['fields']['quantity'], '15');
    },
  );
  test(
    'successful submission clears all pending writes without resurrection',
    () async {
      final key = FormDraftStore.key(['user', 'container:1']);
      final write = FormDraftStore.write(key, {
        'fields': {'name': 'Draft'},
        'values': {},
      });
      final clear = FormDraftStore.clear(key);
      expect(await FormDraftStore.read(key), isNull);
      await Future.wait([write, clear]);
    },
  );
  test(
    'corrupt draft is reported and other drafts remain accessible',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bad', '{');
      await expectLater(FormDraftStore.read('bad'), throwsFormatException);
      await FormDraftStore.write('good', {'fields': {}, 'values': {}});
      expect(await FormDraftStore.read('good'), isNotNull);
    },
  );
}
