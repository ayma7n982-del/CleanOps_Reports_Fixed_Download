import 'action_decision_hub.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/fast_smart_search.dart';
import '../../core/services/container_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/localization.dart';
import '../../core/models/core_models.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/config_service.dart';
import '../../core/services/data_service.dart';
import '../../core/services/messaging_service.dart';
import '../../core/services/operations_admin_service.dart';
import '../../core/services/operational_insights.dart';
import '../../core/services/trip_lifecycle.dart';
import '../../core/services/excel_file_saver.dart';
import '../widgets/app_design.dart';
import '../widgets/creative_shortcuts.dart';
import 'container_management.dart';
import 'operations_management.dart';
import 'equipment_search.dart';
import 'global_search.dart';
import 'ai_bot_screen.dart';
import '../widgets/operations_overview.dart';
import 'reports_center.dart';
import 'user_management_settings.dart';
import '../../core/constants/app_constants.dart';

class EnterpriseOperationsHubPage extends StatelessWidget {
  const EnterpriseOperationsHubPage({super.key});
  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser!;
    final tiles = <CreativeShortcut>[
      if (user.can('containers', 'view'))
        CreativeShortcut(title: 'الحاويات', subtitle: 'الحالة والامتلاء والمشكلات', feature: 'containers', onTap: () => _push(context, const ContainerManagementScreen())),
      if (user.can('dumpsite', 'view'))
        CreativeShortcut(title: 'المكبات', subtitle: 'السعة والامتلاء والحالة', feature: 'dumpsite', onTap: () => _push(context, user.role == 'donor_manager' ? const DumpsitesOverviewScreen() : OperationsManagementScreen(initialTab: user.role == 'municipality_coordinator' ? 1 : 0))),
      if (user.can('operations', 'view') &&
          const ['donor_manager', 'jsc_coordinator', 'municipality_coordinator'].contains(user.role))
        CreativeShortcut(title: 'بحث المعدات', subtitle: 'بحث سريع بالاسم والنوع والموقع', feature: 'operations', onTap: () => _push(context, const EquipmentSearchScreen())),
      if (user.can('operations', 'view') || user.can('reports', 'view'))
        CreativeShortcut(title: 'البحث الشامل', subtitle: 'بحث ذكي يفهم الاختلافات والأخطاء', feature: 'reports', onTap: () => _push(context, const GlobalSearchPage())),
      if (user.can('emergency', 'view'))
        CreativeShortcut(title: 'التنبيهات والبلاغات', subtitle: 'البلاغات والحالات الحرجة', feature: 'emergency', onTap: () => _push(context, const AlertsCenterPage())),
      if (user.can('workers', 'view')) CreativeShortcut(title: 'المجموعات والعمال', subtitle: 'الحالة والتوزيع والأفراد', feature: 'workers', onTap: () => _push(context, const GroupsCommandCenterPage())),
      if (user.can('trips', 'view')) CreativeShortcut(title: 'سجل الترحيلات', subtitle: 'جميع النقلات الموثقة', feature: 'trips', onTap: () => _push(context, const TripsLogPage())),
      if (user.can('reports', 'view')) CreativeShortcut(title: 'التقارير', subtitle: 'الغياب والحاويات والعمل والدورات', feature: 'reports', onTap: () => _push(context, const ReportsCenterScreen())),
      if (user.can('sync', 'view'))
        CreativeShortcut(title: 'المزامنة', subtitle: 'Online / Offline والطوابير', feature: 'sync', onTap: () => _push(context, const SyncCenterPage())),
      if (user.can('permissions', 'view'))
        CreativeShortcut(title: 'الأمان', subtitle: 'الحساب والجلسة والصلاحيات', feature: 'permissions', onTap: () => _push(context, const SecurityCenterPage())),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const AppText('مركز الإدارة والتشغيل'),
        actions: [IconButton(tooltip: tr('البحث الذكي'), onPressed: () => _push(context, const GlobalSearchPage()), icon: const Icon(Icons.search_rounded))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
        const ActionDecisionHubEntry(),
        AiHero(user: user, eyebrow: 'CLEANOPS OPERATIONS HUB', title: 'مركز الإدارة والتشغيل', subtitle: 'مركز بسيط للوصول إلى أهم الأصول والبحث والتنبيهات.'),
        const SizedBox(height: 14),
        FutureBuilder<Map<String, dynamic>>(
          future: context.read<OperationsAdminService>().liveOperationalSnapshot(user),
          builder: (context, snap) {
            if (!snap.hasData) return const _LoadingCard();
            final x = snap.data!;
            return AiSectionCard(title: 'لقطة تشغيلية حقيقية', subtitle: 'تُقرأ من Firestore ولا تستخدم أرقامًا تجريبية', feature: 'dashboard', trailing: AppText(_time(x['checkedAt']), style: const TextStyle(color: cleanOpsMuted, fontSize: 10)), child: Wrap(spacing: 10, runSpacing: 10, children: [
              if (user.can('workers', 'view')) _HubMetric('العمال النشطون', '${x['workers']}', 'workers'),
              if (user.can('operations', 'view')) _HubMetric('المجموعات', '${x['groups']}', 'operations'),
              if (user.can('emergency', 'view')) _HubMetric('الطوارئ', '${x['emergencies']}', 'emergency'),
              if (user.can('dumpsite', 'view')) _HubMetric('مكبات حرجة', '${x['criticalDumpsites']}', 'dumpsite'),
            ]));
          },
        ),
        const SizedBox(height: 14),
        CreativeShortcutGrid(items: tiles, emphasize: true, maxColumns: 2),
      ],
      ),
    );
  }
  static String _time(dynamic v) => v is DateTime ? '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}' : '--:--';
  static void _push(BuildContext c, Widget page) => Navigator.push(c, MaterialPageRoute(builder: (_) => page));
}

class _HubMetric extends StatelessWidget { final String title,value,feature; const _HubMetric(this.title,this.value,this.feature); @override Widget build(BuildContext c)=>Container(width: MediaQuery.sizeOf(c).width < 500 ? 105 : 130,padding: const EdgeInsets.all(10),decoration: BoxDecoration(color: aiDark2.withOpacity(.65),borderRadius: BorderRadius.circular(14),border: Border.all(color: aiCyan.withOpacity(.16))),child: Row(children:[AiFeatureIcon(feature,size:13),const SizedBox(width:7),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[AppText(value,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),AppText(title,style:const TextStyle(fontSize:9,color:cleanOpsMuted),overflow:TextOverflow.ellipsis)]))])); }
class _LoadingCard extends StatelessWidget { const _LoadingCard(); @override Widget build(BuildContext c)=>const AiSectionCard(title:'جاري قراءة البيانات',subtitle:'من Firestore',feature:'sync',child:Center(child:Padding(padding:EdgeInsets.all(16),child:CircularProgressIndicator()))); }

class AlertsCenterPage extends StatelessWidget {
  const AlertsCenterPage({super.key});

