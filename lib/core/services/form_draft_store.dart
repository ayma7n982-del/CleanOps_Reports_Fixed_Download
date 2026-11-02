import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Durable device-only drafts. Keys isolate accounts, roles, groups and records.
/// Serialize per key across screen instances so an old write cannot resurrect a
/// submitted draft or race a newly opened screen's restore.
class FormDraftStore {
  static final Map<String, Future<void>> _pending = {};

  static String key(List<String> scope) =>
      'cleanops.form.v1.${scope.map(Uri.encodeComponent).join('|')}';

  static Future<T> _serial<T>(String key, Future<T> Function() work) {
    final prior = _pending[key] ?? Future<void>.value();
    final result = prior.then((_) => work());
    final done = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _pending[key] = done;
    done.whenComplete(() {
      if (identical(_pending[key], done)) _pending.remove(key);
    });
    return result;
  }

  static Future<Map<String, dynamic>?> read(String key) =>
      _serial(key, () async {
        final raw = (await SharedPreferences.getInstance()).getString(key);
        if (raw == null) return null;
        final value = jsonDecode(raw);
        if (value is! Map<String, dynamic>)
          throw const FormatException('Invalid form draft');
        return value;
      });

  static Future<void> write(String key, Map<String, dynamic> value) {
    final encoded = jsonEncode(
      value,
    ); // Snapshot before the asynchronous write.
    return _serial(key, () async {
      final ok = await (await SharedPreferences.getInstance()).setString(
        key,
        encoded,
      );
      if (!ok) throw StateError('Unable to save the form draft');
    });
  }

  static Future<void> clear(String key) => _serial(key, () async {
    final ok = await (await SharedPreferences.getInstance()).remove(key);
    if (!ok) throw StateError('Unable to clear the form draft');
  });
}
