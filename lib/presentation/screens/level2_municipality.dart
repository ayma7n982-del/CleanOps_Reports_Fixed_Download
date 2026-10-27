import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/data_service.dart';
import '../../core/services/container_service.dart';
import '../../core/services/messaging_service.dart';
import 'reports_center.dart';
import 'operations_management.dart';
import '../widgets/app_design.dart';
import '../widgets/creative_shortcuts.dart';
import '../widgets/operations_overview.dart';
import '../widgets/smart_excel_import.dart';
import 'container_management.dart';
import 'messages_center.dart';
import 'global_search.dart';

class Level2MunicipalityScreen extends StatefulWidget {
  const Level2MunicipalityScreen({super.key});
  @override
  State<Level2MunicipalityScreen> createState() => _Level2MunicipalityScreenState();
}

class _Level2MunicipalityScreenState extends State<Level2MunicipalityScreen> {
  int tab = 0;
  List<Map<String, String>> rows = [];
  List<Map<String, dynamic>> stagnantGroups = [];
  bool loadingStagnation = false;

  @override
  void initState() {
    super.initState();
    _loadStagnation();
  }

  Future<void> _saveImportedRows(List<Map<String, String>> importedRows) async {
    final user = context.read<AuthService>().currentUser;
    final data = context.read<DataService>();
    if (user == null) return;
    for (final row in importedRows) {
      await data.enqueue('worker', 'upsert', {
        'id': row['id'],
        'name': row['name'],
        'job': row['job'],
        'phone': row['phone'],
        'municipality': row['municipality'],
        'group': row['group'],
        'groupNumber': row['group'],
        'municipalityCoordinatorId': row['municipalityCoordinatorId']?.isEmpty == true ? user.id : row['municipalityCoordinatorId'],
        'importedBy': user.id,
        'createdAt': DateTime.now().toIso8601String(),
        'isDeleted': false,
      });
    }
    if (importedRows.isNotEmpty) {
      await data.writeAudit(
        actorId: user.id,
        operation: 'IMPORT_WORKERS_SMART',
        targetId: DateTime.now().millisecondsSinceEpoch.toString(),
        after: {'count': importedRows.length, 'municipality': importedRows.first['municipality'], 'group': importedRows.first['group']},
      );
    }
    if (mounted) setState(() => rows = importedRows);
  }

  Future<void> _loadStagnation() async {
    if (!mounted) return;
    setState(() => loadingStagnation = true);
    final latest = <String, DateTime>{};
    try {
      final data = context.read<DataService>();
      final user = context.read<AuthService>().currentUser;
      if (user == null || user.role != 'municipality_coordinator') return;
      await data.refreshOperations();
      // Only consider trips linked to groups assigned to this municipality.
      final ownGroups = <String>{};
      for (final item in data.operations.where((e) => e['_entity'] == 'group' && e['isDeleted'] != true)) {
        if ('${item['municipalityCoordinatorId'] ?? ''}' != user.id) continue;
        for (final key in ['id', 'number', 'groupId', 'name', 'groupName']) {
          final value = '${item[key] ?? ''}'.trim();
          if (value.isNotEmpty) ownGroups.add(value);
        }
      }
      for (final m in data.operations.where((e) => '${e['_entity'] ?? ''}' == 'trip')) {
        final coordinatorId = '${m['municipalityCoordinatorId'] ?? ''}'.trim();
        final groupId = '${m['groupId'] ?? ''}'.trim();
        final groupName = '${m['groupName'] ?? ''}'.trim();
        if (coordinatorId != user.id && !ownGroups.contains(groupId) && !ownGroups.contains(groupName)) continue;
        if (m['isDeleted'] == true) continue;
        final group = '${m['groupName'] ?? m['groupId'] ?? ''}'.trim();
        final created = DateTime.tryParse('${m['createdAt'] ?? ''}');
        if (group.isEmpty || created == null) continue;
        if (latest[group] == null || created.isAfter(latest[group]!)) latest[group] = created;
      }
    } catch (_) {}
    final now = DateTime.now();
    final computed = latest.entries
        .map((e) => {'group': e.key, 'minutes': now.difference(e.value).inMinutes})
        .where((e) => (e['minutes'] as int) >= 90)
        .toList()
      ..sort((a, b) => (b['minutes'] as int).compareTo(a['minutes'] as int));
    if (mounted) {
      setState(() {
        stagnantGroups = computed;
        loadingStagnation = false;
      });
    }
  }

