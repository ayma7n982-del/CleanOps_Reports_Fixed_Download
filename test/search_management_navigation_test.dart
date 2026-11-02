import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/models/core_models.dart';
import 'package:solid_waste_operations/core/services/fast_smart_search.dart';
import 'package:solid_waste_operations/presentation/screens/enterprise_operations_hub.dart';
import 'package:solid_waste_operations/presentation/screens/operations_management.dart';
import 'package:solid_waste_operations/presentation/screens/user_management_settings.dart';
import 'package:solid_waste_operations/presentation/screens/container_management.dart';
import 'package:solid_waste_operations/presentation/screens/equipment_search.dart';
import 'package:solid_waste_operations/presentation/widgets/operations_overview.dart';

AppUser actor(String role) => AppUser(
  id: 'actor',
  username: 'actor',
  name: 'مدير',
  role: role,
  scope: 'all',
  policies: const {},
);
FastSearchRecord record(String source, String category) => FastSearchRecord(
  collection: source,
  id: 'exact-document',
  category: category,
  data: {'name': 'اسم مكرر', '_entity': 'group'},
);

void main() {
  test('users route to selected account for L4 and L2', () {
    final l4 = searchRecordManagementPage(
      actor('donor_manager'),
      record('users', 'عامل'),
    ) as UserManagementSettingsPage;
    final l2 = searchRecordManagementPage(
      actor('municipality_coordinator'),
      record('users', 'عامل'),
    ) as OperationsManagementScreen;
    expect(l4.focusRecordId, 'exact-document');
    expect(l2.focusRecordId, 'exact-document');
    expect(l2.initialTab, 0);
  });

  test('groups, containers and dumpsites retain exact IDs', () {
    final manager = actor('donor_manager');
    expect(
      (searchRecordManagementPage(
        manager,
        record('operations', 'مجموعة'),
      ) as GroupsCommandCenterPage).focusRecordId,
      'exact-document',
    );
    expect(
      (searchRecordManagementPage(
        manager,
        record('containers', 'حاوية'),
      ) as ContainerManagementScreen).focusRecordId,
      'exact-document',
    );
    expect(
      (searchRecordManagementPage(
        manager,
        record('dumpsites', 'مكب'),
      ) as DumpsitesOverviewScreen).focusRecordId,
      'exact-document',
    );
    final l2 = searchRecordManagementPage(
      actor('municipality_coordinator'),
      record('dumpsites', 'مكب'),
    ) as OperationsManagementScreen;
    expect(l2.focusRecordId, 'exact-document');
    expect(l2.initialTab, 1);
  });

  test(
    'equipment with same ID in different collections selects correct path',
    () {
      for (final source in ['equipment', 'operations', 'remote_operations']) {
        final page = searchRecordManagementPage(
          actor('donor_manager'),
          record(source, 'معدة'),
        ) as EquipmentSearchScreen;
        expect(page.focusRecordId, 'exact-document');
        expect(
          page.focusCollection,
          source == 'remote_operations' ? 'operations' : source,
        );
      }
    },
  );

  test('cycles, trips and closed alerts can reach the selected record', () {
    final manager = actor('donor_manager');
    expect(
      (searchRecordManagementPage(
        manager,
        record('work_cycles', 'دورة'),
      ) as OperationsManagementScreen).focusRecordId,
      'exact-document',
    );
    expect(
      (searchRecordManagementPage(
        manager,
        record('operations', 'نقلة'),
      ) as TripsLogPage).focusRecordId,
      'exact-document',
    );
    expect(
      (searchRecordManagementPage(
        manager,
        record('operations', 'طوارئ'),
      ) as AlertsCenterPage).focusRecordId,
      'exact-document',
    );
  });

  test('legacy records never open unrelated generic management lists', () {
    final manager = actor('donor_manager');
    for (final category in [
      'عامل',
      'مكب',
      'حاوية',
      'دورة',
      'تقرير',
      'بلدية',
      'عملية',
      'حضور',
    ]) {
      expect(
        searchRecordManagementPage(manager, record('operations', category)),
        isNull,
      );
    }
  });

  test('supervisors cannot enter group or equipment management', () {
    final supervisor = actor('group_supervisor');
    expect(
      searchRecordManagementPage(supervisor, record('operations', 'مجموعة')),
      isNull,
    );
    expect(
      searchRecordManagementPage(supervisor, record('equipment', 'معدة')),
      isNull,
    );
    expect(
      searchRecordManagementPage(supervisor, record('users', 'عامل')),
      isNull,
    );
  });
}