  static DateTime _alertTime(Map<String, dynamic> data) {
    final value = data['createdAt'] ?? data['timestamp'] ?? data['updatedAt'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse('$value') ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  static String _priorityLabel(Map<String, dynamic> data) {
    switch (OperationalInsights.alertPriority(data)) {
      case 0:
        return 'حرج';
      case 1:
        return 'مرتفع';
      default:
        return 'عادي';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    return _OpsStreamPage(
      title: 'مركز التنبيهات',
      feature: 'emergency',
      query: FirebaseFirestore.instance.collection('operations')
          .where('_entity', whereIn: ['emergency', 'notification']).limit(200),
      empty: 'لا توجد تنبيهات أو بلاغات مسجلة.',
      builder: (docs) {
        if (user == null || !user.can('emergency', 'view')) {
          return const AppText('ليست لديك صلاحية لعرض التنبيهات.');
        }
        bool visible(Map<String, dynamic> data) => OperationalInsights.visibleToUser(
          data, role: user.role, userId: user.id, scope: user.scope,
          groupId: user.groupId,
        );
        final targetedIncidents = <String>{};
        for (final doc in docs) {
          final data = doc.data();
          if (data['_entity'] == 'notification' && visible(data)) {
            final sourceId = '${data['sourceId'] ?? ''}'.trim();
            if (sourceId.isNotEmpty && data['sourceEntity'] == 'emergency') {
              targetedIncidents.add(sourceId);
            }
          }
        }
        final selected = docs.where((doc) {
          final data = doc.data();
          return OperationalInsights.isOpenAlert(data) &&
              (visible(data) || (data['_entity'] == 'emergency' &&
                  targetedIncidents.contains(doc.id)));
        }).toList()
          ..sort((a, b) {
            final priority = OperationalInsights.alertPriority(a.data())
                .compareTo(OperationalInsights.alertPriority(b.data()));
            if (priority != 0) return priority;
            return _alertTime(b.data()).compareTo(_alertTime(a.data()));
          });
        final seen = <String>{};
        final unique = selected.where((doc) =>
            seen.add(OperationalInsights.alertIncidentKey(doc.data(), doc.id))).toList();
        if (unique.isEmpty) {
          return const AppText('لا توجد بلاغات مفتوحة ضمن نطاق صلاحياتك.');
        }
        return Column(children: [
          AppText('البلاغات الفعالة: ${unique.length} — مرتبة حسب الأولوية، دون تكرار البلاغ نفسه.',
              style: const TextStyle(fontSize: 11, color: cleanOpsMuted)),
          ...unique.map((doc) {
            final data = doc.data();
            final time = _alertTime(data);
            final hasTime = time.millisecondsSinceEpoch > 0;
            return _OperationTile(
              doc,
              critical: OperationalInsights.alertPriority(data) == 0,
              alertMeta: '${_priorityLabel(data)}${hasTime ? ' • ${time.year.toString().padLeft(4, '0')}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}' : ''}',
            );
          }),
        ]);
      },
    );
  }
}

class TripsLogPage extends StatelessWidget {
  const TripsLogPage({super.key});
  @override Widget build(BuildContext context) => _OpsStreamPage(title:'سجل الترحيلات',feature:'trips',query:FirebaseFirestore.instance.collection('operations').where('_entity',isEqualTo:'trip').limit(300),empty:'لا توجد ترحيلات مسجلة.',builder:(docs)=>Column(children:docs.map((d)=>_OperationTile(d)).toList()));
}

class _OpsStreamPage extends StatelessWidget {
  final String title,feature,empty; final Query<Map<String,dynamic>> query; final Widget Function(List<QueryDocumentSnapshot<Map<String,dynamic>>>) builder;
  const _OpsStreamPage({required this.title,required this.feature,required this.query,required this.empty,required this.builder});
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:AppText(title)),body:StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:query.snapshots(),builder:(c,s){if(s.hasError)return Center(child:Padding(padding:const EdgeInsets.all(20),child:AppText('تعذر تحميل البيانات: ${s.error}')));if(!s.hasData)return const Center(child:CircularProgressIndicator());final docs=s.data!.docs.toList()..sort((a,b)=>'${b.data()['createdAt']??b.data()['timestamp']??''}'.compareTo('${a.data()['createdAt']??a.data()['timestamp']??''}'));if(docs.isEmpty)return Center(child:AppText(empty));return ListView(padding:const EdgeInsets.fromLTRB(16,16,16,120),children:[AiSectionCard(title:title,feature:feature,subtitle:s.data!.metadata.isFromCache ? 'بيانات محلية مخزنة (قد تكون قديمة)' : 'بيانات Firestore بحسب الصلاحيات',child:builder(docs))]);}));
}
class _OperationTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool critical;
  final String? alertMeta;
  const _OperationTile(this.doc, {this.critical = false, this.alertMeta});

  @override
  Widget build(BuildContext context) {
    final record = doc.data();
    final user = context.watch<AuthService>().currentUser;
    final entity = '${record['_entity'] ?? ''}';
    final activeUserId = user?.id ?? '';
    final title = '${record['title'] ?? record['name'] ?? record['operation'] ?? entity}';
    final detail = '${record['body'] ?? record['detail'] ?? record['description'] ?? record['status'] ?? ''}';
    final tripReview = entity == 'trip'
        ? OperationalInsights.reviewTrips([record], now: DateTime.now())
        : const OperationalTripReview(assessable: 0, overdue: 0);
    final overdue = tripReview.overdue > 0;
    final canComplete = entity == 'trip' && user != null &&
        user.role == 'group_supervisor' && user.can('trips', 'edit') &&
        TripLifecycle.canSupervisorComplete(
          trip: record,
          supervisorId: user.id,
          groupId: user.groupId ?? '',
        );
    final baseDetail = overdue
        ? 'متأخرة عن الموعد المستهدف • ${detail.isEmpty ? 'قيد التنفيذ' : detail}'
        : detail;
    final displayDetail = alertMeta == null || alertMeta!.isEmpty
        ? baseDetail
        : '$alertMeta${baseDetail.isEmpty ? '' : ' • $baseDetail'}';
    final fields = <String, Object?>{
      'معرّف السجل': doc.id,
      'الحالة': record['status'],
      'درجة الأولوية': record['statusLevel'] ?? record['level'],
      'المجموعة': record['groupName'] ?? record['groupId'],
      'البلدية': record['municipalityName'] ?? record['municipality'],
      'الشارع / الموقع': record['street'] ?? record['location'],
      'المكب / الوجهة': record['landfill'],
      'كمية النفايات': record['estimatedQuantity'],
      'تاريخ التسجيل': record['createdAt'],
      'تاريخ الموعد المستهدف': record['deadlineAt'] ?? record['dueAt'],
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: AiFeatureIcon(critical ? 'emergency' : entity == 'trip' ? 'trips' : 'notifications', size: 15),
      title: AppText(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      subtitle: AppText(displayDetail, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, color: overdue ? Colors.orange : cleanOpsMuted,
              fontWeight: overdue ? FontWeight.w700 : FontWeight.normal)),
      trailing: Icon(overdue ? Icons.warning_amber_rounded : Icons.chevron_left_rounded,
          size: 18, color: overdue ? Colors.orange : null),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: AppText(title),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (detail.isNotEmpty) AppText(detail),
                ...fields.entries.where((entry) =>
                    entry.value != null && '${entry.value}'.trim().isNotEmpty)
                    .map((entry) => ListTile(
                      dense: true,
                      title: AppText(entry.key),
                      subtitle: AppText('${entry.value}'),
                    )),
              ],
            ),
          ),
          actions: [
            if (canComplete)
              FilledButton.icon(
                onPressed: () async {
                  final current = context.read<AuthService>().currentUser;
                  if (current == null || current.id != activeUserId) return;
                  final fields = TripLifecycle.completionFields(
                    completedAt: DateTime.now(),
                    completedBy: current.id,
                  );
                  await context.read<DataService>().enqueue('trip', 'update', {
                    'id': doc.id,
                    ...fields,
                  });
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: AppText('تم إنهاء النقلة محليًا وستتم مزامنتها تلقائيًا.'),
                  ));
                },
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const AppText('اعتماد الوصول وإنهاء النقلة'),
              ),
            TextButton(onPressed: () => Navigator.pop(context),
                child: const AppText('إغلاق')),
          ],
        ),
      ),
    );
  }
}

class SyncCenterPage extends StatelessWidget {
  const SyncCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DataService>();
    final m = context.watch<MessagingService>();
    final c = context.watch<ConfigService>();
    return Scaffold(
      appBar: AppBar(title: const AppText('مركز المزامنة')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          AiSectionCard(
            title: 'حالة الاتصال والمزامنة التلقائية',
            feature: 'sync',
            child: ListTile(
              leading: Icon(
                d.syncing
                    ? Icons.sync_rounded
                    : d.online
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_off_rounded,
                color: d.online ? aiGreen : Colors.orange,
              ),
              title: AppText(d.online ? 'Online' : 'Offline'),
              subtitle: AppText(d.automaticSyncStatus),
              trailing: d.queue.isEmpty
                  ? const Icon(Icons.check_circle_outline_rounded, color: aiGreen)
                  : Badge(label: AppText('${d.queue.length}')),
            ),
          ),
          const SizedBox(height: 12),
          AiSectionCard(
            title: 'طابور البيانات المحلي',
            feature: 'sync',
            child: Column(children: [
              _kv('عمليات بانتظار المزامنة', '${d.queue.length}'),
              _kv('آخر مزامنة ناجحة', d.lastSync),
              _kv('آخر تحديث للبيانات',
                  d.lastDataRefresh.isEmpty ? 'لم يتم بعد' : d.lastDataRefresh),
              _kv('مزامنة الرسائل التلقائية', c.autoMessageSync ? 'مفعّلة' : 'متوقفة'),
              _kv('الرسائل غير المقروءة', '${m.unreadCount}'),
              _kv('الرسائل المحلية', c.localMessagingEnabled ? 'مفعّلة' : 'متوقفة'),
              _kv('الرسائل Online', c.onlineMessagingEnabled ? 'مفعّلة' : 'متوقفة'),
            ]),
          ),
          const SizedBox(height: 12),
          AiSectionCard(
            title: 'سلوك Offline',
            feature: 'messages',
            child: AppText(
              d.online
                  ? 'لا تحتاج إلى زر مزامنة. أي عمليات محلية معلقة تُرسل تلقائيًا، وتُحدّث البيانات دوريًا عند توفر الاتصال.'
                  : 'أنت تعمل دون اتصال. العمليات تُحفظ محليًا، وتُرسل تلقائيًا عند عودة الإنترنت دون أي إجراء يدوي.',
            ),
          ),
        ],
      ),
    );
  }
}

