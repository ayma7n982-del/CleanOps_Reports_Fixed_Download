import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../core/models/core_models.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/container_service.dart';
import '../../core/services/data_service.dart';
import '../screens/global_search.dart';
import '../screens/live_operations_map.dart';
import '../screens/enterprise_operations_hub.dart' show SyncCenterPage, AlertsCenterPage;
import '../screens/container_management.dart';
import 'app_design.dart';
import 'eco_shortcuts.dart';
import '../../core/constants/app_constants.dart';

/// Presentation-only workspace: does not modify Firebase rules or data writes.
class WorkspaceAction {
  final String id, title;
  final IconData icon;
  final VoidCallback onTap;
  const WorkspaceAction(this.id, this.title, this.icon, this.onTap);
}

class WorkspaceOverview extends StatefulWidget {
  final List<WorkspaceAction> actions;
  const WorkspaceOverview({super.key, required this.actions});
  @override
  State<WorkspaceOverview> createState() => _WorkspaceOverviewState();
}

class _WorkspaceOverviewState extends State<WorkspaceOverview> {
  String _loadedUid = '';
  List<String> _order = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.read<AuthService>().currentUser;
    if (user == null || user.id == _loadedUid) return;
    _loadedUid = user.id;
    final raw = context.read<DataService>().store.box.get('workspace_order_${user.id}');
    try {
      final value = jsonDecode('${raw ?? '[]'}');
      _order = value is List ? value.map((x) => '$x').toList() : [];
    } catch (_) { _order = []; }
  }

  List<WorkspaceAction> get orderedActions {
    final items = [...widget.actions];
    items.sort((a,b) {
      final ia = _order.indexOf(a.id), ib = _order.indexOf(b.id);
      final aa = ia < 0 ? _order.length + widget.actions.indexOf(a) : ia;
      final bb = ib < 0 ? _order.length + widget.actions.indexOf(b) : ib;
      return aa.compareTo(bb);
    });
    return items;
  }

  void move(String id, int by) {
    final ids = orderedActions.map((x) => x.id).toList();
    final old = ids.indexOf(id), next = old + by;
    if (old < 0 || next < 0 || next >= ids.length) return;
    final value = ids.removeAt(old);
    ids.insert(next,value);
    setState(() => _order = ids);
    final user = context.read<AuthService>().currentUser;
    if (user != null) {
      context.read<DataService>().store.box.put(
        'workspace_order_${user.id}',jsonEncode(ids));
    }
  }

  bool visibleOperation(Map<String,dynamic> x, AppUser user) {
    if (x['isDeleted'] == true) return false;
    if (user.role == 'donor_manager' || user.role == 'jsc_coordinator') return true;
    if (user.role == 'municipality_coordinator') return
      x['municipalityCoordinatorId'] == user.id ||
      x['requestedBy'] == user.id || x['userId'] == user.id;
    return (user.groupId != null && user.groupId!.isNotEmpty &&
      x['groupId'] == user.groupId) ||
      x['reportedBy'] == user.id || x['userId'] == user.id;
  }

  bool visibleContainer(ContainerItem x, AppUser user) {
    if (user.role == 'donor_manager' || user.role == 'jsc_coordinator') return true;
    if (user.role == 'municipality_coordinator') return x.municipalityId == user.id;
    return user.groupId != null && x.groupId == user.groupId;
  }

  void _open(Widget page) => Navigator.push(context,
    MaterialPageRoute(builder: (_) => page));

  void _openEmergency(AppUser user) {
    // Viewing an existing alert must never open the create-SOS form.
    // Field personnel only see incidents from their assigned group.
    if (user.role == 'group_supervisor' || user.role == 'worker') {
      _open(_FieldAlertsPage(userId: user.id, groupId: user.groupId ?? ''));
    } else {
      _open(const AlertsCenterPage());
    }
  }

  void openMap(AppUser user, List<ContainerItem> scoped) {
    final screen = user.role == 'donor_manager' || user.role == 'jsc_coordinator'
      ? const LiveOperationsMapScreen()
      : _ScopedContainersMap(containers:scoped);
    Navigator.push(context,MaterialPageRoute(builder:(_)=>screen));
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    if (user == null) return const SizedBox.shrink();
    final service = context.watch<DataService>();
    final scoped = context.watch<ContainerService>().containers
      .where((x)=>visibleContainer(x,user)).toList();
    // The DataService cache also contains optimistic offline writes. A queued
    // record is not server-confirmed and must not enter "real activity".
    final pendingIds = <String>{};
    for (final item in service.queue) {
      if (item.ownerUid != user.id) continue;
      try {
        final payload = jsonDecode(item.payload);
        if (payload is Map && payload['id'] != null) {
          pendingIds.add('${payload['id']}');
        }
      } catch (_) { /* Queue diagnostics report malformed entries. */ }
    }
    final ops = service.operations.where((x)=>visibleOperation(x,user)).toList();
    final confirmed = ops.where((x)=> !pendingIds.contains('${x['id']}')).toList();
    final emergencies = ops.where((x)=> x['_entity']=='emergency' &&
      !['secured','closed','resolved'].contains(x['status'])).length;
    final critical = scoped.where((x)=>x.status=='full' ||
      x.issueStatus=='reported').length;
    final pending = service.queue.where((x)=>x.ownerUid==user.id).length;
    final dated = confirmed.where((x)=>x['createdAt'] is String &&
      DateTime.tryParse(x['createdAt'])!=null).toList()
      ..sort((a,b)=>'${b['createdAt']}'.compareTo('${a['createdAt']}'));
    final now=DateTime.now();
    final today = dated.where((x) {
      final d=DateTime.tryParse('${x['createdAt']}')?.toLocal();
      return d!=null && d.year==now.year && d.month==now.month && d.day==now.day;
    }).length;
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      AiSectionCard(title:'يتطلب إجراءك',feature:'emergency',
        subtitle:'بحسب السجلات المتاحة وصلاحيات حسابك',
        child:Column(children:[
          if (user.can('emergency', 'view'))
            ListTile(leading:const Icon(Icons.warning_amber),
              title:Text('بلاغات SOS مفتوحة: $emergencies'),
              trailing:const Icon(Icons.chevron_left),
              onTap:()=>_openEmergency(user)),
          if (user.can('containers', 'view'))
            ListTile(leading:const Icon(Icons.delete_sweep),
              title:Text('حاويات تحتاج متابعة: $critical'),
              trailing:const Icon(Icons.chevron_left),
              onTap:()=>_open(const ContainerManagementScreen())),
          if(pending>0) ListTile(leading:const Icon(Icons.sync_problem),
            title:Text('بانتظار تأكيد الخادم: $pending'),
            subtitle:const Text('عمليات محفوظة محليًا ولم يتأكد تنفيذها'),
            trailing:const Icon(Icons.chevron_left),
            onTap:()=>_open(const SyncCenterPage())),
        ])),
      const SizedBox(height:12),
      if (user.can('operations', 'view') || user.can('reports', 'view'))
      AiSectionCard(title:'البحث والأوامر',feature:'dashboard',
        child:FilledButton.tonalIcon(icon:const Icon(Icons.search),
          label:const Text('البحث الذكي في السجلات والعمليات'),
          onPressed:()=>Navigator.push(context,MaterialPageRoute(
            builder:(_)=>const GlobalSearchPage())))),
      const SizedBox(height:12),
      AiSectionCard(title:'اختصاراتي',feature:'operations',
        subtitle:'يمكن ترتيب الاختصارات؛ يُحفظ الترتيب على الجهاز لكل مستخدم',
        child:Column(children:[
          EcoShortcutGrid(
            cards: [
              for (final action in orderedActions)
                EcoShortcutCard(
                  feature: action.id,
                  icon: action.icon,
                  title: action.title,
                  subtitle: '',
                  onTap: action.onTap,
                ),
            ],
          ),
          ExpansionTile(title:const Text('تعديل ترتيب الاختصارات'),children:[
            for(final action in orderedActions) ListTile(
              title:Text(action.title),
              trailing:Wrap(children:[
                IconButton(icon:const Icon(Icons.arrow_upward),
                  tooltip:'للأعلى',onPressed:()=>move(action.id,-1)),
                IconButton(icon:const Icon(Icons.arrow_downward),
                  tooltip:'للأسفل',onPressed:()=>move(action.id,1)),
              ])),
          ]),
        ])),
      const SizedBox(height:12),
      if (user.can('containers', 'view') ||
          (user.can('dumpsite', 'view') &&
           (user.role == 'donor_manager' || user.role == 'jsc_coordinator')))
      AiSectionCard(title:'الخريطة التشغيلية',feature:'dumpsite',
        child:ListTile(leading:const Icon(Icons.map_outlined),
          title:const Text('عرض المواقع على خريطة جوية'),
          subtitle:Text(user.role=='group_supervisor' ||
            user.role=='municipality_coordinator'
            ? 'حاويات نطاقك فقط، دون توسيع صلاحيات Firebase'
            : 'الخريطة الحية وفق صلاحياتك'),
          trailing:const Icon(Icons.chevron_left),
          onTap:()=>openMap(user,scoped))),
      const SizedBox(height:12),
      AiSectionCard(title:'ملخص اليوم',feature:'reports',
        subtitle:'عدد السجلات المؤرخة المتاحة محليًا اليوم',
        child:Column(children:[
          ListTile(title:Text('سجلات اليوم: $today'),
            subtitle:Text('آخر جلب للبيانات: ${service.lastDataRefresh.isEmpty ? 'غير مؤكد' : service.lastDataRefresh}')),
          ListTile(title:Text('عمليات معلقة: $pending'),
            subtitle:Text(service.automaticSyncStatus),
            trailing:const Icon(Icons.chevron_left),
            onTap:()=>_open(const SyncCenterPage())),
        ])),
      const SizedBox(height:12),
      AiSectionCard(title:'آخر النشاط الحقيقي',feature:'operations',
        subtitle:'من سجل العمليات المحفوظ، وليس بيانات تجريبية',
        child:dated.isEmpty
          ? const Text('لا توجد سجلات مؤرخة ضمن نطاق حسابك.')
          : Column(children:[
              for(final x in dated.take(5)) ListTile(dense:true,
                leading:const Icon(Icons.history),
                title:Text('${x['_entity'] ?? 'عملية'} • ${x['id'] ?? ''}'),
                subtitle:Text('${x['createdAt']}'),
                trailing:const Icon(Icons.info_outline),
                onTap:()=>showDialog<void>(context:context,builder:(ctx)=>
                  AlertDialog(
                    title:const Text('تفاصيل سجل النشاط'),
                    content:SingleChildScrollView(child:SelectableText(
                      'النوع: ${x['_entity'] ?? 'عملية'}\n'
                      'الرقم: ${x['id'] ?? ''}\n'
                      'التاريخ: ${x['createdAt'] ?? ''}\n'
                      'الحالة: ${x['status'] ?? 'غير محددة'}\n'
                      'منفذ الإجراء: ${x['userId'] ?? x['requestedBy'] ?? x['reportedBy'] ?? 'غير محدد'}',
                    )),
                    actions:[TextButton(onPressed:()=>Navigator.pop(ctx),
                      child:const Text('إغلاق'))],
                  ))),
            ])),
    ]);
  }
}

