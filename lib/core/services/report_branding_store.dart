import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Scoped shared identity with a durable offline copy. Existing local settings
/// remain the fallback until the manager publishes an identity for this scope.
class ReportBrandingStore {
  static const keys = [
    'report_municipality_name', 'report_council_name', 'report_project_name',
    'report_municipality_logo_base64', 'report_council_logo_base64', 'report_unicef_logo_base64',
  ];
  final Map<String, String> _values;
  ReportBrandingStore._(this._values);
  String? getString(String key) {
    final value = _values[key];
    return value == null || value.isEmpty ? null : value;
  }

  static String _scope(String municipality, String council) => municipality.isNotEmpty
      ? 'municipality:$municipality' : council.isNotEmpty ? 'council:$council' : '';
  static String _document(String scope) => 'report_branding_${base64Url.encode(utf8.encode(scope)).replaceAll('=', '')}';

  static ReportBrandingStore resolve(Map<String, String> settings, {
    String municipality = '', String council = '', String project = '',
    bool allowLocalMunicipality = true, bool allowLocalCouncil = true,
  }) {
    final values = Map<String, String>.from(settings);
    final configuredMunicipality = values['report_municipality_name'] ?? '';
    if (municipality.isNotEmpty && municipality != configuredMunicipality ||
        !allowLocalMunicipality && municipality.isEmpty) {
      values.remove('report_municipality_logo_base64');
      if (municipality.isNotEmpty && municipality != configuredMunicipality && council.isEmpty) {
        values.remove('report_council_name'); values.remove('report_council_logo_base64');
      }
    }
    if (municipality.isNotEmpty || !allowLocalMunicipality) {
      values['report_municipality_name'] = municipality;
    }
    if (!allowLocalCouncil && council.isEmpty) {
      values.remove('report_council_name'); values.remove('report_council_logo_base64');
    }
    if (council.isNotEmpty) {
      if (council != values['report_council_name']) values.remove('report_council_logo_base64');
      values['report_council_name'] = council;
    }
    if (project.isNotEmpty) values['report_project_name'] = project;
    return ReportBrandingStore._(values);
  }

  static Future<ReportBrandingStore> read({String municipality = '', String council = '',
    String project = '', bool allowLocalMunicipality = true, bool allowLocalCouncil = true}) async {
    municipality = municipality.trim(); council = council.trim();
    final prefs = await SharedPreferences.getInstance();
    var values = {for (final key in keys) key: prefs.getString(key) ?? ''};
    final scope = _scope(municipality, council);
    if (scope.isNotEmpty) {
      final cacheKey = 'report_branding_cache_$scope';
      try {
        final cached = prefs.getString(cacheKey);
        if (cached != null) values = Map<String, String>.from(jsonDecode(cached) as Map);
      } catch (_) { /* Ignore an invalid local copy. */ }
      if (Firebase.apps.isNotEmpty) {
        try {
          final doc = await FirebaseFirestore.instance.collection('config').doc(_document(scope))
              .get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 5));
          final raw = doc.data();
          if (raw != null && raw['scope'] == scope) {
            values = {for (final key in keys) key: '${raw[key] ?? ''}'};
            await prefs.setString(cacheKey, jsonEncode(values));
          } else if (raw == null) {
            await prefs.remove(cacheKey);
            values = {for (final key in keys) key: prefs.getString(key) ?? ''};
          }
        } catch (_) { /* Use the cached identity when the server is unavailable. */ }
      }
    }
    return resolve(values, municipality: municipality, council: council, project: project,
        allowLocalMunicipality: allowLocalMunicipality, allowLocalCouncil: allowLocalCouncil);
  }

  /// Existing config rules permit publishing only by donor_manager.
  static Future<void> publish() async {
    if (Firebase.apps.isEmpty) throw StateError('الاتصال بالخادم غير متاح.');
    final prefs = await SharedPreferences.getInstance();
    final values = {for (final key in keys) key: (prefs.getString(key) ?? '').trim()};
    final scope = _scope(values['report_municipality_name']!, values['report_council_name']!);
    if (scope.isEmpty) throw StateError('حدد اسم البلدية أو المجلس قبل نشر الهوية.');
    if (utf8.encode(jsonEncode(values)).length > 750000) {
      throw StateError('حجم الشعارات كبير. اختر صورًا أصغر قبل نشر الهوية.');
    }
    await FirebaseFirestore.instance.collection('config').doc(_document(scope)).set({
      ...values, 'scope': scope, 'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(const Duration(seconds: 15));
    await prefs.setString('report_branding_cache_$scope', jsonEncode(values));
  }
}