class SystemHealthPage extends StatefulWidget { const SystemHealthPage({super.key}); @override State<SystemHealthPage> createState()=>_SystemHealthPageState(); }
class _SystemHealthPageState extends State<SystemHealthPage>{Map<String,String> state={};bool busy=false;Future<void> check()async{setState(()=>busy=true);final next=<String,String>{};next['Firebase']=Firebase.apps.isNotEmpty?'جاهز':'غير مهيأ';next['Authentication']=FirebaseAuth.instance.currentUser != null?'جلسة نشطة':'لا توجد جلسة';try{await FirebaseFirestore.instance.collection('config').doc('global').get(const GetOptions(source:Source.server)).timeout(const Duration(seconds:5));next['Firestore']='متصل';}catch(e){next['Firestore']='غير متاح';}final c=context.read<ConfigService>();next['API']=c.apiEnabled?(c.apiBaseUrl.isEmpty?'مفعّل بلا عنوان':'مفعّل'):'غير مفعّل';next['Local Store']='جاهز';setState(()=>state=next..['Checked At']=DateTime.now().toIso8601String());setState(()=>busy=false);} @override void initState(){super.initState();unawaited(check());} @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const AppText('صحة النظام')),body:ListView(padding:const EdgeInsets.fromLTRB(16,16,16,120),children:[AiSectionCard(title:'System Health',subtitle:'فحص فعلي للخدمات المتاحة',feature:'operations',trailing:IconButton(onPressed:busy?null:check,icon:const Icon(Icons.refresh_rounded)),child:Column(children:state.entries.map((e)=>ListTile(dense:true,leading:Icon(e.key=='Checked At'?Icons.schedule_rounded:Icons.circle,color:e.key=='Checked At'?cleanOpsMuted:(e.value.contains('غير')||e.value.contains('لا ')?Colors.orange:aiGreen),size:15),title:AppText(e.key,style:const TextStyle(fontSize:11)),trailing:AppText(e.value,style:const TextStyle(fontSize:10,color:cleanOpsText)))).toList()))]));}


class GlobalSearchPage extends StatefulWidget {
  final String initialQuery;
  final bool openExactResult;
  const GlobalSearchPage({
    super.key,
    this.initialQuery = '',
    this.openExactResult = false,
  });

  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  final controller = TextEditingController();
  final FastSmartSearch _index = FastSmartSearch();
  late DataService _dataService;
  late ContainerService _containerService;
  late AppUser _actor;
  List<FastSearchRecord> results = const [];
  bool remoteLoading = false;
  bool _loadedOnce = false;
  bool _autoOpened = false;
  String? remoteWarning;
  String categoryFilter = 'الكل';

