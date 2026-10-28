import '../models/core_models.dart';

/// Single source of truth for operational shortcuts exposed by CleanOps AI.
/// The UI may only render actions returned here, so a visible shortcut always
/// corresponds to a permission the signed-in user actually has.
class AssistantShortcutPolicy {
  static Set<String> visibleKeys(
    AppUser user, {
    required bool liveOperationsMapEnabled,
  }) {
    final keys = <String>{};

    if (user.can('messages', 'view')) keys.add('messages');
    if (user.can('operations', 'view')) keys.add('operations');
    if (user.can('trips', 'view')) keys.add('trips');
    if (user.can('workers', 'view')) keys.add('workers');
    if (user.can('emergency', 'view')) keys.add('alerts');
    if (user.can('reports', 'view')) keys.add('reports');
    if (user.can('reports', 'export')) keys.add('report_pdf');
    if (user.role == 'jsc_coordinator' && user.can('dumpsite', 'view')) {
      keys.add('dumpsites');
    }
    if (liveOperationsMapEnabled && user.can('operations', 'view')) {
      keys.add('live_map');
    }

    return keys;
  }
}
