import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import 'app_design.dart';

/// Single approved Eco visual language for every clickable shortcut.
/// This component has no knowledge of roles, routes, Firebase or PDF export:
/// existing callers provide the exact action and permission gate.
class EcoShortcutCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String feature;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final Color? accent;

  const EcoShortcutCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.feature,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? EcoPalette.accent(feature);
    final tint = EcoPalette.tint(feature);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final radius = BorderRadius.circular(19);

    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: selected
                  ? [const Color(0xFFE0F6EE), tint]
                  : [Colors.white, tint],
            ),
            border: Border.all(
              color: selected ? color : color.withOpacity(.18),
              width: selected ? 1.8 : 1,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x100F8D74),
                  blurRadius: 11, offset: Offset(0, 4)),
            ],
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Follow the approved mockup on normal phones: illustrated
                // icon at the right, label beside it, open arrow at the left.
                // Only tiny 320px phones fall back to stacked content.
                final horizontal = constraints.maxWidth >= 155;
                final compact = constraints.maxWidth < 190;
                final art = EcoPictorialIcon(
                  feature: feature,
                  icon: icon,
                  size: horizontal ? (compact ? 45 : 54) : 47,
                );
                final indicator = Container(
                  width: 25,
                  height: 25,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.90),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    selected
                        ? Icons.check_rounded
                        : rtl
                            ? Icons.chevron_left_rounded
                            : Icons.chevron_right_rounded,
                    color: color,
                    size: 18,
                  ),
                );
                final label = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.start,
                      style: TextStyle(
                        fontSize: compact ? 12 : 13.2,
                        color: cleanOpsText,
                        fontWeight: FontWeight.w900,
                        height: 1.19,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: horizontal ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                          fontSize: compact ? 9.2 : 10.4,
                          height: 1.22,
                          color: const Color(0xFF52766E),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                );

                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 7 : 10,
                    vertical: 9,
                  ),
                  child: horizontal
                      ? Row(
                          children: [
                            art,
                            SizedBox(width: compact ? 6 : 10),
                            Expanded(child: label),
                            const SizedBox(width: 3),
                            indicator,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                art,
                                const Spacer(),
                                indicator,
                              ],
                            ),
                            const SizedBox(height: 7),
                            Flexible(child: label),
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

/// Shared responsive geometry across all levels and report types.
/// Responsive text height is accounted for rather than relying on aspectRatio.
class EcoShortcutGrid extends StatelessWidget {
  final List<Widget> cards;
  final int? maxColumns;

  const EcoShortcutGrid({
    super.key,
    required this.cards,
    this.maxColumns,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth.isFinite
            ? box.maxWidth
            : MediaQuery.sizeOf(context).width - 32;
        final desired = width >= 960 ? 4 : width >= 610 ? 3 : width < 270 ? 1 : 2;
        final columns = maxColumns != null && desired > maxColumns!
            ? maxColumns!
            : desired;
        final scaleDelta =
            (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0.0, 36.0);
        final tileHeight = 125.0 + scaleDelta * 2.9;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: tileHeight,
          ),
          itemBuilder: (context, i) => cards[i],
        );
      },
    );
  }
}
