import 'package:flutter/material.dart';
import 'app_design.dart';
import '../../core/constants/app_constants.dart';

/// The same role-gated callbacks supplied by each screen are retained.
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

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final available = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width - 32;
      final idealColumns = available >= 980 ? 4 : available >= 640 ? 3 : available < 300 ? 1 : 2;
      final columns = maxColumns == null
          ? idealColumns
          : (idealColumns < maxColumns! ? idealColumns : maxColumns!);
      final scale = (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0.0, 26.0);
      final height = (columns == 1 ? 132.0 : emphasize ? 171.0 : 158.0) + scale * 2.2;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 11,
          mainAxisSpacing: 11,
          mainAxisExtent: height,
        ),
        itemBuilder: (context, i) => _CreativeShortcutCard(
          item: items[i],
          emphasize: emphasize,
        ),
      );
    });
  }
}

class _CreativeShortcutCard extends StatelessWidget {
  final CreativeShortcut item;
  final bool emphasize;
  const _CreativeShortcutCard({required this.item, this.emphasize = false});

  IconData _icon(String f) => switch (f) {
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
  Widget build(BuildContext context) {
    final accent = item.accent ?? EcoPalette.accent(item.feature);
    final tint = EcoPalette.tint(item.feature);
    final narrow = MediaQuery.sizeOf(context).width < 340;
    final borderRadius = BorderRadius.circular(21);
    return Semantics(
      button: true,
      label: item.title,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [tint, Color.lerp(tint, Colors.white, .5)!],
            ),
            borderRadius: borderRadius,
            border: Border.all(color: accent.withOpacity(.19)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x100A715D),
                blurRadius: 15,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: borderRadius,
            onTap: item.onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: narrow ? 9 : 12,
                vertical: emphasize ? 13 : 10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      EcoPictorialIcon(
                        feature: item.feature,
                        icon: _icon(item.feature),
                        size: emphasize ? 61 : 53,
                      ),
                      const Spacer(),
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.white.withOpacity(.88),
                        child: Icon(
                          Directionality.of(context) == TextDirection.rtl
                              ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                          size: 19,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cleanOpsText,
                      fontSize: emphasize ? 14.5 : 13.5,
                      fontWeight: FontWeight.w900,
                      height: 1.21,
                    ),
                  ),
                  Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF5E7D77),
                      fontSize: 10.5,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
