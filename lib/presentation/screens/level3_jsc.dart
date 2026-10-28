import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import '../../core/localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/gaza_municipalities.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/data_service.dart';
import '../../core/services/report_service.dart';
import '../../core/services/container_service.dart';
import 'reports_center.dart';
import 'global_search.dart';
import 'operations_management.dart';
import '../widgets/app_design.dart';
import '../widgets/creative_shortcuts.dart';
import '../widgets/operations_overview.dart';
import 'container_management.dart';
import 'messages_center.dart';

class Level3JscScreen extends StatefulWidget {
  const Level3JscScreen({super.key});
  @override
  State<Level3JscScreen> createState() => _Level3JscState();
}

class _Level3JscState extends State<Level3JscScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int tab = 0;
  double capacity = 0;
  bool loading = true;
  List<Map<String, dynamic>> emergencies = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted && _tabController.index != tab) {
        setState(() => tab = _tabController.index);
      }
    });
    _loadOperationsState();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadOperationsState() async {
    if (!mounted) return;
    setState(() => loading = true);
    try {
      final data = context.read<DataService>();
      if (data.online) await data.refreshOperations();
      var loadedCapacity = capacity;
      try {
        final snapshot = await ReportService(data).load(
          user: context.read<AuthService>().currentUser);
        loadedCapacity = snapshot.landfillCapacity;
      } catch (error) {
        debugPrint('Council capacity unavailable; keeping cached SOS: $error');
      }
      final cases = <Map<String, dynamic>>[];
      for (final m in data.operations.where((e) => '${e['_entity'] ?? ''}' == 'emergency')) {
        if (m['isDeleted'] != true && (m['status'] != 'closed' ||
            _hasPendingSos('${m['id']}'))) cases.add(Map.from(m));
      }
      cases.sort((a, b) => '${b['createdAt'] ?? ''}'.compareTo('${a['createdAt'] ?? ''}'));
      if (mounted) {
        setState(() {
          capacity = loadedCapacity.clamp(0.0, 1.0).toDouble();
          emergencies = cases;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _chooseDispatch() async {
    final user = context.read<AuthService>().currentUser;
    if (user == null || user.role != 'jsc_coordinator' ||
        !user.can('operations', 'create')) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('equipment').limit(300).get(const GetOptions(source: Source.serverAndCache));
      final available = snapshot.docs.where((doc) {
        final item = doc.data();
        final kind = '${item['type'] ?? item['category'] ?? ''}'.toLowerCase();
        final state = '${item['status'] ?? ''}'.toLowerCase();
        return item['isDeleted'] != true &&
            !const ['cart', 'كارة'].contains(kind) &&
            item['dispatchStatus'] != 'dispatched' &&
            !context.read<DataService>().hasPendingEquipmentDispatch(doc.id) &&
            !const ['out_of_service', 'maintenance', 'broken'].contains(state);
      }).toList();
      if (!mounted) return;
      if (available.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: AppText('لا توجد آليات مسجلة يمكن توجيهها.')));
        return;
      }
      String? selectedId = available.first.id;
      String selectedMunicipality = gazaMunicipalities.first.nameAr;
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const AppText('توجيه آلية مسجلة'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الآلية'),
                  items: available.map((doc) {
                    final item = doc.data();
                    final label = '${item['name'] ?? item['equipmentName'] ?? item['type'] ?? doc.id}';
                    return DropdownMenuItem(value: doc.id, child: Text(label,
                        overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (value) => setDialogState(() => selectedId = value),
                ),
                DropdownButtonFormField<String>(
                  initialValue: selectedMunicipality,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'البلدية المستهدفة'),
                  items: gazaMunicipalities.map((m) => DropdownMenuItem(
                    value: m.nameAr, child: Text(m.nameAr,
                      overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (value) => setDialogState(
                    () => selectedMunicipality = value ?? selectedMunicipality),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext),
                  child: const AppText('إلغاء')),
              FilledButton(
                onPressed: () {
                  if (selectedId == null) return;
                  Navigator.pop(dialogContext, {
                    'equipmentId': selectedId!,
                    'municipality': selectedMunicipality,
                  });
                },
                child: const AppText('اعتماد طلب التوجيه'),
              ),
            ],
          ),
        ),
      );
      if (result == null || !mounted) return;
      final equipment = available.firstWhere(
          (doc) => doc.id == result['equipmentId']);
      final record = equipment.data();
      final name = '${record['name'] ?? record['equipmentName'] ?? record['type'] ?? equipment.id}';
      await _dispatch(name, result['municipality']!,
          equipmentId: equipment.id);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحميل الآليات: $error')));
    }
  }

  Future<void> _dispatch(String machine, String municipality,
      {required String equipmentId}) async {
    final u = context.read<AuthService>().currentUser;
    if (u == null || u.role != 'jsc_coordinator' || !u.can('operations', 'create')) return;
    final d = context.read<DataService>();
    if (d.hasPendingEquipmentDispatch(equipmentId)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: AppText('يوجد طلب توجيه أو استعادة سابق بانتظار المزامنة.')));
      return;
    }
    final id = d.uuid.v4();
    await d.enqueue('equipment_dispatch', 'dispatch', {
      'id': id,
      'machine': machine,
      'equipmentId': equipmentId,
      'municipality': municipality,
      'requestedBy': u.id,
      'createdAt': DateTime.now().toIso8601String(),
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: AppText('تم حفظ طلب توجيه الآلية؛ لن يعتمد التخصيص حتى تؤكد Firebase نجاح المزامنة.')));
  }

  Future<void> _chooseEquipmentReturn() async {
    final user = context.read<AuthService>().currentUser;
    if (user == null || user.role != 'jsc_coordinator' ||
        !user.can('operations', 'edit')) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('equipment')
          .where('dispatchStatus', isEqualTo: 'dispatched')
          .limit(300)
          .get(const GetOptions(source: Source.serverAndCache));
      if (!mounted) return;
      final service = context.read<DataService>();
      final assigned = snapshot.docs.where((doc) =>
          doc.data()['isDeleted'] != true &&
          doc.data()['dispatchRequestId'] is String &&
          !service.hasPendingEquipmentDispatch(doc.id)).toList();
      if (assigned.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: AppText('لا توجد آليات موجّهة قابلة للاستعادة الآن.')));
        return;
      }
      String? selectedId = assigned.first.id;
      final noteController = TextEditingController();
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const AppText('إنهاء توجيه الآلية'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الآلية الموجّهة'),
                  items: assigned.map((doc) {
                    final item = doc.data();
                    return DropdownMenuItem(
                      value: doc.id,
                      child: Text(
                        '${item['name'] ?? item['equipmentName'] ?? item['type'] ?? doc.id} — ${item['dispatchMunicipality'] ?? ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) => setDialogState(() => selectedId = value),
                ),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'سبب إنهاء التوجيه وملاحظات العودة',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const AppText('إلغاء')),
              FilledButton(
                onPressed: () {
                  final note = noteController.text.trim();
                  if (selectedId == null || note.isEmpty) return;
                  Navigator.pop(dialogContext, {
                    'equipmentId': selectedId!, 'returnNote': note,
                  });
                },
                child: const AppText('حفظ طلب الاستعادة'),
              ),
            ],
          ),
        ),
      );
      noteController.dispose();
      if (result == null || !mounted) return;
      final equipmentId = result['equipmentId']!;
      final machine = assigned.firstWhere((doc) => doc.id == equipmentId).data();
      if (service.hasPendingEquipmentDispatch(equipmentId)) return;
      await service.enqueue('equipment_return', 'return', {
        'id': service.uuid.v4(),
        'equipmentId': equipmentId,
        'sourceDispatchRequestId': machine['dispatchRequestId'],
        'requestedBy': user.id,
        'returnNote': result['returnNote'],
        'createdAt': DateTime.now().toIso8601String(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: AppText('تم حفظ طلب استعادة الآلية؛ لن تصبح متاحة حتى يؤكد الخادم ذلك.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر استعادة الآلية: $error')));
    }
  }

  Future<void> _sendLandfillWarning() async {
    final u = context.read<AuthService>().currentUser;
    if (u == null) return;
    final d = context.read<DataService>();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await d.enqueue('notification', 'critical', {
      'id': id,
      'targetLayer': 'municipality',
      'title': 'تحذير سعة المكب',
      'body': 'السعة الحالية ${(_capacityPercent * 100).round()}% وتجاوزت حد 85%.',
      'createdAt': DateTime.now().toIso8601String(),
    });
    await d.writeAudit(actorId: u.id, operation: 'LANDFILL_CAPACITY_WARNING', targetId: id, after: {'capacity': _capacityPercent, 'threshold': .85});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('تم تسجيل تحذير سعة المكب.')));
  }

  double get _capacityPercent => capacity.clamp(0.0, 1.0).toDouble();

  Future<void> _acknowledgeEmergency(String id) async {
    final user = context.read<AuthService>().currentUser;
    if (user == null || user.role != 'jsc_coordinator') return;
    try {
      final now = DateTime.now().toIso8601String();
      await context.read<DataService>().enqueue('emergency', 'sos_acknowledge', {
        'id': id,
        'acknowledged': true,
        'acknowledgedBy': user.id,
        'acknowledgedAt': now,
        'status': 'acknowledged',
        'updatedAt': now,
      });
      await _loadOperationsState();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('تم حفظ تأكيد الاستلام للمزامنة التلقائية.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تسجيل تأكيد الاستلام: $error')));
    }
  }

  Future<void> _closeSos(String id) async {
    final user = context.read<AuthService>().currentUser;
    if (user == null || user.role != 'jsc_coordinator') return;
    final record = emergencies.where((e) => '${e['id']}' == id).toList();
    if (record.isEmpty || record.first['acknowledged'] != true ||
        !const ['acknowledged', 'resolved', 'reopened'].contains(record.first['status'])) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: AppText('يجب تأكيد استلام البلاغ قبل إغلاقه.')));
      return;
    }
    final noteController = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const AppText('إغلاق بلاغ SOS'),
        content: TextField(
          controller: noteController,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'سبب الإغلاق والإجراءات المتخذة'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const AppText('إلغاء')),
          FilledButton(onPressed: () {
            final value = noteController.text.trim();
            if (value.isNotEmpty) Navigator.pop(dialogContext, value);
          }, child: const AppText('اعتماد الإغلاق')),
        ],
      ),
    );
    noteController.dispose();
    if (note == null || note.isEmpty || !mounted) return;
    try {
      final now = DateTime.now().toIso8601String();
      await context.read<DataService>().enqueue('emergency', 'sos_close', {
        'id': id,
        'status': 'closed',
        'acknowledged': true,
        'closedBy': user.id,
        'closedAt': now,
        'resolutionNote': note,
        'updatedAt': now,
      });
      await _loadOperationsState();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: AppText('تم حفظ طلب إغلاق SOS؛ سيُزامن تلقائيًا عند الاتصال.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تسجيل إغلاق البلاغ: $error')));
    }
  }

  Future<void> _referEmergency(String id) async {
    final user = context.read<AuthService>().currentUser;
    if (user == null || user.role != 'jsc_coordinator') return;
    try {
      final now = DateTime.now().toIso8601String();
      final data = context.read<DataService>();
      await data.enqueue('emergency', 'sos_refer', {
        'id': id,
        'referredBy': user.id,
        'referredAt': now,
        'referralDestination': 'هندسة المتفجرات',
        'updatedAt': now,
      });
      await _loadOperationsState();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: AppText('تم حفظ إحالة البلاغ في سجل العمليات بانتظار المزامنة؛ لا يعني ذلك استلام جهة خارجية.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ إحالة البلاغ: $error')));
    }
  }

  /// Records a specialist's documented clearance. This is not a technical
  /// confirmation that unexploded ordnance is safe; physical clearance remains
  /// the responsibility of the specialist authority.
  Future<void> _recordSecuredSite(String id) async {
    final user = context.read<AuthService>().currentUser;
    if (user == null || user.role != 'jsc_coordinator') return;
    final reports = emergencies.where((item) => '${item['id']}' == id).toList();
    if (reports.isEmpty || reports.first['acknowledged'] != true ||
        !const ['acknowledged', 'resolved'].contains(reports.first['status']) ||
        reports.first['referralDestination'] != 'هندسة المتفجرات') {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: AppText('لا يمكن تسجيل تأمين الموقع قبل تأكيد الاستلام وتوثيق الإحالة للجهة المختصة.')));
      return;
    }
    final officer = TextEditingController();
    final reference = TextEditingController();
    final note = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const AppText('توثيق إفادة تأمين الموقع'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppText(
                'أدخل بيانات إفادة رسمية صادرة عن جهة مختصة. هذا التسجيل الإداري ليس فحص سلامة للموقع.'),
              TextField(
                controller: officer,
                decoration: const InputDecoration(labelText: 'اسم المختص أو الجهة المصدرة للإفادة'),
              ),
              TextField(
                controller: reference,
                decoration: const InputDecoration(labelText: 'رقم المرجع أو المحضر الرسمي'),
              ),
              TextField(
                controller: note, maxLines: 3,
                decoration: const InputDecoration(labelText: 'ملخص ما أكدتْه الجهة المختصة'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const AppText('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (officer.text.trim().isEmpty ||
                  reference.text.trim().isEmpty || note.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(dialogContext, {
                'eodOfficer': officer.text.trim(),
                'eodReference': reference.text.trim(),
                'securityNote': note.text.trim(),
              });
            },
            child: const AppText('حفظ بيانات الإفادة'),
          ),
        ],
      ),
    );
    officer.dispose();
    reference.dispose();
    note.dispose();
    if (result == null || !mounted) return;
    try {
      final now = DateTime.now().toIso8601String();
      await context.read<DataService>().enqueue('emergency', 'sos_secure', {
        'id': id,
        'status': 'secured',
        'securedBy': user.id,
        'securedAt': now,
        ...result,
        'updatedAt': now,
      });
      await _loadOperationsState();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: AppText('حُفظت إفادة التأمين محليًا؛ ستتحقق قواعد Firebase من انتقال الحالة عند المزامنة.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تسجيل إفادة تأمين الموقع: $error')));
    }
  }

  Future<void> _reopenStreet(String id) async {
    final user = context.read<AuthService>().currentUser;
    if (user == null || user.role != 'jsc_coordinator') return;
    final secured = emergencies.any((e) =>
        '${e['id']}' == id && e['status'] == 'secured' && e['acknowledged'] == true);
    if (!secured) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: AppText('لا يمكن طلب إعادة الفتح قبل تأمين الموقع وتأكيد الاستلام.')));
      return;
    }
    try {
      final now = DateTime.now().toIso8601String();
      await context.read<DataService>().enqueue('emergency', 'sos_reopen', {
        'id': id,
        'status': 'reopened',
        'reopenedBy': user.id,
        'reopenedAt': now,
        'updatedAt': now,
      });
      await _loadOperationsState();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: AppText('تم تسجيل إعادة الفتح للمزامنة؛ لا تُعد الحالة مؤكدة قبل موافقة الخادم.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تسجيل إعادة الفتح: $error')));
    }
  }

  bool _hasPendingSos(String id) {
    for (final item in context.read<DataService>().queue) {
      final uid = context.read<AuthService>().currentUser?.id;
      if (item.entity != 'emergency' ||
          (item.ownerUid != null && item.ownerUid != uid)) continue;
      try {
        final payload = jsonDecode(item.payload);
        if (payload is Map && '${payload['id']}' == id) return true;
      } catch (_) {}
    }
    return false;
  }

  Future<void> _copyEmergencyDetails(Map<String, dynamic> emergency) async {
    final latitude = emergency['latitude'] ?? emergency['lat'] ?? emergency['locationLat'];
    final longitude = emergency['longitude'] ?? emergency['lng'] ?? emergency['locationLng'];
    final location = latitude is num && longitude is num
        ? 'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude'
        : 'إحداثيات GPS غير متوفرة';
    final details = 'بلاغ طوارئ رقم ${emergency['id'] ?? ''}\n'
        'الموقع: ${emergency['street'] ?? 'غير محدد'}\n'
        'الإحداثيات: $latitude، $longitude\n'
        'خريطة الموقع: $location\n'
        'الحالة: ${emergency['status'] ?? 'urgent'}';
    await Clipboard.setData(ClipboardData(text: details));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: AppText('تم نسخ تفاصيل البلاغ والموقع للمشاركة مع الجهة المختصة.')));
  }

  Future<void> _openSosLocation(num latitude, num longitude) async {
    final link = Uri.https('www.google.com', '/maps/search/', {
      'api': '1', 'query': '$latitude,$longitude',
    });
    try {
      if (!await launchUrl(link, mode: LaunchMode.externalApplication) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: AppText('تعذر فتح خريطة الموقع على هذا الجهاز.')));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح الموقع: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: context.watch<LocaleController>().isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: const AppText('المستوى 3 — منسق مجلس الخدمات'),
          actions: [
            IconButton(onPressed: _loadOperationsState, icon: const Icon(Icons.refresh)),
            IconButton(tooltip: tr('البحث الذكي'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GlobalSearchPage())), icon: const Icon(Icons.search_rounded)),
            IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsCenterScreen())), icon: const Icon(Icons.analytics_outlined)),
          ],
          bottom: TabBar(controller: _tabController, isScrollable: true, tabs: [Tab(text: tr('لوحة القيادة')), Tab(text: tr('الإدارة')), Tab(text: tr('التقارير والرسائل'))]),
        ),
        body: IndexedStack(index: tab, children: [_dashboardBody(), _managementBody(), _reportsBody()]),
        ),
    );
  }
  Widget _dashboardBody() {
    final redLight = _capacityPercent >= .85;
    return loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  AiHero(
                    user: context.read<AuthService>().currentUser!,
                    eyebrow: 'LEVEL 3 • JSC CONTROL',
                    title: 'مركز القيادة والتنسيق',
                    subtitle: 'السعة، الآليات والطوارئ في لوحة واحدة مع إشارات تشغيل ذكية.',
                  ),
                  const SizedBox(height: 10),
                  const OperationsOverviewStrip(),
                  const SizedBox(height: 6),
                  Text(context.watch<DataService>().automaticSyncStatus),
                  const SizedBox(height: 12),
                  Builder(builder: (context) {
                    final cs = context.watch<ContainerService>();
                    final critical = cs.containers.where((c) => c.status == 'full' || c.issueStatus == 'reported' || c.issueStatus == 'resolving').toList();
                    return AiSectionCard(
                      title: 'تنبيهات الحاويات',
                      subtitle: critical.isEmpty ? 'لا توجد تنبيهات حرجة للحاويات.' : '${critical.length} تنبيه في نطاق JSC.',
                      feature: 'containers',
                      child: critical.isEmpty
                          ? const AppText('لا توجد حاويات ممتلئة أو مشكلات مفتوحة.')
                          : Column(children: critical.take(8).map((c) => ListTile(contentPadding: EdgeInsets.zero, leading: Icon(c.status == 'full' ? Icons.warning_amber_rounded : Icons.report_problem_outlined, color: c.status == 'full' ? red : orange), title: AppText(c.locationName), subtitle: AppText(c.status == 'full' ? 'ممتلئة — يلزم التفريغ' : c.issueStatus == 'reported' ? 'مشكلة مسجلة' : 'إجراء تصحيحي قيد المعالجة'))).toList()),
                    );
                  }),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(width: 165, child: AiStatTile(title: 'سعة المكب', value: '${(_capacityPercent * 100).round()}%', subtitle: redLight ? 'تنبيه مرتفع' : 'ضمن النطاق', feature: 'dumpsite')),
                      SizedBox(width: 165, child: AiStatTile(title: 'الطوارئ', value: '${emergencies.length}', subtitle: 'بلاغات مرصودة', feature: 'emergency')),
                      const SizedBox(width: 165, child: AiStatTile(title: 'الدور', value: 'L3', subtitle: 'منسق JSC', feature: 'permissions')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.delete_sweep_outlined, color: redLight ? red : green, size: 34),
                              const SizedBox(width: 10),
                              const Expanded(child: AppText('سعة المكب المركزي', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                              AppText('${(_capacityPercent * 100).round()}%', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: redLight ? red : green)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(value: _capacityPercent, minHeight: 12, color: redLight ? red : green),
                          if (redLight) ...[
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: AppText('تحذير: السعة وصلت إلى 85% أو أكثر. أوقف توجيه الشاحنات الجديدة إلى هذا المكب واقترح نقطة بديلة.', style: TextStyle(color: red, fontWeight: FontWeight.w900)),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.tonalIcon(onPressed: _sendLandfillWarning, icon: const Icon(Icons.notifications_active_outlined), label: const AppText('إرسال تحذير للمستويات المعنية')),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CardSection3(
                    title: 'غرفة عمليات الطوارئ',
                    icon: const Icon(Icons.warning_amber_rounded, color: red),
                    child: emergencies.isEmpty
                        ? const ListTile(title: AppText('لا توجد بلاغات مفتوحة ضمن البيانات المتاحة.'))
                        : Column(
                            children: emergencies.take(20).map((e) {
                              final id = '${e['id']}';
                              final secured = e['status'] == 'secured';
                              final latitude = e['latitude'] ?? e['lat'] ?? e['locationLat'];
                              final longitude = e['longitude'] ?? e['lng'] ?? e['locationLng'];
                              final pending = _hasPendingSos(id);
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      AppText('بلاغ مخلفات حربية #$id',
                                        style: const TextStyle(fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 6),
                                      AppText('${e['street'] ?? 'موقع غير محدد'} • ${e['status'] ?? 'urgent'}\nالإحداثيات: ${latitude ?? 'غير متوفرة'}، ${longitude ?? 'غير متوفرة'}'),
                                      if (pending) const Padding(
                                        padding: EdgeInsets.only(top: 6),
                                        child: AppText('هناك إجراء محلي بانتظار تأكيد المزامنة.'),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8, runSpacing: 8,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: () => _copyEmergencyDetails(e),
                                            icon: const Icon(Icons.copy_outlined),
                                            label: const AppText('نسخ تفاصيل الإحالة')),
                                          if (latitude is num && longitude is num)
                                            OutlinedButton.icon(
                                              onPressed: () => _openSosLocation(latitude, longitude),
                                              icon: const Icon(Icons.place_outlined),
                                              label: const AppText('فتح الموقع')),
                                          if (e['acknowledged'] != true && e['status'] == 'urgent')
                                            OutlinedButton.icon(
                                              onPressed: pending ? null : () => _acknowledgeEmergency(id),
                                              icon: const Icon(Icons.check_circle_outline),
                                              label: const AppText('تأكيد الاستلام')),
                                          if (e['acknowledged'] == true &&
                                              const ['acknowledged', 'resolved', 'reopened'].contains(e['status']))
                                            FilledButton(
                                              onPressed: pending ? null : () => _closeSos(id),
                                              child: const AppText('إغلاق SOS')),
                                          if (!secured && !const ['reopened', 'closed'].contains(e['status']) &&
                                              e['referredBy'] == null)
                                            OutlinedButton.icon(
                                              onPressed: pending ? null : () => _referEmergency(id),
                                              icon: const Icon(Icons.forward),
                                              label: const AppText('إحالة')),
                                          if (e['acknowledged'] == true &&
                                              const ['acknowledged', 'resolved'].contains(e['status']) &&
                                              e['referralDestination'] == 'هندسة المتفجرات')
                                            OutlinedButton.icon(
                                              onPressed: pending ? null : () => _recordSecuredSite(id),
                                              icon: const Icon(Icons.verified_user_outlined),
                                              label: const AppText('توثيق تأمين الموقع')),
                                          if (secured && e['acknowledged'] == true)
                                            OutlinedButton.icon(
                                              onPressed: pending ? null : () => _reopenStreet(id),
                                              icon: const Icon(Icons.lock_open),
                                              label: const AppText('إعادة فتح')),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                  ),
                ],
              );
  }

  Widget _managementBody() => ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 120), children: [
    CreativeShortcutGrid(emphasize: true, maxColumns: 2, items: [
      CreativeShortcut(title: 'توجيه الآليات', subtitle: 'إرسال المعدات للمواقع', feature: 'operations', onTap: _chooseDispatch),
      CreativeShortcut(title: 'استعادة الآليات', subtitle: 'إنهاء التوجيه وإتاحتها', feature: 'operations', onTap: _chooseEquipmentReturn),
      CreativeShortcut(title: 'الحاويات', subtitle: 'إدارة المواقع والحالات', feature: 'containers', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContainerManagementScreen()))),
      CreativeShortcut(title: 'المكبات', subtitle: 'السعة والامتلاء والحالة', feature: 'dumpsite', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OperationsManagementScreen(initialTab: 0)))),
      CreativeShortcut(title: 'التقارير', subtitle: 'تقارير البلديات والتشغيل', feature: 'reports', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsCenterScreen()))),
    ]),
  ]);

  Widget _reportsBody() => ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 120), children: [
    AiSectionCard(title: 'التقارير والرسائل', subtitle: 'التقارير التشغيلية والتواصل الداخلي.', feature: 'reports', child: Column(children: [
      FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsCenterScreen())), icon: const Icon(Icons.analytics_outlined), label: const AppText('فتح التقارير')),
      const SizedBox(height: 8),
      FilledButton.tonalIcon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MessagesCenterScreen())), icon: const Icon(Icons.forum_outlined), label: const AppText('فتح الرسائل')),
    ])),
  ]);

}

class CardSection3 extends StatelessWidget {
  final String title;
  final Widget icon;
  final Widget child;
  const CardSection3({super.key, required this.title, required this.icon, required this.child});
  @override
  Widget build(BuildContext context) => AiSectionCard(title: title, feature: title.contains('طوارئ') ? 'emergency' : 'operations', child: child);
}
