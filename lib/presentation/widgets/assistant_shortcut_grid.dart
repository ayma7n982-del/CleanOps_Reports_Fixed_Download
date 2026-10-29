import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import 'app_design.dart';

/// Consistent, tap-accessible assistant shortcuts. The grid intentionally gives
/// every tile a fixed, responsive area instead of allowing Wrap children to
/// expand into full-width rows on compact Android devices.
class AssistantShortcutAction {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const AssistantShortcutAction({
    required this.title,
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

    final accent = suggestions
        ? const Color(0xFF087F6B)
        : const Color(0xFF147A88);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 3, end: 3, bottom: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withOpacity(.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(sectionIcon, size: 20, color: accent),
              ),
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
                        color: cleanOpsText,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: cleanOpsMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
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
            final columns = constraints.maxWidth < 300 ? 1 : 2;
            final textScale = MediaQuery.textScalerOf(context).scale(14);
            final tileHeight = 103.0 + (textScale - 14).clamp(0.0, 20.0) * 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: actions.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: tileHeight,
              ),
              itemBuilder: (context, index) {
                final action = actions[index];
                return _AssistantShortcutCard(
                  action: action,
                  accent: accent,
                  suggestions: suggestions,
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _AssistantShortcutCard extends StatelessWidget {
  final AssistantShortcutAction action;
  final Color accent;
  final bool suggestions;

  const _AssistantShortcutCard({
    required this.action,
    required this.accent,
    required this.suggestions,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(19);
    return Semantics(
      button: true,
      label: action.title,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: suggestions
                  ? const [Color(0xFFFFFFFF), Color(0xFFF0F9F4)]
                  : const [Color(0xFFFFFFFF), Color(0xFFEFF8FA)],
            ),
            border: Border.all(
              color: accent.withOpacity(.21),
              width: 1.1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0E073C35),
                offset: Offset(0, 5),
                blurRadius: 12,
              ),
            ],
          ),
          child: InkWell(
            onTap: action.onTap,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        height: 37,
                        width: 37,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [accent, Color.lerp(accent, Colors.white, .18)!],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          action.icon,
                          size: 21,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_outward_rounded,
                        size: 16,
                        color: accent.withOpacity(.70),
                      ),
                    ],
                  ),
                  Text(
                    action.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                    style: const TextStyle(
                      color: cleanOpsText,
                      fontSize: 13,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
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
