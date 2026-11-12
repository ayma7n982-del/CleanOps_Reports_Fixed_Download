import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solid_waste_operations/core/services/report_branding_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const local = {
    'report_municipality_name': 'A', 'report_municipality_logo_base64': 'logo-A',
    'report_council_name': 'Council A', 'report_council_logo_base64': 'council-logo',
    'report_project_name': 'Old cycle',
  };
  test('selected municipality and cycle override local defaults without borrowing another logo', () {
    final identity = ReportBrandingStore.resolve(local, municipality: 'B', council: 'Council B', project: 'Selected cycle');
    expect(identity.getString('report_municipality_name'), 'B');
    expect(identity.getString('report_project_name'), 'Selected cycle');
    expect(identity.getString('report_municipality_logo_base64'), isNull);
    expect(identity.getString('report_council_logo_base64'), isNull);
    expect(ReportBrandingStore.resolve(local, municipality: 'A').getString('report_municipality_logo_base64'), 'logo-A');
  });
  test('multi-municipality report does not inherit a single municipality identity', () {
    final identity = ReportBrandingStore.resolve(local, allowLocalMunicipality: false, allowLocalCouncil: false);
    expect(identity.getString('report_municipality_name'), isNull);
    expect(identity.getString('report_municipality_logo_base64'), isNull);
    expect(identity.getString('report_council_name'), isNull);
  });
  test('published scoped cache is usable offline and isolated from other municipalities', () async {
    SharedPreferences.setMockInitialValues({
      ...local,
      'report_branding_cache_municipality:B': jsonEncode({
        'report_municipality_name': 'B', 'report_municipality_logo_base64': 'logo-B',
      }),
    });
    expect((await ReportBrandingStore.read(municipality: 'B')).getString('report_municipality_logo_base64'), 'logo-B');
    expect((await ReportBrandingStore.read(municipality: 'A')).getString('report_municipality_logo_base64'), 'logo-A');
  });
}
