import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/models/core_models.dart';
import 'package:solid_waste_operations/core/services/assistant_shortcut_policy.dart';

AppUser user({
  required String role,
  Map<String, FeaturePolicy> policies = const {},
}) =>
    AppUser(
      id: 'u-$role',
      username: role,
      name: role,
      role: role,
      scope: role == 'jsc_coordinator' ? 'Council A' : 'all',
      policies: policies,
    );

void main() {
  test('AI shortcuts honor feature permissions instead of rendering inert buttons', () {
    final u = user(
      role: 'jsc_coordinator',
      policies: const {
        'reports': FeaturePolicy(view: true, export: false),
        'emergency': FeaturePolicy(view: false, visible: false),
        'trips': FeaturePolicy(view: true),
      },
    );

    final keys = AssistantShortcutPolicy.visibleKeys(
      u,
      liveOperationsMapEnabled: true,
    );

    expect(keys, contains('trips'));
    expect(keys, contains('reports'));
    expect(keys, isNot(contains('report_pdf')));
    expect(keys, isNot(contains('alerts')));
    expect(keys, contains('dumpsites'));
    expect(keys, contains('live_map'));
  });

  test('PDF shortcut appears only when reports export permission is granted', () {
    final denied = user(
      role: 'donor_manager',
      policies: const {
        'reports': FeaturePolicy(view: true, export: false),
      },
    );
    final allowed = user(
      role: 'donor_manager',
      policies: const {
        'reports': FeaturePolicy(view: true, export: true),
      },
    );

    expect(
      AssistantShortcutPolicy.visibleKeys(
        denied,
        liveOperationsMapEnabled: false,
      ),
      isNot(contains('report_pdf')),
    );
    expect(
      AssistantShortcutPolicy.visibleKeys(
        allowed,
        liveOperationsMapEnabled: false,
      ),
      contains('report_pdf'),
    );
  });

  test('live map disappears when operations permission is disabled', () {
    final u = user(
      role: 'donor_manager',
      policies: const {
        'operations': FeaturePolicy(view: false, visible: false),
      },
    );

    final keys = AssistantShortcutPolicy.visibleKeys(
      u,
      liveOperationsMapEnabled: true,
    );

    expect(keys, isNot(contains('operations')));
    expect(keys, isNot(contains('live_map')));
  });
}
