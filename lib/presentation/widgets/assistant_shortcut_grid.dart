import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import 'app_design.dart';

/// All permissions and navigation callbacks are supplied by the existing
/// screen. These widgets are presentation-only and never query the backend.
class AssistantShortcutAction {
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  const AssistantShortcutAction({
    required this.title,
    this.description = '',
    required this.icon,
    required this.onTap,
  });
}

class AssistantShortcutGrid extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData sectionIcon;
  final List<AssistantShortcutAction> actions;
  final bool suggestions;

  const AssistantShortcutGrid({
    super.key,
    required this.title,
    required this.subtitle,
    required this.sectionIcon,
    required this.actions,
    this.suggestions = false,
  });

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    final accent = suggestions ? const Color(0xFF07846C) : const Color(0xFF137F8A);

    return Container(
      padding: const EdgeInsets.fromLTRB(11, 15, 11, 13),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.86),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: const Color(0xFFE2F2EC)),
        boxShadow: const [
          BoxShadow(color: Color(0x0E2F9C84), blurRadius: 19, offset: Offset(0, 7)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(5, 0, 5, 13),
            child: Row(
              children: [
                Icon(sectionIcon, color: accent, size: 25),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900,
                          color: Color(0xFF113D39),
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10, height: 1.3,
                          color: Color(0xFF66817C),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 284 ? 1 : 2;
              final effectiveSize = MediaQuery.textScalerOf(context).scale(14);
              final extra = (effectiveSize - 14).clamp(0.0, 28.0) * 2.2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: actions.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: (columns == 1 ? 137.0 : 153.0) + extra,
                ),
                itemBuilder: (context, index) {
                  return _AssistantShortcutCard(
                    action: actions[index],
                    palette: _ShortcutPalette.forIndex(index, suggestions: suggestions),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ShortcutPalette {
  final Color tint;
  final Color accent;
  final Color halo;
  const _ShortcutPalette(this.tint, this.accent, this.halo);

  static _ShortcutPalette forIndex(int i, {bool suggestions = false}) {
    const options = <_ShortcutPalette>[
      _ShortcutPalette(Color(0xFFE9F9F1), Color(0xFF0C956E), Color(0xFFBAF1D5)),
      _ShortcutPalette(Color(0xFFFFF0ED), Color(0xFFE06959), Color(0xFFFFCECA)),
      _ShortcutPalette(Color(0xFFE7F7EF), Color(0xFF159B79), Color(0xFFB3EACF)),
      _ShortcutPalette(Color(0xFFE5F8F8), Color(0xFF0A9DA6), Color(0xFFB9F0ED)),
      _ShortcutPalette(Color(0xFFEAF5FF), Color(0xFF2985B9), Color(0xFFCEE9FD)),
      _ShortcutPalette(Color(0xFFEDF6F8), Color(0xFF267B87), Color(0xFFC2E7EC)),
      _ShortcutPalette(Color(0xFFFFF6E9), Color(0xFFC28A2A), Color(0xFFFFE3AB)),
      _ShortcutPalette(Color(0xFFF1EFFF), Color(0xFF7B60BD), Color(0xFFD8CDFF)),
    ];
    return options[(suggestions ? i : i + 3) % options.length];
  }
}

class _AssistantShortcutCard extends StatelessWidget {
  final AssistantShortcutAction action;
  final _ShortcutPalette palette;

  const _AssistantShortcutCard({required this.action, required this.palette});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    return Semantics(
      button: true,
      label: action.title,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              colors: [palette.tint, Color.lerp(palette.tint, Colors.white, .48)!],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            border: Border.all(color: palette.accent.withOpacity(.10)),
          ),
          child: InkWell(
            onTap: action.onTap,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 69,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _AssistantPictorialIcon(icon: action.icon, palette: palette),
                        Container(
                          width: 29,
                          height: 29,
                          decoration: const BoxDecoration(
                            color: Color(0xEFFFFFFF),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 14, color: palette.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    action.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: cleanOpsText,
                      fontSize: 13.2,
                      height: 1.25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (action.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Flexible(
                      child: Text(
                        action.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF587670),
                          fontSize: 9.5,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Layered gradient art uses standard Material icons, not remote pictures,
/// image files, or extra runtime dependencies.
class _AssistantPictorialIcon extends StatelessWidget {
  final IconData icon;
  final _ShortcutPalette palette;
  const _AssistantPictorialIcon({required this.icon, required this.palette});

  IconData get smallSymbol {
    if (icon == Icons.warning_amber_rounded ||
        icon == Icons.notification_important_rounded) {
      return Icons.priority_high_rounded;
    }
    if (icon == Icons.delete_sweep_rounded ||
        icon == Icons.location_on_rounded) {
      return Icons.recycling_rounded;
    }
    if (icon == Icons.local_shipping_rounded ||
        icon == Icons.route_rounded) {
      return Icons.location_on_rounded;
    }
    if (icon == Icons.groups_rounded) return Icons.check_circle_rounded;
    if (icon == Icons.description_rounded ||
        icon == Icons.picture_as_pdf_rounded) {
      return Icons.pie_chart_rounded;
    }
    return Icons.auto_awesome_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 66,
      width: 76,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 5,
            right: 5,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: palette.halo.withOpacity(.70),
                borderRadius: BorderRadius.circular(21),
              ),
            ),
          ),
          Positioned(
            top: 1,
            right: 10,
            child: Transform.rotate(
              angle: -.08,
              child: Container(
                width: 53,
                height: 55,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color.lerp(palette.accent, Colors.white, .34)!, palette.accent],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: palette.accent.withOpacity(.23),
                      blurRadius: 11,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(icon, size: 31, color: Colors.white),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 2,
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(11),
                boxShadow: const [
                  BoxShadow(color: Color(0x16073C35), blurRadius: 5),
                ],
              ),
              child: Icon(smallSymbol, color: palette.accent, size: 17),
            ),
          ),
        ],
      ),
    );
  }
}

class AssistantFeaturedPdfShortcut extends StatelessWidget {
  final AssistantShortcutAction action;

  const AssistantFeaturedPdfShortcut({super.key, required this.action});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: action.title,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            gradient: const LinearGradient(
              colors: [Color(0xFFF5F1FF), Color(0xFFECEAFF), Color(0xFFF8F7FF)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            border: Border.all(color: const Color(0xFFDCD4FA)),
          ),
          child: InkWell(
            onTap: action.onTap,
            borderRadius: BorderRadius.circular(21),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              child: Row(
                children: [
                  Container(
                    height: 62,
                    width: 65,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5DEFF),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: Color(0xFF8B64C8),
                      size: 40,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          action.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF39315A),
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          action.description.isEmpty
                              ? 'إنشاء تقرير PDF مخصص'
                              : action.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF746994), fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const CircleAvatar(
                    radius: 17,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 15,
                      color: Color(0xFF8765BD),
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
