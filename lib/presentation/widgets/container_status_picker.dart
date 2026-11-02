import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/services/auth_service.dart';

import '../../core/services/container_service.dart';
import 'app_design.dart';

const containerStatusLabels = <String, String>{
  'empty': 'فارغة',
  'partial': 'نصف ممتلئة',
  'full': 'ممتلئة',
};

class ContainerStatusPicker extends StatelessWidget {
  final String? value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  const ContainerStatusPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const AppText(
        'ما حالة امتلاء الحاوية؟',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in containerStatusLabels.entries)
            ChoiceChip(
              label: AppText(entry.value),
              avatar: Icon(
                Icons.circle,
                size: 14,
                color: entry.key == 'full'
                    ? Colors.red
                    : entry.key == 'partial'
                    ? Colors.orange
                    : Colors.grey,
              ),
              selected: value == entry.key,
              showCheckmark: true,
              onSelected: enabled ? (_) => onChanged(entry.key) : null,
            ),
        ],
      ),
      if (value == null)
        const AppText('اختر الحالة قبل الحفظ.', style: TextStyle(fontSize: 12)),
    ],
  );
}

class ContainerUpdateDetails extends StatelessWidget {
  final ContainerItem item;
  const ContainerUpdateDetails({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    final at = DateTime.tryParse(item.updatedAt)?.toLocal();
    final current = context.watch<AuthService>().currentUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(
            'آخر حالة مسجلة: ${containerStatusLabels[item.status] ?? 'غير محددة'}',
            style: const TextStyle(fontSize: 12),
          ),
          if (current?.id == item.updatedBy) AppText('سجّل الحالة: ${current!.name}', style: const TextStyle(fontSize: 12)),
          if (at != null)
            Text(
              DateFormat('yyyy-MM-dd HH:mm').format(at),
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
    );
  }
}
