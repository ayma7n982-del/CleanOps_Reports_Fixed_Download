import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import 'app_design.dart';
import 'eco_shortcuts.dart';

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
          EcoShortcutGrid(
            cards: [
              for (final action in actions)
                EcoShortcutCard(
                  title: action.title,
                  subtitle: action.description,
                  feature: _featureFor(action.icon),
                  icon: action.icon,
                  onTap: action.onTap,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Map the existing icons to the same feature colors as other app screens.
String _featureFor(IconData icon) {
  if (icon == Icons.analytics_rounded || icon == Icons.insights_rounded ||
      icon == Icons.description_rounded) return 'reports';
  if (icon == Icons.warning_amber_rounded ||
      icon == Icons.notification_important_rounded) return 'emergency';
  if (icon == Icons.delete_sweep_rounded || icon == Icons.location_on_rounded) {
    return 'dumpsite';
  }
  if (icon == Icons.local_shipping_rounded || icon == Icons.route_rounded) {
    return 'trips';
  }
  if (icon == Icons.groups_rounded) return 'workers';
  if (icon == Icons.forum_rounded) return 'messages';
  if (icon == Icons.picture_as_pdf_rounded) return 'reports';
  if (icon == Icons.map_rounded) return 'map';
  return 'ai';
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
