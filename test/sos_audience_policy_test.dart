import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/sos_audience_policy.dart';

void main() {
  final open = <String, dynamic>{
    '_entity': 'emergency',
    'id': 'sos-a',
    'status': 'urgent',
    'municipalityCoordinatorId': 'municipality-a',
  };

  test('assigned municipality receives its SOS but not another municipality', () {
    expect(SosAudiencePolicy.canSeeEmergency(
      role: 'municipality_coordinator', uid: 'municipality-a', emergency: open),
      isTrue);
    expect(SosAudiencePolicy.canSeeEmergency(
      role: 'municipality_coordinator', uid: 'municipality-b', emergency: open),
      isFalse);
  });

  test('council and donor can see open SOS without unresolved routing IDs', () {
    for (final role in ['jsc_coordinator', 'donor_manager']) {
      expect(SosAudiencePolicy.canSeeEmergency(
        role: role, uid: 'active-management', emergency: open), isTrue);
    }
  });

  test('workers, signed-out sessions and unrelated operations cannot receive it', () {
    expect(SosAudiencePolicy.canSeeEmergency(
      role: 'group_supervisor', uid: 'head-a', emergency: open), isFalse);
    expect(SosAudiencePolicy.canSeeEmergency(
      role: 'jsc_coordinator', uid: '', emergency: open), isFalse);
    expect(SosAudiencePolicy.canSeeEmergency(
      role: 'jsc_coordinator', uid: 'jsc',
      emergency: {...open, '_entity': 'notification'}), isFalse);
  });

  test('closed or deleted SOS no longer enters the alert inbox', () {
    expect(SosAudiencePolicy.canSeeEmergency(
      role: 'jsc_coordinator', uid: 'jsc',
      emergency: {...open, 'status': 'closed'}), isFalse);
    expect(SosAudiencePolicy.canSeeEmergency(
      role: 'donor_manager', uid: 'donor',
      emergency: {...open, 'isDeleted': true}), isFalse);
  });
}