  Future<void> _redirect() async {
    final u = context.read<AuthService>().currentUser;
    if (u == null || u.role != 'municipality_coordinator' || !u.can('workers', 'edit')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('لا تملك صلاحية إعادة التوجيه.')));
      return;
    }
    final data = context.read<DataService>();
    await data.refreshOperations();
    if (!mounted) return;
    // Only allow existing, municipality-owned records. Never fabricate a cart or group.
    final records = data.operations.where((x) => x['isDeleted'] != true &&
        '${x['municipalityCoordinatorId'] ?? ''}' == u.id).toList();
    final groups = records.where((x) => x['_entity'] == 'group').toList();
    final carts = records.where((x) =>
        (x['_entity'] == 'cart' || x['_entity'] == 'equipment' || x['_entity'] == 'heavy_machinery') &&
        ['${x['type'] ?? ''}', '${x['category'] ?? ''}', '${x['machine'] ?? ''}', '${x['name'] ?? ''}']
            .any((value) => value.contains('كارة') || value.toLowerCase().contains('cart')))
        .map((x) => {...x, '_cartCollection': 'operations'}).toList();
    if (data.online) {
      try {
        final equipment = await FirebaseFirestore.instance.collection('equipment').limit(1000).get();
        for (final doc in equipment.docs) {
          final x = doc.data();
          if (x['isDeleted'] == true || '${x['municipalityCoordinatorId'] ?? ''}' != u.id) continue;
          if (!['${x['type'] ?? ''}', '${x['category'] ?? ''}', '${x['name'] ?? ''}']
              .any((v) => v.contains('كارة') || v.toLowerCase().contains('cart'))) continue;
          carts.add({...x, 'id': doc.id, '_cartCollection': 'equipment', '_entity': 'equipment'});
        }
      } catch (e) {
        debugPrint('Equipment cart lookup unavailable; using offline operations cache: $e');
      }
    }
    if (!mounted) return;
    String? fromId, toId, cartId;
    String recordId(Map<String, dynamic> x) => '${x['id'] ?? ''}';
    String recordName(Map<String, dynamic> x) =>
        '${x['name'] ?? x['groupName'] ?? x['number'] ?? x['id'] ?? ''}';
    if (groups.length < 2 || carts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: AppText('لا توجد مجموعتان وكارة مسجلة ضمن بيانات بلديتك. تحقق من السجلات والمزامنة.')));
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) {
        final availableDestinations = groups.where((g) => recordId(g) != fromId).toList();
        return AlertDialog(
          title: const AppText('إعادة توجيه كارة'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: cartId, isExpanded: true,
              decoration: const InputDecoration(labelText: 'الكارة'),
              items: carts.map((c) => DropdownMenuItem(value: recordId(c),
                child: Text(recordName(c), overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setDialogState(() => cartId = v),
            ),
            DropdownButtonFormField<String>(
              value: fromId, isExpanded: true,
              decoration: const InputDecoration(labelText: 'من المجموعة'),
              items: groups.map((g) => DropdownMenuItem(value: recordId(g),
                child: Text(recordName(g), overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setDialogState(() {
                fromId = v;
                if (toId == v) toId = null;
              }),
            ),
            DropdownButtonFormField<String>(
              value: toId, isExpanded: true,
              decoration: const InputDecoration(labelText: 'إلى المجموعة'),
              items: availableDestinations.map((g) => DropdownMenuItem(value: recordId(g),
                child: Text(recordName(g), overflow: TextOverflow.ellipsis))).toList(),
              onChanged: fromId == null ? null : (v) => setDialogState(() => toId = v),
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const AppText('إلغاء')),
            FilledButton(
              onPressed: cartId != null && fromId != null && toId != null && fromId != toId
                  ? () => Navigator.pop(dialogContext, true) : null,
              child: const AppText('تسجيل إعادة التوجيه'),
            ),
          ],
        );
      }),
    );
    if (approved != true || !mounted) return;
    final current = context.read<AuthService>().currentUser;
    if (current == null || current.id != u.id || !current.can('workers', 'edit')) return;
    // Validate selections again before enqueuing an offline-first operation.
    if (!carts.any((c) => recordId(c) == cartId) ||
        !groups.any((g) => recordId(g) == fromId) ||
        !groups.any((g) => recordId(g) == toId) || fromId == toId) return;
    try {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final payload = <String, dynamic>{
        'id': id, 'municipalityCoordinatorId': u.id,
        'fromGroupId': fromId, 'toGroupId': toId, 'cartId': cartId,
        'cartEntity': carts.firstWhere((c) => recordId(c) == cartId)['_entity'],
        'cartCollection': carts.firstWhere((c) => recordId(c) == cartId)['_cartCollection'],
        'fromGroup': recordName(groups.firstWhere((g) => recordId(g) == fromId)),
        'toGroup': recordName(groups.firstWhere((g) => recordId(g) == toId)),
        'cart': recordName(carts.firstWhere((c) => recordId(c) == cartId)),
        'requestedBy': u.id, 'createdAt': DateTime.now().toIso8601String(),
      };
      await data.enqueue('cart_redirect', 'create', payload);
      await data.writeAudit(actorId: u.id, operation: 'REDIRECT_CART', targetId: id, after: payload);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: AppText('تم حفظ إعادة التوجيه محلياً وإدراجها للمزامنة التلقائية.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ إعادة التوجيه: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: context.watch<LocaleController>().isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: const AppText('المستوى 2 — منسق البلدية'),
          actions: [
            IconButton(tooltip: tr('البحث الذكي'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GlobalSearchPage())), icon: const Icon(Icons.search_rounded)),
            Builder(builder: (context) {
              final unread = context.watch<MessagingService>().unreadCount;
              return IconButton(
                tooltip: unread > 0 ? 'الرسائل والإشعارات غير المقروءة: $unread' : 'الرسائل والإشعارات',
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MessagesCenterScreen())),
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text(unread > 99 ? '99+' : '$unread'),
                  child: const Icon(Icons.notifications_outlined),
                ),
              );
            }),
            IconButton(onPressed: _loadStagnation, icon: const Icon(Icons.refresh)),
            IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsCenterScreen())), icon: const Icon(Icons.analytics_outlined)),
            IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OperationsManagementScreen(initialTab: 1))), icon: const Icon(Icons.hub_outlined)),
          ],
          bottom: TabBar(isScrollable: true, onTap: (i) => setState(() => tab = i), tabs: [Tab(text: tr('لوحة القيادة')), Tab(text: tr('الإدارة')), Tab(text: tr('التقارير والرسائل'))]),
        ),
        body: _tabBody(),
      ),
    );
  }

  Future<void> _acknowledgeMunicipalitySos(String id) async {
    final user = context.read<AuthService>().currentUser;
    if (user == null || user.role != 'municipality_coordinator') return;
    try {
      final now = DateTime.now().toIso8601String();
      await FirebaseFirestore.instance.collection('operations').doc(id).update({
        'acknowledged': true,
        'acknowledgedBy': user.id,
        'acknowledgedAt': now,
        'status': 'acknowledged',
        'updatedAt': now,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('تم تأكيد استلام البلاغ.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تأكيد الاستلام: $error')));
    }
  }

  Stream<Set<String>> _assignedLegacySosIds(String userId) =>
      FirebaseFirestore.instance.collection('operations')
          .where('_entity', isEqualTo: 'notification')
          .where('targetUserId', isEqualTo: userId)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .where((doc) => doc.data()['sourceEntity'] == 'emergency')
              .map((doc) => '${doc.data()['sourceId']}').toSet());

  Widget _municipalitySosInbox() {
    final user = context.read<AuthService>().currentUser;
    if (user == null) return const SizedBox.shrink();
    return StreamBuilder<Set<String>>(
      stream: _assignedLegacySosIds(user.id),
      builder: (context, assignments) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('operations')
          .where('_entity', isEqualTo: 'emergency').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const ListTile(title: AppText('تعذر تحميل بلاغات الطوارئ.'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final cases = snapshot.data!.docs.where((doc) {
          final item = doc.data();
          return item['isDeleted'] != true
              && item['acknowledged'] != true
              && item['status'] == 'urgent'
              && (item['municipalityCoordinatorId'] == user.id ||
                  (assignments.data?.contains(doc.id) ?? false));
        }).toList();
        if (cases.isEmpty) return const ListTile(title: AppText('لا توجد بلاغات SOS جديدة موجهة إليك.'));
        return Column(children: cases.take(15).map((doc) => ListTile(
          title: AppText('بلاغ SOS — ${doc.data()['street'] ?? ''}'),
          subtitle: AppText('بانتظار تأكيد الاستلام'),
          trailing: FilledButton(
            onPressed: () => _acknowledgeMunicipalitySos(doc.id),
            child: const AppText('تأكيد الاستلام'),
          ),
        )).toList());
      },
    ));
  }

  Widget _dashboardBody() => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            if (context.watch<AuthService>().currentUser case final currentUser?) AiHero(
              user: currentUser,
              eyebrow: 'LEVEL 2 • MUNICIPAL COMMAND',
              title: 'لوحة تشغيل البلدية',
              subtitle: 'مراقبة الركود، القوى العاملة، الكارات والبيانات الميدانية من مركز واحد.',
            ),
            const SizedBox(height: 10),
            const OperationsOverviewStrip(),
            const SizedBox(height: 12),
            AiSectionCard(title: 'بلاغات SOS العاجلة', feature: 'emergency', child: _municipalitySosInbox()),
            const SizedBox(height: 12),
            Builder(builder: (context) {
              final cs = context.watch<ContainerService>();
              final critical = cs.containers.where((c) => c.status == 'full' || c.issueStatus == 'reported' || c.issueStatus == 'resolving').toList();
              return AiSectionCard(
                title: 'تنبيهات الحاويات',
                subtitle: critical.isEmpty ? 'لا توجد تنبيهات حرجة للحاويات.' : '${critical.length} تنبيه يحتاج متابعة.',
                feature: 'containers',
                child: critical.isEmpty
                    ? const AppText('لا توجد حاويات ممتلئة أو مشكلات مفتوحة.')
                    : Column(children: critical.take(6).map((c) => ListTile(contentPadding: EdgeInsets.zero, leading: Icon(c.status == 'full' ? Icons.warning_amber_rounded : Icons.report_problem_outlined, color: c.status == 'full' ? red : orange), title: AppText(c.locationName), subtitle: AppText(c.status == 'full' ? 'ممتلئة — يلزم التفريغ' : c.issueStatus == 'reported' ? 'مشكلة مسجلة' : 'إجراء تصحيحي قيد المعالجة'))).toList()),
              );
            }),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                const SizedBox(width: 165, child: AiStatTile(title: 'الركود', value: '90+ min', subtitle: 'عتبة التنبيه', feature: 'emergency')),
                SizedBox(width: 165, child: AiStatTile(title: 'السجلات', value: '${rows.length}', subtitle: 'سجلات مستوردة', feature: 'excel')),
                const SizedBox(width: 165, child: AiStatTile(title: 'الدور', value: 'L2', subtitle: 'منسق البلدية', feature: 'permissions')),
              ],
            ),
            const SizedBox(height: 14),
            CardSection2(
              title: 'تنبيهات الركود — أكثر من 90 دقيقة',
              icon: const Icon(Icons.timer_outlined),
              child: loadingStagnation
                  ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                  : stagnantGroups.isEmpty
                      ? const ListTile(title: AppText('لا توجد مجموعة متوقفة لأكثر من 90 دقيقة ضمن البيانات المتاحة.'))
                      : Column(children: stagnantGroups.map((e) => _stagnation('${e['group']}', '${e['minutes']} دقيقة')).toList()),
            ),
          ],
        );

  Widget _tabBody() => switch (tab) {
    0 => _dashboardBody(),
    1 => ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 120), children: [
      CreativeShortcutGrid(items: [
        CreativeShortcut(title: 'المجموعات والعمال', subtitle: 'القوى العاملة والتوزيع', feature: 'workers', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OperationsManagementScreen(initialTab: 0)))),
        CreativeShortcut(title: 'إدخال الحاويات', subtitle: 'الحالة والمشكلات اليومية', feature: 'containers', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContainerManagementScreen()))),
        CreativeShortcut(title: 'المكبات', subtitle: 'السعة والامتلاء والمواقع', feature: 'dumpsite', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OperationsManagementScreen(initialTab: 1)))),
        CreativeShortcut(title: 'التقارير', subtitle: 'تشغيل البلدية ومؤشراتها', feature: 'reports', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsCenterScreen()))),
        CreativeShortcut(title: 'الرسائل والإشعارات', subtitle: 'الوارد والتنبيهات غير المقروءة', feature: 'emergency', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MessagesCenterScreen()))),
      ]),
      const SizedBox(height: 14),
      AiSectionCard(title: 'إدارة العمال', subtitle: 'استيراد كشف العمال بذكاء من Excel أو CSV.', feature: 'workers', child: SmartExcelImportCard(onImport: _saveImportedRows)),
      const SizedBox(height: 12),
      CardSection2(title: 'إعادة توجيه الكارات', icon: const Icon(Icons.swap_horiz), child: Column(children: [
        const ListTile(title: AppText('اختيار الكارة والمجموعتين'), subtitle: AppText('من سجلات البلدية الفعلية، دون بيانات ثابتة')),
        FilledButton.icon(onPressed: _redirect, icon: const Icon(Icons.double_arrow), label: const AppText('تنفيذ إعادة التوجيه')),
      ])),
    ]),
    2 => _reportsBody(),
    _ => _dashboardBody(),
  };

  Widget _reportsBody() => ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 120), children: [
    AiSectionCard(title: 'التقارير والرسائل', subtitle: 'الوصول إلى التقارير التشغيلية ومركز الرسائل.', feature: 'reports', child: Column(children: [
      FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsCenterScreen())), icon: const Icon(Icons.analytics_outlined), label: const AppText('فتح التقارير')),
      const SizedBox(height: 8),
      FilledButton.tonalIcon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MessagesCenterScreen())), icon: const Icon(Icons.forum_outlined), label: const AppText('فتح الرسائل')),
    ])),
  ]);

  Widget _stagnation(String group, String time) => ListTile(
    leading: const Icon(Icons.warning_amber_rounded, color: orange),
    title: AppText(group, style: const TextStyle(fontWeight: FontWeight.bold)),
    subtitle: AppText('لا يوجد نشاط منذ $time'),
    trailing: const Chip(label: AppText('ركود')),
  );
}

class CardSection2 extends StatelessWidget {
  final String title;
  final Widget icon;
  final Widget child;
  const CardSection2({super.key, required this.title, required this.icon, required this.child});
  @override
  Widget build(BuildContext context) => AiSectionCard(title: title, feature: title.contains('Excel') ? 'excel' : title.contains('ركود') ? 'emergency' : 'trips', child: child);
}
