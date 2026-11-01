import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/data_service.dart';
import '../../core/services/operational_insights.dart';
import '../widgets/app_design.dart';
import '../widgets/app_navigation_bar.dart';

/// Read-only task records from the existing synchronized operation cache.
class ScopedOperationRecordsScreen extends StatelessWidget {
  final String feature, entity, title;
  const ScopedOperationRecordsScreen({super.key, required this.feature,
    required this.entity, required this.title});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final data = context.watch<DataService>();
    final records = user == null || !user.can(feature, 'view')
        ? <Map<String, dynamic>>[]
        : data.operations.where((record) => record['_entity'] == entity &&
            OperationalInsights.visibleToUser(record, role: user.role,
              userId: user.id, scope: user.scope, groupId: user.groupId)).toList();
    records.sort((a, b) => '${b['createdAt'] ?? ''}'.compareTo('${a['createdAt'] ?? ''}'));
    return Scaffold(
      appBar: AppBar(title: AppText(title), bottom: const AppNavigationBar()),
      body: Column(children: [
        if (!data.online)
          const Padding(padding: EdgeInsets.all(12), child: AppText(
              'تُعرض السجلات المحفوظة على الجهاز حتى عودة الاتصال.')),
        Expanded(child: records.isEmpty
          ? const Center(child: AppText('لا توجد سجلات متاحة ضمن نطاقك.'))
          : ListView.builder(
              padding: const EdgeInsets.all(14), itemCount: records.length,
              itemBuilder: (context, index) {
                final record = records[index];
                final label = '${record['street'] ?? record['locationName'] ?? record['groupName'] ?? title}';
                return Card(child: ListTile(
                  title: AppText(label),
                  subtitle: AppText('${record['createdAt'] ?? ''}'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
                    title: AppText(label),
                    content: SingleChildScrollView(child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final field in const {
                          'street': 'الشارع', 'phase': 'مرحلة التوثيق',
                          'caption': 'وصف الصورة', 'description': 'الوصف',
                          'issue': 'المشكلة', 'quantity': 'الكمية',
                          'estimatedQuantity': 'الكمية التقديرية (طن)',
                          'landfill': 'المكب', 'groupName': 'المجموعة',
                          'municipalityName': 'البلدية', 'createdAt': 'التاريخ',
                        }.entries)
                          if (record[field.key] != null && '${record[field.key]}'.isNotEmpty)
                            Padding(padding: const EdgeInsets.only(bottom: 8),
                              child: AppText('${field.value}: ${record[field.key]}')),
                      ],
                    )),
                    actions: [TextButton(onPressed: () => Navigator.pop(dialogContext),
                        child: const AppText('إغلاق'))],
                  )),
                ));
              },
            )),
      ]),
    );
  }
}
