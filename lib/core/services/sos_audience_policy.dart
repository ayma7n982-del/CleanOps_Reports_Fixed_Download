/// Client-side scoping of locally displayed SOS alerts.
///
/// This mirrors the existing operation read permissions for L2/L3/L4. It does
/// not grant Firestore access; server-side security rules remain authoritative.
/// A local alert is not proof of delivery to an external responder.
class SosAudiencePolicy {
  static bool isManagementRole(String role) => const {
    'municipality_coordinator', 'jsc_coordinator', 'donor_manager',
  }.contains(role);

  static bool canSeeEmergency({
    required String role,
    required String uid,
    required Map<String, dynamic> emergency,
  }) {
    if (!isManagementRole(role) || uid.isEmpty ||
        emergency['_entity'] != 'emergency' ||
        emergency['isDeleted'] == true ||
        emergency['status'] == 'closed') {
      return false;
    }
    if (role == 'municipality_coordinator') {
      return emergency['municipalityCoordinatorId'] == uid;
    }
    return role == 'jsc_coordinator' || role == 'donor_manager';
  }
}