class _ScopedContainersMap extends StatelessWidget {
  final List<ContainerItem> containers;
  const _ScopedContainersMap({required this.containers});
  @override
  Widget build(BuildContext context) {
    final valid=containers.where((c)=>c.latitude>=-90 && c.latitude<=90 &&
      c.longitude>=-180 && c.longitude<=180 &&
      (c.latitude!=0 || c.longitude!=0)).toList();
    return Scaffold(appBar:AppBar(title:const Text('خريطة حاويات نطاقي')),
      body:valid.isEmpty
        ? const Center(child:Text('لا توجد حاويات بإحداثيات متاحة ضمن نطاقك'))
        : FlutterMap(options:MapOptions(
            initialCenter:LatLng(valid.first.latitude,valid.first.longitude),
            initialZoom:12),
          children:[
            TileLayer(urlTemplate:'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
              userAgentPackageName:'com.solidwaste.solid_waste_operations'),
            MarkerLayer(markers:[
              for(final c in valid) Marker(
                point:LatLng(c.latitude,c.longitude),width:46,height:46,
                child:Tooltip(message:'${c.locationName} • ${c.status}',
                  child:Icon(Icons.delete_rounded,size:35,
                    color:c.status=='full'?Colors.red:Colors.green))),
            ]),
            RichAttributionWidget(attributions:[
              TextSourceAttribution('Esri, Maxar, Earthstar Geographics and GIS User Community'),
            ]),
          ]));
  }
}