  @override
  void initState() {
    super.initState();
    controller.text = widget.initialQuery;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _actor = context.read<AuthService>().currentUser!;
      _dataService = context.read<DataService>();
      _containerService = context.read<ContainerService>();
      _dataService.addListener(_refreshLocalSources);
      _containerService.addListener(_refreshLocalSources);
      _refreshLocalSources();
      _loadRemoteSources();
    });
  }

  @override
  void dispose() {
    if (_loadedOnce) {
      _dataService.removeListener(_refreshLocalSources);
      _containerService.removeListener(_refreshLocalSources);
    }
    controller.dispose();
    super.dispose();
  }

  static String _operationCategory(Map<String, dynamic> data) {
    return switch ('${data['_entity'] ?? ''}') {
      'group' => 'مجموعة',
      'trip' => 'نقلة',
      'cycle' => 'دورة',
      'municipality' => 'بلدية',
      'emergency' || 'sos' => 'طوارئ',
      'container' => 'حاوية',
      'dumpsite' => 'مكب',
      'heavy_machinery' || 'equipment' => 'معدة',
      'attendance' => 'حضور',
      'work_report' || 'report' => 'تقرير',
      'worker' => 'عامل',
      _ => 'عملية',
    };
  }

  static String _userCategory(Map<String, dynamic> data) {
    final role = '${data['role'] ?? ''}';
    if (role == 'worker' || role == 'worker_with_cart') return 'عامل';
    if (role == 'group_supervisor') return 'مشرف';
    return 'مستخدم';
  }

  // Local operational records are filtered by the current role before indexing.
  // In particular, no cached data from another municipal/group scope is surfaced.
  bool _canSeeOperation(Map<String, dynamic> row) {
    if (row['isDeleted'] == true) return false;
    if (_actor.role == 'group_supervisor' || _actor.role == 'worker') {
      final groupId = (_actor.groupId ?? '').trim();
      return groupId.isNotEmpty && '${row['groupId'] ?? ''}' == groupId;
    }
    if (_actor.role == 'municipality_coordinator') {
      if ('${row['municipalityCoordinatorId'] ?? ''}' == _actor.id ||
          '${row['coordinatorId'] ?? ''}' == _actor.id) {
        return true;
      }
      final scope = _actor.scope.trim();
      if (scope.isEmpty || scope == 'assigned_only' || scope == 'all') return false;
      return FastSmartSearch.normalize('${row['municipalityName'] ?? row['municipality'] ?? row['municipalityId'] ?? ''}') ==
          FastSmartSearch.normalize(scope);
    }
    if (_actor.role == 'jsc_coordinator') {
      final scope = _actor.scope.trim();
      if (scope.isEmpty || scope == 'all' || scope == 'assigned_only') return true;
      return FastSmartSearch.normalize('${row['councilName'] ?? row['councilId'] ?? row['municipalityName'] ?? ''}') ==
          FastSmartSearch.normalize(scope);
    }
    return true;
  }

  void _refreshLocalSources() {
    if (!mounted) return;
    _loadedOnce = true;
    _index.replaceSource(
      'operations', 'عملية',
      _dataService.operations.where(_canSeeOperation),
      categoryFor: _operationCategory,
    );
    if (_actor.can('containers', 'view')) {
      _index.replaceSource(
        'containers', 'حاوية',
        _containerService.containers.map((item) => item.toMap()),
      );
    }
    _applyQuery();
  }

  void _applyQuery() {
    if (!mounted) return;
    final found = _index.find(controller.text, limit: 100);
    setState(() => results = found);
    if (widget.openExactResult && !_autoOpened) {
      final expected = widget.initialQuery.trim();
      final exact = found.where((record) => record.id == expected).toList();
      if (exact.length == 1) {
        _autoOpened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openRecord(exact.single);
        });
      }
    }
  }

  Future<void> _loadRemoteSources() async {
    if (remoteLoading || !mounted) return;
    if (Firebase.apps.isEmpty) {
      setState(() => remoteWarning = 'البحث يعمل على البيانات المحلية؛ Firebase غير مهيأ.');
      return;
    }
    final canFetchServer = _dataService.online &&
        !context.read<AuthService>().offlineSession;
    setState(() { remoteLoading = true; remoteWarning = null; });
    final db = FirebaseFirestore.instance;
    final pending = <Future<void>>[];
    var failures = 0;

    // Restrict remote cached records as well as server results. The offline
    // Firestore cache is shared by the installation, so role scoping matters.
    bool visibleRemote(String collection, Map<String, dynamic> record) {
      if (record['isDeleted'] == true) return false;
      if (collection == 'users') return true; // Users are scoped at query level.
      if (_actor.role == 'municipality_coordinator' ||
          _actor.role == 'jsc_coordinator' ||
          _actor.role == 'group_supervisor' || _actor.role == 'worker') {
        return _canSeeOperation(record);
      }
      return true;
    }

    void add(String collection, String label, Query<Map<String, dynamic>> query,
        {String Function(Map<String, dynamic>)? categoryFor}) {
      pending.add(() async {
        final limited = query.limit(800);
        void apply(QuerySnapshot<Map<String, dynamic>> snapshot) {
          if (!mounted || context.read<AuthService>().currentUser?.id != _actor.id) return;
          final docs = snapshot.docs
              .map((doc) => {...doc.data(), 'id': doc.id})
              .where((doc) => visibleRemote(collection, doc));
          _index.replaceSource(collection, label, docs, categoryFor: categoryFor);
          _applyQuery();
        }

        // Cached Firestore data is normally available without any network wait.
        try {
          final cached = await limited.get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 2));
          if (cached.docs.isNotEmpty) apply(cached);
        } catch (_) {
          // A first-time install legitimately has no cached query.
        }
        if (!canFetchServer) return;
        try {
          final snapshot = await limited.get().timeout(const Duration(seconds: 9));
          apply(snapshot);
        } catch (_) {
          failures++;
        }
      }());
    }

    // The container service already maintains an authorized live/offline feed.
    // Unlike the previous implementation, no Firestore request happens on each keystroke.
    if (_dataService.operations.isEmpty) {
      Query<Map<String, dynamic>> operations = db.collection('operations');
      if (_actor.role == 'group_supervisor' || _actor.role == 'worker') {
        final groupId = (_actor.groupId ?? '').trim();
        if (groupId.isNotEmpty) {
          operations = operations.where('groupId', isEqualTo: groupId);
          add('remote_operations', 'عملية', operations,
              categoryFor: _operationCategory);
        }
      } else {
        add('remote_operations', 'عملية', operations,
            categoryFor: _operationCategory);
      }
    }
    if (_actor.can('workers', 'view') &&
        const ['donor_manager', 'jsc_coordinator', 'municipality_coordinator'].contains(_actor.role)) {
      Query<Map<String, dynamic>> users = db.collection('users');
      if (_actor.role == 'municipality_coordinator') {
        users = users.where('municipalityCoordinatorId', isEqualTo: _actor.id);
      }
      add('users', 'مستخدم', users, categoryFor: _userCategory);
    }
    if (_actor.can('operations', 'view') &&
        const ['donor_manager', 'jsc_coordinator', 'municipality_coordinator'].contains(_actor.role)) {
      add('equipment', 'معدة', db.collection('equipment'));
      add('work_cycles', 'دورة', db.collection('work_cycles'));
    }
    if (_actor.can('dumpsite', 'view') &&
        const ['donor_manager', 'jsc_coordinator', 'municipality_coordinator'].contains(_actor.role)) {
      add('dumpsites', 'مكب', db.collection('dumpsites'));
    }
    if (_actor.role == 'donor_manager' || _actor.role == 'jsc_coordinator') {
      add('municipalities', 'بلدية', db.collection('municipalities'));
    }

    await Future.wait(pending);
    if (!mounted) return;
    setState(() {
      remoteLoading = false;
      remoteWarning = !canFetchServer
          ? 'وضع عدم الاتصال: البحث يعمل على البيانات المحلية المخزنة.'
          : failures > 0
              ? 'تعذر تحديث بعض الأقسام من الشبكة؛ النتائج المحلية ما زالت متاحة.'
              : null;
    });
  }

  void _openRecord(FastSearchRecord result) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SearchRecordPage(record: result),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = controller.text.trim().isNotEmpty;
    final categories = <String>['الكل', ...results.map((r) => r.category).toSet()];
    final displayed = categoryFilter == 'الكل'
        ? results
        : results.where((r) => r.category == categoryFilter).toList();
    return Scaffold(
      appBar: AppBar(
        title: const AppText('البحث الشامل'),
        actions: [
          IconButton(
            tooltip: 'تحديث نتائج البحث',
            onPressed: remoteLoading ? null : _loadRemoteSources,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 110),
        children: [
          TextField(
            controller: controller,
            autofocus: widget.initialQuery.isEmpty,
            textInputAction: TextInputAction.search,
            onChanged: (_) {
              categoryFilter = 'الكل';
              _applyQuery();
            },
            onSubmitted: (_) => _applyQuery(),
            decoration: InputDecoration(
              hintText: 'ابدأ بحرف واحد: اسم، عامل، مكب، حاوية...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'مسح البحث',
                      onPressed: () {
                        controller.clear();
                        categoryFilter = 'الكل';
                        _applyQuery();
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          if (remoteLoading)
            const LinearProgressIndicator(minHeight: 2),
          if (remoteLoading)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: AppText('نتائج البيانات المحلية فورية • يجري إضافة بيانات الشبكة', style: TextStyle(color: cleanOpsMuted, fontSize: 11)),
            ),
          if (remoteWarning != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: AppText(remoteWarning!, style: const TextStyle(color: cleanOpsMuted, fontSize: 12)),
            ),
          if (!hasQuery)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Column(children: [
                Icon(Icons.manage_search_rounded, size: 58, color: aiBlue),
                SizedBox(height: 12),
                AppText('اكتب حرفًا واحدًا على الأقل لعرض النتائج فورًا.'),
                SizedBox(height: 8),
                AppText('يدعم الأخطاء الإملائية والمرادفات؛ اضغط النتيجة لفتح سجلها.', style: TextStyle(color: cleanOpsMuted, fontSize: 12), textAlign: TextAlign.center),
              ]),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: AppText(
                '${results.length} نتيجة مطابقة' + (results.length == 100 ? ' (أول 100 نتيجة)' : ''),
                style: const TextStyle(color: aiBlue, fontWeight: FontWeight.w800),
              ),
            ),
            if (categories.length > 2)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final category in categories)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: ChoiceChip(
                          label: AppText(category),
                          selected: categoryFilter == category,
                          onSelected: (_) => setState(() => categoryFilter = category),
                        ),
                      ),
                  ],
                ),
              ),
            if (displayed.isEmpty && !remoteLoading)
              const Padding(
                padding: EdgeInsets.all(25),
                child: Center(child: AppText('لم نجد نتيجة مطابقة ضمن صلاحياتك. جرّب مرادفًا أو جزءًا من الاسم.')),
              ),
            for (final result in displayed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AiGlassCard(
                  padding: EdgeInsets.zero,
                  onTap: () => _openRecord(result),
                  child: ListTile(
                    onTap: () => _openRecord(result),
                    leading: AiFeatureIcon(
                      result.category == 'عامل' || result.category == 'مجموعة' || result.category == 'مستخدم'
                          ? 'workers'
                          : result.category == 'مكب' ? 'dumpsite'
                          : result.category == 'حاوية' ? 'containers'
                          : result.category == 'دورة' ? 'cycle'
                          : result.category == 'نقلة' ? 'trips'
                          : result.category == 'طوارئ' ? 'emergency'
                          : 'operations',
                      size: 19,
                    ),
                    title: AppText(result.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: AppText(
                      result.category + ' • ' + result.id,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: cleanOpsMuted, fontSize: 11),
                    ),
                    trailing: const Icon(Icons.arrow_circle_left_outlined, color: aiBlue),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Opens the *selected record* (not a generic textual search hit). When online,
/// its real document remains connected to Firestore; offline, the indexed copy
/// is shown. Actions connect it to the appropriate management page and map.
class _SearchRecordPage extends StatelessWidget {
  final FastSearchRecord record;
  const _SearchRecordPage({required this.record});

  static const _fields = <String, String>{
    'name': 'الاسم', 'nameAr': 'الاسم', 'fullName': 'الاسم',
    'username': 'اسم المستخدم', 'role': 'الصلاحية',
    'status': 'الحالة', 'machineStatus': 'حالة المعدة',
    'locationName': 'الموقع', 'location': 'الموقع', 'street': 'الشارع',
    'municipalityName': 'البلدية', 'municipality': 'البلدية',
    'groupName': 'المجموعة', 'groupId': 'رقم المجموعة',
    'groupNumber': 'رقم المجموعة', 'cycleName': 'الدورة',
    'landfill': 'المكب', 'dumpsiteName': 'المكب',
    'equipmentName': 'المعدة', 'plateNumber': 'رقم اللوحة',
    'model': 'الموديل', 'type': 'النوع', 'issueStatus': 'حالة المشكلة',
    'description': 'الوصف', 'notes': 'ملاحظات',
    'createdAt': 'تاريخ الإنشاء', 'updatedAt': 'آخر تحديث',
  };

  Widget? _destination(AppUser actor) {
    switch (record.category) {
      case 'عامل':
      case 'مستخدم':
      case 'مشرف':
        if (actor.role == 'donor_manager') return const UserManagementSettingsPage();
        if (actor.role == 'municipality_coordinator') return const OperationsManagementScreen(initialTab: 0);
        return null;
      case 'مجموعة':
        return const GroupsCommandCenterPage();
      case 'مكب':
        if (!actor.can('dumpsite', 'view')) return null;
        return actor.role == 'donor_manager'
            ? const DumpsitesOverviewScreen()
            : OperationsManagementScreen(initialTab: actor.role == 'municipality_coordinator' ? 1 : 0);
      case 'حاوية':
        return actor.can('containers', 'view') ? const ContainerManagementScreen() : null;
      case 'معدة':
        return actor.can('operations', 'view') ? const EquipmentSearchScreen() : null;
      case 'دورة':
        return actor.role == 'donor_manager'
            ? const OperationsManagementScreen(initialTab: 0)
            : const ReportsCenterScreen();
      case 'نقلة':
        return actor.can('trips', 'view') ? const TripsLogPage() : null;
      case 'طوارئ':
        return actor.can('emergency', 'view') ? const AlertsCenterPage() : null;
      case 'تقرير':
        return actor.can('reports', 'view') ? const ReportsCenterScreen() : null;
      case 'بلدية':
      case 'عملية':
      case 'حضور':
        return actor.can('operations', 'view') ? const EnterpriseOperationsHubPage() : null;
    }
    return null;
  }

  static double? _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('${value ?? ''}');

  static (double, double)? _coordinates(Map<String, dynamic> row) {
    final gps = row['gpsCoordinates'];
    final point = gps is Map ? gps : null;
    final lat = _number(point?['lat'] ?? point?['latitude'] ?? row['latitude'] ?? row['lat']);
    final lng = _number(point?['lng'] ?? point?['longitude'] ?? row['longitude'] ?? row['lng']);
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180 ||
        (lat == 0 && lng == 0)) return null;
    return (lat, lng);
  }

  @override
  Widget build(BuildContext context) {
    final actor = context.watch<AuthService>().currentUser;
    if (actor == null) {
      return const Scaffold(body: Center(child: AppText('يرجى تسجيل الدخول مجددًا.')));
    }
    final online = context.watch<DataService>().online && Firebase.apps.isNotEmpty;
    final source = record.collection == 'remote_operations' ? 'operations' : record.collection;
    final stream = online
        ? FirebaseFirestore.instance.collection(source).doc(record.id).snapshots()
        : null;
    return Scaffold(
      appBar: AppBar(title: AppText(record.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: stream == null
          ? _recordBody(context, record.data, fromCache: true)
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data!.exists && snapshot.data!.data() != null) {
                  return _recordBody(context, {...record.data, ...snapshot.data!.data()!},
                      fromCache: snapshot.data!.metadata.isFromCache);
                }
                return _recordBody(context, record.data, fromCache: true);
              },
            ),
    );
  }

  Widget _recordBody(BuildContext context, Map<String, dynamic> data, {required bool fromCache}) {
    final actor = context.read<AuthService>().currentUser!;
    final destination = _destination(actor);
    final coordinates = _coordinates(data);
    final entries = _fields.entries
        .where((field) => data[field.key] != null &&
            '${data[field.key]}'.trim().isNotEmpty &&
            '${data[field.key]}' != 'null')
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 115),
      children: [
        AiSectionCard(
          title: record.title,
          subtitle: record.category + ' • سجل ' + record.id,
          feature: 'operations',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (fromCache)
                const Padding(
                  padding: EdgeInsets.only(bottom: 9),
                  child: AppText('نسخة محفوظة محليًا • قد تتأخر عن آخر تعديل',
                      style: TextStyle(color: cleanOpsMuted, fontSize: 11)),
                ),
              if (entries.isEmpty)
                const AppText('لا توجد تفاصيل إضافية لهذا السجل.')
              else
                for (final field in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 105, child: AppText(field.value,
                            style: const TextStyle(color: cleanOpsMuted, fontSize: 12))),
                        const SizedBox(width: 8),
                        Expanded(child: AppText('${data[field.key]}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (destination != null)
          FilledButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => destination)),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const AppText('فتح قسم إدارة السجل'),
          ),
        if (coordinates != null) ...[
          const SizedBox(height: 9),
          OutlinedButton.icon(
            onPressed: () async {
              final uri = Uri.https('www.google.com', '/maps/search/', {
                'api': '1',
                'query': '${coordinates.$1},${coordinates.$2}',
              });
              final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: AppText('تعذر فتح تطبيق الخرائط.')),
                );
              }
            },
            icon: const Icon(Icons.map_rounded),
            label: const AppText('فتح موقع السجل على الخريطة'),
          ),
        ],
        const SizedBox(height: 9),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: record.id));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: AppText('تم نسخ معرّف السجل.')),
              );
            }
          },
          icon: const Icon(Icons.copy_rounded),
          label: const AppText('نسخ معرّف السجل'),
        ),
      ],
    );
  }
}

