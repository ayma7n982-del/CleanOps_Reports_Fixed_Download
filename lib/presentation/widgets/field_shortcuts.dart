import 'package:flutter/material.dart';

import '../../core/models/core_models.dart';
import '../../core/services/feature_route_policy.dart';
import '../feature_navigation.dart';
import '../screens/enterprise_operations_hub.dart';
import '../screens/global_search.dart';
import '../screens/notifications_screen.dart';
import 'app_design.dart';
import 'eco_shortcuts.dart';

/// Shared by the dashboard, focus mode and the field workspace. Each task
/// uses the same role-aware destination, including read-only record viewers.
class FieldTaskShortcuts extends StatelessWidget {
  final AppUser user;
  const FieldTaskShortcuts({super.key, required this.user});

  static const features = [
    'attendance',
    'leave',
    'trips',
    'streets',
    'containers',
    'emergency',
  ];

  static String label(AppUser user, String feature) => feature == 'containers'
      ? 'حاويات مجموعتي'
      : FeatureRoutePolicy.label(user, feature);

  static IconData icon(String feature) => switch (feature) {
    'attendance' => Icons.fact_check_outlined,
    'leave' => Icons.event_available_outlined,
    'trips' => Icons.local_shipping_outlined,
    'streets' => Icons.camera_alt_outlined,
    'containers' => Icons.delete_outline,
    'emergency' => Icons.warning_amber_rounded,
    _ => Icons.dashboard_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final available = features
        .where((feature) => FeatureRoutePolicy.resolve(user, feature) != null)
        .toList();
    if (available.isEmpty) return const SizedBox.shrink();
    return AiSectionCard(
      title: 'مهامك الميدانية',
      feature: 'operations',
      child: EcoShortcutGrid(
        cards: [
          for (final feature in available)
            EcoShortcutCard(
              key: ValueKey('field-task-$feature'),
              feature: feature,
              icon: icon(feature),
              title: label(user, feature),
              subtitle: feature == 'emergency' ? 'البلاغات حسب صلاحياتك' : '',
              accent: feature == 'emergency' ? Colors.red.shade700 : null,
              onTap: () => openAppFeature(context, feature),
            ),
        ],
      ),
    );
  }
}

/// Tools remain visible in focus mode; none of these tiles is a placeholder.
class FieldSupportShortcuts extends StatelessWidget {
  final AppUser user;
  const FieldSupportShortcuts({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    Widget tool(
      String feature,
      String title,
      IconData icon,
      VoidCallback tap,
    ) => EcoShortcutCard(
      key: ValueKey('field-tool-$feature'),
      feature: feature,
      icon: icon,
      title: title,
      subtitle: '',
      onTap: tap,
    );
    void push(Widget page) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    final cards = <Widget>[
      if (user.can('messages', 'view'))
        tool(
          'messages',
          'الرسائل',
          Icons.forum_outlined,
          () => openAppFeature(context, 'messages'),
        ),
      if (user.can('notifications', 'view'))
        tool(
          'notifications',
          'الإشعارات',
          Icons.notifications_none_rounded,
          () => push(const NotificationsPage()),
        ),
      if (user.can('operations', 'view') || user.can('reports', 'view'))
        tool(
          'search',
          'البحث في النظام',
          Icons.search_rounded,
          () => push(const GlobalSearchPage()),
        ),
      if (user.can('reports', 'view'))
        tool(
          'reports',
          'التقارير',
          Icons.assessment_outlined,
          () => openAppFeature(context, 'reports'),
        ),
      if (user.can('sync', 'view'))
        tool(
          'sync',
          'المزامنة',
          Icons.sync_rounded,
          () => push(const SyncCenterPage()),
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return AiSectionCard(
      title: 'التواصل والمتابعة',
      feature: 'messages',
      child: EcoShortcutGrid(cards: cards),
    );
  }
}
