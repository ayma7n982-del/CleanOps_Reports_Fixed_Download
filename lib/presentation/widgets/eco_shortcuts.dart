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
    final scale = MediaQuery.textScalerOf(context);
    final headline = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.start,
      style: const TextStyle(
        fontSize: 13.2,
        color: cleanOpsText,
        fontWeight: FontWeight.w900,
        height: 1.18,
      ),
    );
    final supporting = subtitle.isEmpty
        ? const SizedBox.shrink()
        : Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.start,
            style: const TextStyle(
              fontSize: 10.4,
              height: 1.22,
              color: Color(0xFF52766E),
              fontWeight: FontWeight.w600,
            ),
          );
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
              BoxShadow(
                color: Color(0x100F8D74),
                blurRadius: 11,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontal = constraints.maxWidth >= 270;
                final art = EcoPictorialIcon(
                  feature: feature,
                  icon: icon,
                  size: horizontal ? 48 : 48,
                );
                final action = Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : rtl
                          ? Icons.arrow_back_rounded
                          : Icons.arrow_forward_rounded,
                  size: 17,
                  color: color.withOpacity(.86),
                );
                final label = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    headline,
                    if (subtitle.isNotEmpty) const SizedBox(height: 3),
                    supporting,
                  ],
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                  child: horizontal
                      ? Row(
                          children: [
                            art,
                            const SizedBox(width: 11),
                            Expanded(child: label),
                            const SizedBox(width: 3),
                            action,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                art,
                                const Spacer(),
                                action,
                              ],
                            ),
                            const SizedBox(height: 7),
                            // Icon and heading belong to the SAME content
                            // group; no Spacer / MainAxisAlignment.spaceBetween.
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
        final tileHeight = (columns == 1 ? 83.0 : 125.0) + scaleDelta * 2.9;
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