class GroupsCommandCenterPage extends StatelessWidget {
  const GroupsCommandCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final u = context.watch<AuthService>().currentUser;
    if (u == null) return const Scaffold(body: Center(child: AppText('يرجى تسجيل الدخول مجددًا.')));
    final canManage = u.can('workers', 'edit');
    final groupQuery = FirebaseFirestore.instance.collection('operations').limit(1500);
    final userQuery = FirebaseFirestore.instance.collection('users').limit(1500);

    return Scaffold(
      appBar: AppBar(
        title: const AppText('مركز المجموعات'),
        actions: [
          if (canManage) IconButton(tooltip: 'استيراد مجموعات', icon: const Icon(Icons.file_upload_outlined), onPressed: () => _importGroups(context, u.id, u.role, u.scope)),
          if (canManage) IconButton(tooltip: 'تصدير Excel', icon: const Icon(Icons.file_download_outlined), onPressed: () => _exportGroups(context, actorId: u.id, actorRole: u.role, scope: u.scope, csv: false)),
          if (canManage) PopupMenuButton<String>(
            tooltip: 'خيارات التصدير',
            onSelected: (v) => _exportGroups(context, actorId: u.id, actorRole: u.role, scope: u.scope, csv: v == 'csv'),
            itemBuilder: (_) => const [PopupMenuItem(value: 'csv', child: AppText('تصدير CSV'))],
          ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(onPressed: () => _createGroup(context, u.id, u.scope), icon: const Icon(Icons.group_add_rounded), label: const AppText('إضافة مجموعة'))
          : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: groupQuery.snapshots(),
        builder: (context, groupsSnap) {
          if (groupsSnap.hasError) return Center(child: AppText('تعذر تحميل المجموعات: ${groupsSnap.error}'));
          if (!groupsSnap.hasData) return const Center(child: CircularProgressIndicator());
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: userQuery.snapshots(),
            builder: (context, usersSnap) {
              if (usersSnap.hasError) return Center(child: AppText('تعذر تحميل بيانات العمال: ${usersSnap.error}'));
              if (!usersSnap.hasData) return const Center(child: CircularProgressIndicator());
              final users = usersSnap.data!.docs;
              final counts = <String, int>{};
              final members = <String, List<Map<String, String>>>{};
              void addMember(String group, String id, Map<String, dynamic> data) {
                final label = '${data['name'] ?? data['fullName'] ?? data['displayName'] ?? data['username'] ?? data['workerName'] ?? id}'.trim();
                members.putIfAbsent(group.toLowerCase(), () => []).add({
                  'id': id,
                  'name': label.isEmpty ? id : label,
                  'role': '${data['role'] ?? 'worker'}',
                });
              }
              final seenMembers = <String>{};
              final legacyGroups = <String, Map<String, dynamic>>{};
              for (final d in users) {
                final x = d.data();
                if (x['isDeleted'] == true) continue;
                final rawGroup = '${x['groupId'] ?? x['groupNumber'] ?? x['group'] ?? ''}'.trim();
                if (rawGroup.isEmpty) continue;
                final active = x['isActive'] != false;
                if (active) {
                  final memberKey = '$rawGroup|${d.id}';
                  if (seenMembers.add(memberKey)) {
                    counts[rawGroup] = (counts[rawGroup] ?? 0) + 1;
                    addMember(rawGroup, d.id, x);
                  }
                  final key = rawGroup.toLowerCase();
                  legacyGroups.putIfAbsent(key, () => {
                    'id': 'legacy:$rawGroup', '_docId': '', '_isSynthetic': true,
                    'name': '${x['groupName'] ?? x['groupLabel'] ?? rawGroup}',
                    'groupName': '${x['groupName'] ?? x['groupLabel'] ?? rawGroup}',
                    'number': rawGroup, 'groupNumber': rawGroup, 'groupId': rawGroup,
                    'municipalityCoordinatorId': '${x['municipalityCoordinatorId'] ?? x['coordinatorId'] ?? ''}',
                    'municipalityName': '${x['municipalityName'] ?? x['municipality'] ?? x['scope'] ?? ''}',
                    'status': 'active',
                  });
                }
              }
              // Imported workers are stored as operations documents, not necessarily in
              // the users collection. Recover group names/numbers from those records too.
              for (final d in groupsSnap.data!.docs) {
                final x = d.data();
                if ('${x['_entity'] ?? ''}' != 'worker' || x['isDeleted'] == true) continue;
                final rawGroup = '${x['groupId'] ?? x['groupNumber'] ?? x['group'] ?? ''}'.trim();
                if (rawGroup.isEmpty) continue;
                final active = x['isActive'] != false;
                final personKey = '$rawGroup|${x['id'] ?? d.id}';
                if (active && seenMembers.add(personKey)) {
                  counts[rawGroup] = (counts[rawGroup] ?? 0) + 1;
                  addMember(rawGroup, '${x['id'] ?? d.id}', x);
                }
                final key = rawGroup.toLowerCase();
                legacyGroups.putIfAbsent(key, () => {
                  'id': 'legacy:$rawGroup', '_docId': '', '_isSynthetic': true,
                  'name': '${x['groupName'] ?? x['groupLabel'] ?? rawGroup}',
                  'groupName': '${x['groupName'] ?? x['groupLabel'] ?? rawGroup}',
                  'number': rawGroup, 'groupNumber': rawGroup, 'groupId': rawGroup,
                  'municipalityCoordinatorId': '${x['municipalityCoordinatorId'] ?? x['coordinatorId'] ?? ''}',
                  'municipalityName': '${x['municipalityName'] ?? x['municipality'] ?? x['scope'] ?? ''}',
                  'status': 'active',
                });
              }

              final visible = <Map<String, dynamic>>[];
              final knownKeys = <String>{};
              for (final d in groupsSnap.data!.docs) {
                final x = d.data();
                if ('${x['_entity'] ?? ''}' != 'group') continue;
                if (x['isDeleted'] == true || '${x['status'] ?? ''}'.toLowerCase() == 'deleted') continue;
                if (u.role == 'municipality_coordinator' && !_belongsToCoordinator(x, u.id, u.scope)) continue;
                final number = '${x['number'] ?? x['groupNumber'] ?? x['groupId'] ?? ''}'.trim();
                final name = '${x['name'] ?? x['groupName'] ?? number}'.trim();
                visible.add({...x, 'id': d.id, '_docId': d.id, '_isSynthetic': false, 'name': name, 'number': number});
                knownKeys.add(number.toLowerCase());
                knownKeys.add(name.toLowerCase());
                knownKeys.add(d.id.toLowerCase());
              }
              // Show groups that exist in worker records but were never written to the
              // operations group registry; this is the main legacy/missing-group case.
              for (final entry in legacyGroups.entries) {
                final g = entry.value;
                if (knownKeys.contains(entry.key)) continue;
                if (u.role == 'municipality_coordinator' && !_belongsToCoordinator(g, u.id, u.scope)) continue;
                visible.add(g);
              }
              visible.sort((a, b) => '${a['number'] ?? a['name'] ?? ''}'.compareTo('${b['number'] ?? b['name'] ?? ''}'));

              if (visible.isEmpty) {
                return ListView(padding: const EdgeInsets.all(18), children: [
                  const SizedBox(height: 80),
                  const Icon(Icons.groups_2_outlined, size: 56, color: aiCyan),
                  const SizedBox(height: 12),
                  const Center(child: AppText('لا توجد مجموعات مسجلة لهذا النطاق.')),
                  const SizedBox(height: 8),
                  const Center(child: AppText('يمكنك إنشاء مجموعة أو استيرادها من Excel/CSV.', style: TextStyle(color: cleanOpsMuted))),
                  if (canManage) ...[
                    const SizedBox(height: 18),
                    FilledButton.icon(onPressed: () => _createGroup(context, u.id, u.scope), icon: const Icon(Icons.add), label: const AppText('إنشاء مجموعة')),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(onPressed: () => _importGroups(context, u.id, u.role, u.scope), icon: const Icon(Icons.file_upload), label: const AppText('استيراد مجموعات')),
                  ],
                ]);
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  AiSectionCard(
                    title: 'المجموعات (${visible.length})',
                    feature: 'workers',
                    subtitle: 'تظهر المجموعات المسجلة وكذلك المجموعات القديمة المستنتجة من سجلات العمال.',
                    child: Column(children: visible.map((x) {
                      final id = '${x['_docId'] ?? ''}';
                      final number = '${x['number'] ?? x['groupNumber'] ?? x['groupId'] ?? ''}'.trim();
                      final name = '${x['name'] ?? x['groupName'] ?? number}'.trim();
                      final count = <String>{id, number, name}.where((e) => e.isNotEmpty).fold<int>(0, (sum, key) => sum + (counts[key] ?? 0));
                      final synthetic = x['_isSynthetic'] == true;
                      final groupMembers = <Map<String, String>>[];
                      final memberIds = <String>{};
                      for (final key in <String>{id, number, name}) {
                        for (final member in members[key.toLowerCase()] ?? const <Map<String, String>>[]) {
                          if (memberIds.add(member['id'] ?? '')) groupMembers.add(member);
                        }
                      }
                      return ExpansionTile(
                        leading: Icon(synthetic ? Icons.group_work_outlined : Icons.groups_rounded, color: synthetic ? Colors.amber : aiCyan),
                        title: AppText(name.isEmpty ? 'مجموعة ${number.isEmpty ? 'بدون رقم' : number}' : name),
                        subtitle: AppText('رقم المجموعة: ${number.isEmpty ? '—' : number} • العمال النشطون: $count • ${synthetic ? 'مجموعة قديمة تحتاج تسجيلًا' : (x['status'] ?? 'نشطة')}', style: const TextStyle(fontSize: 11, color: cleanOpsMuted)),
                        children: groupMembers.isEmpty
                            ? [const ListTile(title: AppText('لا توجد أسماء عمال مرتبطة بهذه المجموعة في البيانات المتاحة.'))]
                            : groupMembers.map((member) => ListTile(
                                dense: true,
                                leading: const Icon(Icons.person_outline),
                                title: AppText(member['name'] ?? 'عامل'),
                                subtitle: AppText(member['role'] == 'group_supervisor' ? 'مشرف مجموعة' : 'عامل'),
                              )).toList(),
                        trailing: canManage ? PopupMenuButton<String>(
                          tooltip: 'إدارة المجموعة',
                          onSelected: (v) {
                            if (v == 'edit') _editGroup(context, id, x, u.id, u.scope);
                            if (v == 'delete') _confirmDeleteGroup(context, id, number, name, count, synthetic);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'edit', child: AppText(synthetic ? 'تسجيل / تعديل المجموعة' : 'تعديل المجموعة')),
                            if (!synthetic) const PopupMenuItem(value: 'delete', child: AppText('حذف المجموعة')),
                          ],
                        ) : null,
                      );
                    }).toList()),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  static String _normalizeScope(String value) => value
      .replaceAll('\uFEFF', '')
      .replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا')
      .replaceAll('ة', 'ه').replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'^(بلديه|بلدية)\s*'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim().toLowerCase();

  static bool _belongsToCoordinator(Map<String, dynamic> x, String coordinatorId, String scope) {
    final owners = [x['municipalityCoordinatorId'], x['coordinatorId'], x['createdBy'], x['createdByUserId']]
        .map((v) => '${v ?? ''}'.trim()).where((v) => v.isNotEmpty);
    if (owners.contains(coordinatorId.trim())) return true;
    final expected = _normalizeScope(scope);
    final municipality = _normalizeScope('${x['municipalityName'] ?? x['municipality'] ?? x['municipalityScope'] ?? x['scope'] ?? ''}');
    return expected.isNotEmpty && municipality.isNotEmpty && expected == municipality;
  }

  Future<void> _createGroup(BuildContext context, String coordinatorId, String municipalityName) async {
    final number = TextEditingController();
    final name = TextEditingController();
    try {
      final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: const AppText('إضافة مجموعة جديدة'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: number, keyboardType: TextInputType.text, decoration: const InputDecoration(labelText: 'رقم المجموعة', hintText: 'مثال: 01')),
          const SizedBox(height: 10),
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'اسم المجموعة', hintText: 'مثال: المجموعة الأولى')),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const AppText('إلغاء')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const AppText('إضافة'))],
      ));
      if (ok != true || !context.mounted) return;
      final groupName = name.text.trim();
      final groupNumber = number.text.trim().isEmpty ? groupName : number.text.trim();
      if (groupName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('يرجى إدخال اسم المجموعة.')));
        return;
      }
      final ref = FirebaseFirestore.instance.collection('operations').doc();
      await ref.set({
        'id': ref.id, 'groupId': groupNumber, 'number': groupNumber, 'groupNumber': groupNumber,
        '_entity': 'group', 'name': groupName, 'groupName': groupName, 'title': groupName,
        'status': 'active', 'isActive': true, 'isDeleted': false,
        'municipalityCoordinatorId': coordinatorId, 'coordinatorId': coordinatorId,
        'municipalityName': municipalityName, 'municipality': municipalityName,
        'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(), 'createdBy': coordinatorId,
      });
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('تمت إضافة المجموعة وربطها بمنسق البلدية.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: AppText('تعذرت إضافة المجموعة: $e')));
    } finally { number.dispose(); name.dispose(); }
  }