/// Read-only incident inbox; the red SOS shortcut remains the separate create
/// action. Uses only group-scoped operations already loaded by DataService.
class _FieldAlertsPage extends StatelessWidget {
  final String userId;
  final String groupId;
  const _FieldAlertsPage({required this.userId, required this.groupId});

  @override
  Widget build(BuildContext context) {
    final items = context.watch<DataService>().operations.where((item) {
      if (item['_entity'] != 'emergency' || item['isDeleted'] == true) {
        return false;
      }
      if (const ['closed', 'resolved', 'secured'].contains(item['status'])) {
        return false;
      }
      return groupId.isNotEmpty && (item['groupId'] == groupId ||
          item['reportedBy'] == userId);
    }).toList()
      ..sort((a, b) => '${b['createdAt'] ?? ''}'
          .compareTo('${a['createdAt'] ?? ''}'));
    return Scaffold(
      appBar: AppBar(title: const Text('بلاغات SOS لمجموعتي')),
      body: items.isEmpty
          ? const Center(child: Text('لا توجد بلاغات مفتوحة ضمن بيانات مجموعتك.'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  leading: const Icon(Icons.warning_amber_rounded, color: Colors.red),
                  title: Text('${item['street'] ?? item['locationName'] ?? 'بلاغ ميداني'}'),
                  subtitle: Text('الحالة: ${item['status'] ?? 'urgent'}'
                      ' • ${item['createdAt'] ?? 'بدون تاريخ'}'),
                  trailing: const Icon(Icons.info_outline),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('تفاصيل بلاغ الطوارئ'),
                      content: SelectableText(
                        'الموقع: ${item['street'] ?? 'غير محدد'}\n'
                        'الحالة: ${item['status'] ?? 'urgent'}\n'
                        'إحداثيات: ${item['latitude'] ?? '—'}, '
                        '${item['longitude'] ?? '—'}\n'
                        'المعرف: ${item['id'] ?? ''}'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('إغلاق'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
