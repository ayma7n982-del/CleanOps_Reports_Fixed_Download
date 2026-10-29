import 'package:flutter/material.dart';
import 'eco_shortcuts.dart';

/// Existing role-gated navigation and callbacks remain owned by each page.
class CreativeShortcut {
  final String title;
  final String subtitle;
  final String feature;
  final VoidCallback onTap;
  final Color? accent;

  const CreativeShortcut({
    required this.title,
    required this.subtitle,
    required this.feature,
    required this.onTap,
    this.accent,
  });
}

/// Same approved cards as the assistant, reports and workspace shortcuts.
class CreativeShortcutGrid extends StatelessWidget {
  final List<CreativeShortcut> items;
  final int? maxColumns;
  final bool emphasize;

  const CreativeShortcutGrid({
    super.key,
    required this.items,
    this.maxColumns,
    this.emphasize = false,
  });

  static IconData iconFor(String feature) => switch (feature) {
    'ai' => Icons.auto_awesome_rounded,
    'dashboard' => Icons.space_dashboard_rounded,
    'workers' || 'users' => Icons.groups_rounded,
    'attendance' => Icons.fact_check_rounded,
    'trips' => Icons.local_shipping_rounded,
    'streets' => Icons.route_rounded,
    'emergency' => Icons.notification_important_rounded,
    'notifications' => Icons.notifications_active_rounded,
    'reports' => Icons.insert_chart_outlined_rounded,
    'excel' => Icons.table_chart_rounded,
    'permissions' => Icons.verified_user_rounded,
    'settings' => Icons.tune_rounded,
    'sync' => Icons.sync_rounded,
    'critical_areas' => Icons.location_searching_rounded,
    'map' => Icons.map_rounded,
    'activity' => Icons.timeline_rounded,
    'cycle' => Icons.event_repeat_rounded,
    'dumpsite' => Icons.delete_sweep_rounded,
    'messages' => Icons.forum_rounded,
    'containers' => Icons.delete_outline_rounded,
    _ => Icons.eco_rounded,
  };

  @override
  Widget build(BuildContext context) => EcoShortcutGrid(
    maxColumns: maxColumns,
    cards: [
      for (final item in items)
        EcoShortcutCard(
          title: item.title,
          subtitle: item.subtitle,
          feature: item.feature,
          icon: iconFor(item.feature),
          accent: item.accent,
          onTap: item.onTap,
        ),
    ],
  );
}