  Future<void> _editGroup(BuildContext context, String id, Map<String, dynamic> data, String actorId, String municipalityName) async {
    final number = TextEditingController(text: '${data['number'] ?? data['groupNumber'] ?? data['groupId'] ?? ''}');
    final name = TextEditingController(text: '${data['name'] ?? data['groupName'] ?? ''}');
    final status = ValueNotifier<String>('${data['status'] ?? 'active'}' == 'inactive' ? 'inactive' : 'active');
    final synthetic = data['_isSynthetic'] == true || id.isEmpty;
    try {
      final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: AppText(synthetic ? 'تسجيل مجموعة قديمة' : 'تعديل المجموعة'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: number, decoration: const InputDecoration(labelText: 'رقم المجموعة')),
          const SizedBox(height: 10), TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المجموعة')),
          const SizedBox(height: 10), ValueListenableBuilder<String>(valueListenable: status, builder: (_, value, __) => DropdownButtonFormField<String>(value: value, items: const [DropdownMenuItem(value: 'active', child: AppText('نشطة')), DropdownMenuItem(value: 'inactive', child: AppText('غير نشطة'))], onChanged: (v) => status.value = v ?? value, decoration: const InputDecoration(labelText: 'الحالة'))),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const AppText('إلغاء')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const AppText('حفظ'))],
      ));
      if (ok != true || !context.mounted) return;
      if (name.text.trim().isEmpty || number.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('اسم المجموعة ورقمها مطلوبان.'))); return;
      }
      final ref = synthetic ? FirebaseFirestore.instance.collection('operations').doc() : FirebaseFirestore.instance.collection('operations').doc(id);
      await ref.set({
        'id': ref.id, '_entity': 'group', 'name': name.text.trim(), 'groupName': name.text.trim(), 'title': name.text.trim(),
        'number': number.text.trim(), 'groupNumber': number.text.trim(), 'groupId': number.text.trim(),
        'status': status.value, 'isActive': status.value == 'active', 'isDeleted': false,
        'municipalityCoordinatorId': actorId, 'coordinatorId': actorId,
        'municipalityName': '${data['municipalityName'] ?? data['municipality'] ?? municipalityName}',
        'createdBy': '${data['createdBy'] ?? actorId}', 'updatedBy': actorId,
        if (synthetic) 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('تم حفظ المجموعة وتوحيد حقولها بنجاح.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: AppText('تعذر حفظ المجموعة: $e')));
    } finally { number.dispose(); name.dispose(); status.dispose(); }
  }

  Future<void> _confirmDeleteGroup(BuildContext context, String id, String number, String name, int count, bool synthetic) async {
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const AppText('تأكيد حذف المجموعة'),
      content: AppText('سيتم حذف سجل المجموعة «${name.isEmpty ? number : name}». عدد العمال النشطين المرتبطين بها: $count. لن تُحذف سجلات العمال تلقائيًا. هل تريد المتابعة؟'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const AppText('إلغاء')), TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const AppText('حذف', style: TextStyle(color: Colors.red)))],
    ));
    if (confirmed != true || !context.mounted) return;
    try {
      await FirebaseFirestore.instance.collection('operations').doc(id).delete();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('تم حذف سجل المجموعة. لم يتم حذف العمال المرتبطين بها.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: AppText('تعذر حذف المجموعة: $e')));
    }
  }

  Future<void> _exportGroups(BuildContext context, {required String actorId, required String actorRole, required String scope, required bool csv}) async {
    try {
      final snap = await FirebaseFirestore.instance.collection('operations').limit(1500).get();
      final groupsByKey = <String, List<String>>{};
      for (final d in snap.docs) {
        final x = d.data();
        final entity = '${x['_entity'] ?? ''}';
        if (x['isDeleted'] == true || (actorRole == 'municipality_coordinator' && !_belongsToCoordinator(x, actorId, scope))) continue;
        if (entity == 'group') {
          final number = '${x['number'] ?? x['groupNumber'] ?? x['groupId'] ?? ''}'.trim();
          final name = '${x['name'] ?? x['groupName'] ?? number}'.trim();
          final key = (number.isNotEmpty ? number : name).toLowerCase();
          if (key.isEmpty) continue;
          groupsByKey[key] = [d.id, number, name, '${x['municipalityName'] ?? x['municipality'] ?? ''}', '${x['municipalityCoordinatorId'] ?? x['coordinatorId'] ?? ''}', '${x['status'] ?? 'active'}'];
        }
      }
      // Include legacy groups found in imported worker records even if the group
      // registry document was never created.
      for (final d in snap.docs) {
        final x = d.data();
        if ('${x['_entity'] ?? ''}' != 'worker' || x['isDeleted'] == true) continue;
        if (actorRole == 'municipality_coordinator' && !_belongsToCoordinator(x, actorId, scope)) continue;
        final number = '${x['groupId'] ?? x['groupNumber'] ?? x['group'] ?? ''}'.trim();
        if (number.isEmpty) continue;
        groupsByKey.putIfAbsent(number.toLowerCase(), () => ['', number, '${x['groupName'] ?? x['groupLabel'] ?? number}', '${x['municipalityName'] ?? x['municipality'] ?? ''}', '${x['municipalityCoordinatorId'] ?? x['coordinatorId'] ?? ''}', 'legacy']);
      }
      final rows = groupsByKey.values.toList();
      const headers = ['معرّف المجموعة', 'رقم المجموعة', 'اسم المجموعة', 'البلدية', 'معرّف المنسق', 'الحالة'];
      String? path;
      final stamp = DateTime.now().millisecondsSinceEpoch;
      if (csv) {
        String quote(String s) { final q = String.fromCharCode(34); return '$q${s.replaceAll(q, q + q)}$q'; }
        final content = '\uFEFF${[headers, ...rows].map((r) => r.map(quote).join(',')).join('\r\n')}';
        path = await saveExcelBytes(Uint8List.fromList(utf8.encode(content)), 'cleanops_groups_$stamp.csv');
      } else {
        final book = excel.Excel.createExcel();
        final sheet = book['Groups'];
        sheet.appendRow(headers.map(excel.TextCellValue.new).toList());
        for (final row in rows) { sheet.appendRow(row.map(excel.TextCellValue.new).toList()); }
        final bytes = book.encode();
        if (bytes != null && bytes.isNotEmpty) path = await saveExcelBytes(Uint8List.fromList(bytes), 'cleanops_groups_$stamp.xlsx');
      }
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: AppText(path == null ? 'تعذر حفظ ملف التصدير على هذا الجهاز.' : 'تم تصدير ${rows.length} مجموعة إلى: $path')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: AppText('فشل تصدير المجموعات: $e')));
    }
  }

  Future<void> _importGroups(BuildContext context, String actorId, String actorRole, String municipalityName) async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'csv'], withData: true);
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) throw Exception('الملف فارغ أو تعذر قراءته.');
      List<List<String>> rows;
      if (file.name.toLowerCase().endsWith('.csv')) {
        final decoded = utf8.decode(bytes, allowMalformed: true).replaceFirst('\uFEFF', '');
        rows = decoded.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).map((l) => l.split(RegExp(r'[,;\t]')).map((v) => v.trim().replaceAll(RegExp(r'^"|"$'), '')).toList()).toList();
      } else {
        final book = excel.Excel.decodeBytes(bytes);
        if (book.tables.isEmpty) throw Exception('لا توجد ورقة عمل قابلة للقراءة.');
        rows = book.tables.values.first.rows.map((r) => r.map((c) => c?.value == null ? '' : '${c!.value}'.trim()).toList()).toList();
      }
      if (rows.isEmpty) throw Exception('الملف لا يحتوي على بيانات.');
      String norm(String s) => s.replaceAll('\uFEFF', '').replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('ة', 'ه').trim().toLowerCase();
      final header = rows.take(30).toList().asMap().entries.firstWhere((entry) => entry.value.any((v) => ['رقم المجموعة','المجموعة','group number','group no','number','اسم المجموعة','group name','name'].contains(norm(v))), orElse: () => const MapEntry<int, List<String>>(-1, <String>[]));
      if (header.key < 0) throw Exception('لم يتم العثور على صف العناوين. استخدم عمود «رقم المجموعة» و/أو «اسم المجموعة».');
      final h = <String, int>{};
      for (var i = 0; i < header.value.length; i++) {
        final v = norm(header.value[i]);
        if (['رقم المجموعة','المجموعة','group number','group no','number','group'].contains(v)) h.putIfAbsent('number', () => i);
        if (['اسم المجموعة','group name','name'].contains(v)) h.putIfAbsent('name', () => i);
        if (['البلدية','اسم البلدية','municipality','municipality name'].contains(v)) h.putIfAbsent('municipality', () => i);
      }
      if (!h.containsKey('number') && !h.containsKey('name')) throw Exception('أضف عمود رقم المجموعة أو اسم المجموعة.');
      final existing = await FirebaseFirestore.instance.collection('operations').where('_entity', isEqualTo: 'group').limit(1500).get();
      final existingKeys = existing.docs.map((d) => '${d.data()['number'] ?? d.data()['groupNumber'] ?? d.data()['groupId'] ?? ''}'.trim().toLowerCase()).where((v) => v.isNotEmpty).toSet();
      var created = 0; var skipped = 0;
      final batch = FirebaseFirestore.instance.batch();
      for (var i = header.key + 1; i < rows.length; i++) {
        final row = rows[i];
        String value(String key) { final index = h[key]; return index == null || index >= row.length ? '' : row[index].trim(); }
        final number = value('number');
        final name = value('name').isNotEmpty ? value('name') : number;
        final groupNumber = number.isNotEmpty ? number : name;
        if (groupNumber.isEmpty || name.isEmpty) { skipped++; continue; }
        if (existingKeys.contains(groupNumber.toLowerCase())) { skipped++; continue; }
        final municipality = value('municipality').isNotEmpty ? value('municipality') : municipalityName;
        final ref = FirebaseFirestore.instance.collection('operations').doc();
        batch.set(ref, {'id': ref.id, '_entity': 'group', 'name': name, 'groupName': name, 'title': name, 'number': groupNumber, 'groupNumber': groupNumber, 'groupId': groupNumber, 'municipalityCoordinatorId': actorId, 'coordinatorId': actorId, 'municipalityName': municipality, 'municipality': municipality, 'status': 'active', 'isActive': true, 'isDeleted': false, 'createdBy': actorId, 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
        existingKeys.add(groupNumber.toLowerCase()); created++;
      }
      if (created > 0) await batch.commit();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: AppText('اكتمل استيراد المجموعات: أضيف $created، وتُجاوز $skipped (فارغة أو مكررة).')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: AppText('فشل استيراد المجموعات: $e'), duration: const Duration(seconds: 8)));
    }
  }
}

