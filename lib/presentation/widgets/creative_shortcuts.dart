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
      // Two balanced tiles even on a small Android screen. Drop to one
      // column only when text would genuinely become unreadable.
      final idealColumns = available >= 980 ? 4 : available >= 640 ? 3 : available < 260 ? 1 : 2;
      final columns = maxColumns == null
          ? idealColumns
          : (idealColumns < maxColumns! ? idealColumns : maxColumns!);
      final scale = (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0.0, 26.0);
      // The old 171px tile left a very large empty gap below its icon.
      // Compact cards retain both title and subtitle without dead space.
      final height = (columns == 1 ? 105.0 : 140.0) + scale * 2.5;
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
    final radius = BorderRadius.circular(20);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      label: item.title,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              colors: [Colors.white, tint],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            border: Border.all(color: accent.withOpacity(.19)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x100A715D),
                blurRadius: 11,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: InkWell(
            onTap: item.onTap,
            borderRadius: radius,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontal = constraints.maxWidth >= 265 &&
                    constraints.maxHeight <= 135;
                final iconSize = horizontal ? 48.0 : 49.0;
                final art = EcoPictorialIcon(
                  feature: item.feature,
                  icon: _icon(item.feature),
                  size: iconSize,
                );
                final label = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: cleanOpsText,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        height: 1.24,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF54736C),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1.23,
                      ),
                    ),
                  ],
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11, vertical: 9,
                  ),
                  child: horizontal
                      ? Row(children: [
                          art,
                          const SizedBox(width: 11),
                          Expanded(child: label),
                          Icon(
                            isRtl
                                ? Icons.chevron_left_rounded
                                : Icons.chevron_right_rounded,
                            color: accent, size: 19,
                          ),
                        ])
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                art,
                                const Spacer(),
                                Icon(
                                  isRtl
                                      ? Icons.arrow_back_rounded
                                      : Icons.arrow_forward_rounded,
                                  color: accent,
                                  size: 19,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Align(
                                alignment: AlignmentDirectional.topStart,
                                child: label,
                              ),
                            ),
                          ],
                        ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
