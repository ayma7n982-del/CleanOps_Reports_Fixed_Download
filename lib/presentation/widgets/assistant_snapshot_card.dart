import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/localization.dart';
import 'app_design.dart';

/// Owns the request so typing/rebuilding the parent cannot restart it.
/// A new account/scope must supply a different widget key.
class AssistantSnapshotCard extends StatefulWidget {
  final Future<Map<String, dynamic>> Function() load;
  const AssistantSnapshotCard({super.key, required this.load});

  @override
  State<AssistantSnapshotCard> createState() => _AssistantSnapshotCardState();
}

class _AssistantSnapshotCardState extends State<AssistantSnapshotCard> {
  late Future<Map<String, dynamic>> _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = _load();
  }

  Future<Map<String, dynamic>> _load() =>
      Future<Map<String, dynamic>>.sync(widget.load)
          .timeout(const Duration(seconds: 20));

  @override
  Widget build(BuildContext context) => AiGlassCard(
        padding: const EdgeInsets.all(12),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _snapshot,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Row(children: [
                SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Expanded(child: AppText('جاري تحميل مؤشرات التشغيل...')),
              ]);
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppText(
                    'تعذر تحميل المؤشرات. تحقق من الاتصال ثم أعد المحاولة.',
                    style: TextStyle(color: cleanOpsMuted),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _snapshot = _load()),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const AppText('إعادة المحاولة'),
                  ),
                ],
              );
            }
            final data = snapshot.data!;
            const labels = {
              'workers': 'العمال',
              'groups': 'المجموعات',
              'trips': 'الترحيلات',
              'emergencies': 'الطوارئ',
              'criticalDumpsites': 'المكبات الحرجة',
            };
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppText('مؤشرات التشغيل',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final entry in labels.entries)
                    Chip(label: AppText('${entry.value}: ${data[entry.key] ?? '—'}')),
                ]),
              ],
            );
          },
        ),
      );
}