class ExecutiveReportPage extends StatelessWidget {
  const ExecutiveReportPage({super.key});
  @override
  Widget build(BuildContext context) {
    final u = context.watch<AuthService>().currentUser!;
    return Scaffold(
      appBar: AppBar(title: const AppText('التقرير التنفيذي')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: context.read<OperationsAdminService>().liveOperationalSnapshot(u),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final x = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              AiHero(user: u, eyebrow: 'EXECUTIVE REPORT', title: 'ملخص تنفيذي', subtitle: 'الأرقام الحالية مأخوذة من Firestore وقت إنشاء التقرير.'),
              const SizedBox(height: 12),
              AiSectionCard(
                title: 'المؤشرات التشغيلية', feature: 'reports',
                child: Wrap(spacing: 10, runSpacing: 10, children: [
                  _HubMetric('المستخدمون النشطون', '${x['activeUsers']}', 'users'),
                  _HubMetric('العمال', '${x['workers']}', 'workers'),
                  _HubMetric('المشرفون', '${x['supervisors']}', 'workers'),
                  _HubMetric('المجموعات', '${x['groups']}', 'operations'),
                  _HubMetric('الترحيلات', '${x['trips']}', 'trips'),
                  _HubMetric('الطوارئ', '${x['emergencies']}', 'emergency'),
                  _HubMetric('التقارير', '${x['reports']}', 'reports'),
                  _HubMetric('المكبات الحرجة', '${x['criticalDumpsites']}', 'dumpsite'),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

class SecurityCenterPage extends StatelessWidget {
  const SecurityCenterPage({super.key});
  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser!;
    final auth = context.read<AuthService>();
    return Scaffold(
      appBar: AppBar(title: const AppText('مركز الأمان')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
        AiSectionCard(title: 'الحساب الحالي', feature: 'permissions', child: Column(children: [
          _kv('اسم المستخدم', user.username),
          _kv('الدور', roleNames[user.role] ?? user.role),
          _kv('الحالة', user.isActive ? 'نشط' : 'غير نشط'),
          _kv('كلمة المرور', 'لا تُحفظ داخل Firestore أو LocalStore'),
        ])),
        const SizedBox(height: 12),
        AiSectionCard(title: 'إعادة كلمة المرور', feature: 'users', subtitle: 'يُرسل رابط إعادة التعيين إلى البريد المرتبط بالحساب', child: FilledButton.icon(
          onPressed: () async {
            final ok = await auth.requestPasswordReset(user.username);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: AppText(ok ? 'تم إرسال رابط إعادة التعيين.' : (auth.error ?? 'تعذر إرسال الرابط.'))));
          },
          icon: const Icon(Icons.lock_reset_rounded),
          label: const AppText('إرسال رابط إعادة التعيين'),
        )),
        const SizedBox(height: 12),
        const AiSectionCard(title: 'سياسة الأمان', feature: 'permissions', child: Column(children: [
          ListTile(leading: Icon(Icons.password_rounded, color: aiGreen), title: AppText('كلمات المرور'), subtitle: AppText('تُدار عبر Firebase Authentication ولا تُكتب في Firestore.')),
          ListTile(leading: Icon(Icons.cloud_off_rounded, color: aiCyan), title: AppText('Offline'), subtitle: AppText('لا يتم تخزين كلمة المرور في التخزين المحلي.')),
          ListTile(leading: Icon(Icons.notifications_off_rounded, color: aiCyan), title: AppText('FCM'), subtitle: AppText('غير مستخدم في منظومة الرسائل الحالية.')),
        ])),
      ]),
    );
  }
}

class FilesCenterPage extends StatefulWidget {
  const FilesCenterPage({super.key});
  @override State<FilesCenterPage> createState() => _FilesCenterPageState();
}

class _FilesCenterPageState extends State<FilesCenterPage> {
  bool busy = true;
  String? error;
  final files = <Reference>[];
  Future<void> load() async {
    setState(() { busy = true; error = null; files.clear(); });
    try {
      final storage = FirebaseStorage.instance;
      Future<void> collect(Reference ref, int depth) async {
        if (files.length >= 100 || depth > 3) return;
        final result = await ref.listAll();
        files.addAll(result.items.take(100 - files.length));
        for (final prefix in result.prefixes) {
          if (files.length >= 100) break;
          await collect(prefix, depth + 1);
        }
      }
      for (final root in ['photos', 'audio']) {
        if (files.length >= 100) break;
        await collect(storage.ref(root), 0);
      }
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => busy = false);
  }
  @override void initState() { super.initState(); unawaited(load()); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('مركز الملفات'), actions: [IconButton(onPressed: busy ? null : load, icon: const Icon(Icons.refresh_rounded))]),
    body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
      AiSectionCard(title: 'الملفات المرفوعة', subtitle: 'تُقرأ من Firebase Storage • الصور والتسجيلات الميدانية', feature: 'reports', child: busy
        ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
        : error != null
          ? AppText('تعذر تحميل الملفات: $error')
          : files.isEmpty
            ? const AppText('لا توجد ملفات مرفوعة بعد.')
            : Column(children: files.map((r) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: AiFeatureIcon(r.fullPath.startsWith('audio/') ? 'messages' : 'reports', size: 14),
                title: AppText(r.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                subtitle: AppText(r.fullPath, style: const TextStyle(fontSize: 9, color: cleanOpsMuted), overflow: TextOverflow.ellipsis),
                onTap: () async { final url = await r.getDownloadURL(); if (!context.mounted) return; await showDialog(context: context, builder: (_) => AlertDialog(title: const AppText('رابط الملف'), content: SelectableText(url), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const AppText('إغلاق'))])); },
              )).toList()),
      ),
    ]),
  );
}

class AuditLogPage extends StatelessWidget {
  const AuditLogPage({super.key});
  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance.collection('audit').orderBy('timestamp', descending: true).limit(200).snapshots();
    return Scaffold(
      appBar: AppBar(title: const AppText('سجل التدقيق')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: AppText('تعذر تحميل سجل التدقيق: ${snap.error}')));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: AppText('لا توجد عمليات مسجلة بعد.'));
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              AiSectionCard(
                title: 'سجل التدقيق', subtitle: 'قراءة فقط • Level 4', feature: 'permissions',
                child: Column(children: docs.map((d) {
                  final x = d.data();
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const AiFeatureIcon('permissions', size: 14),
                    title: AppText('${x['operation'] ?? 'عملية'}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                    subtitle: AppText('المنفذ: ${x['actorId'] ?? '-'} • الهدف: ${x['targetId'] ?? '-'}', style: const TextStyle(fontSize: 9, color: cleanOpsMuted)),
                  );
                }).toList()),
              ),
            ],
          );
        },
      ),
    );
  }
}

Widget _kv(String a,String b)=>ListTile(contentPadding:EdgeInsets.zero,title:AppText(a,style:const TextStyle(fontSize:11)),trailing:AppText(b,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w800,color:aiCyan)));
