import '../widgets/app_navigation_bar.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/fast_smart_search.dart';
import '../../core/services/search_page_loader.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../core/localization.dart';
import '../widgets/app_design.dart';
import '../../core/constants/app_constants.dart';

class EquipmentSearchScreen extends StatefulWidget {
  final String? focusRecordId;
  final String focusCollection;
  const EquipmentSearchScreen({super.key, this.focusRecordId, this.focusCollection = 'equipment'});
  @override State<EquipmentSearchScreen> createState() => _EquipmentSearchScreenState();
}

class _EquipmentSearchScreenState extends State<EquipmentSearchScreen> {
  final search = TextEditingController();
  String filter = 'all';
  Timer? _debounce;
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  String? error;

  @override void initState() { super.initState(); _load(); search.addListener(_changed); }
  @override void dispose() { _debounce?.cancel(); search.dispose(); super.dispose(); }
  void _changed() { _debounce?.cancel(); _debounce = Timer(const Duration(milliseconds: 250), () => setState(() {})); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final db = FirebaseFirestore.instance;
      final actor = context.read<AuthService>().currentUser;
      if (actor == null || !actor.can('operations', 'view') ||
          !const ['municipality_coordinator', 'jsc_coordinator', 'donor_manager'].contains(actor.role)) {
        throw StateError('لا توجد صلاحية لعرض المعدات.');
      }
      final unique = <String, Map<String, dynamic>>{};
      final sources = widget.focusRecordId == null
          ? const ['operations', 'equipment']
          : [widget.focusCollection];
      var failures = 0;
      for (final source in sources) {
        try {
        if (!const ['operations', 'equipment'].contains(source)) continue;
        Query<Map<String, dynamic>> query = db.collection(source);
        if (source == 'operations') {
          query = query.where('_entity', whereIn: ['heavy_machinery', 'equipment']);
        } else if (actor.role == 'municipality_coordinator') {
          query = query.where('municipalityCoordinatorId', isEqualTo: actor.id);
        }
        if (widget.focusRecordId != null) {
          query = query.where(FieldPath.documentId, isEqualTo: widget.focusRecordId);
        }
        final ordered = query.orderBy(FieldPath.documentId);
        await for (final page in readSearchPages<QueryDocumentSnapshot<Map<String, dynamic>>>(
          isActive: () => mounted && context.read<AuthService>().currentUser?.id == actor.id,
          fetchPage: (after, size) async {
            Query<Map<String, dynamic>> next = ordered.limit(size);
            if (after != null) next = next.startAfterDocument(after);
            return (await next.get().timeout(const Duration(seconds: 15))).docs;
          },
        )) {
          for (final doc in page) {
            final data = {...doc.data(), 'id': doc.id};
            if (data['isDeleted'] == true || data['status'] == 'deleted') continue;
            final scope = actor.scope.trim();
            final unrestrictedCouncil = actor.role == 'jsc_coordinator' &&
                (scope.isEmpty || scope == 'all' || scope == 'assigned_only');
            final owns = '${data['municipalityCoordinatorId'] ?? data['coordinatorId'] ?? ''}' == actor.id;
            final field = actor.role == 'jsc_coordinator'
                ? data['councilName'] ?? data['councilId'] ?? data['municipalityName']
                : data['municipalityName'] ?? data['municipality'] ?? data['municipalityId'];
            final inScope = scope.isNotEmpty && scope != 'all' && scope != 'assigned_only' &&
                FastSmartSearch.normalize('$field') == FastSmartSearch.normalize(scope);
            if (actor.role != 'donor_manager' && !unrestrictedCouncil && !owns && !inScope) continue;
            unique['$source/${doc.id}'] = data;
          }
          if (mounted) setState(() => rows = unique.values.toList());
        }
        } catch (_) {
          failures++;
        }
      }
      if (mounted) setState(() { rows = unique.values.toList(); loading = false;
        if (failures > 0) error = 'تعذر تحديث بعض مصادر المعدات؛ النتائج المحملة متاحة.';
      });
    } catch (e) {
      if (mounted) setState(() { error = '$e'; loading = false; });
    }
  }

  // Normalize Arabic spelling and diacritics for incremental search.
  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
      .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'[^\u0621-\u064A\u0660-\u0669a-z0-9]+'), ' ')
      .trim();

  bool _matches(Map<String, dynamic> x) {
    final q = _normalize(search.text);
    final status = '${x['status'] ?? x['machineStatus'] ?? ''}'.toLowerCase();
    if (filter != 'all' && status != filter) return false;
    if (q.isEmpty) return true;
    final hay = [x['id'], x['name'], x['machine'], x['equipmentName'], x['type'], x['model'], x['plateNumber'], x['municipality'], x['municipalityName'], x['groupName'], x['status'], x['notes'], x['location']]
        .map((v) => _normalize('$v')).join(' ');
    return hay.contains(q) || q.split(' ').every((word) => word.isNotEmpty && hay.contains(word));
  }

  @override Widget build(BuildContext context) {
    final visible = rows.where(_matches).toList();
    return Directionality(
      textDirection: context.watch<LocaleController>().isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(bottom: const AppNavigationBar(), title: const AppText('بحث المعدات'), actions: [IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh_rounded))]),
        body: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 120), children: [
          AiSectionCard(
            title: 'مركز بحث المعدات', subtitle: 'ابحث بالاسم أو النوع أو الموديل أو اللوحة أو البلدية أو المجموعة.', feature: 'operations',
            child: Column(children: [
              TextField(controller: search, decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: tr('ابحث عن معدة...'), suffixIcon: search.text.isEmpty ? null : IconButton(onPressed: search.clear, icon: const Icon(Icons.clear_rounded)))),
              const SizedBox(height: 10),
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                _filter('all', 'الكل'), _filter('active', 'نشطة'), _filter('maintenance', 'صيانة'), _filter('inactive', 'متوقفة'),
              ])),
            ]),
          ),
          const SizedBox(height: 12),
          if (error != null && visible.isNotEmpty) AppText(error!),
          if (loading) const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()))
          else if (error != null && visible.isEmpty) AiSectionCard(title: 'تعذر تحميل المعدات', feature: 'emergency', child: AppText(error!))
          else if (visible.isEmpty) const AiSectionCard(title: 'لا توجد نتائج', subtitle: 'جرّب كلمة بحث أخرى أو غيّر الفلتر.', feature: 'operations', child: SizedBox.shrink())
          else AiSectionCard(title: '${visible.length} نتيجة', subtitle: 'بيانات المعدات التشغيلية', feature: 'operations', child: Column(children: visible.map(_tile).toList())),
        ]),
      ),
    );
  }

  Widget _filter(String value, String label) => Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: ChoiceChip(label: AppText(label), selected: filter == value, onSelected: (_) => setState(() => filter = value)));

  Widget _tile(Map<String, dynamic> x) {
    final title = '${x['name'] ?? x['machine'] ?? x['equipmentName'] ?? x['type'] ?? 'معدة'}'.trim();
    final subtitle = [x['model'], x['plateNumber'], x['municipalityName'] ?? x['municipality'], x['groupName']]
        .where((v) => '$v'.trim().isNotEmpty && '$v' != 'null').join(' • ');
    final status = '${x['status'] ?? x['machineStatus'] ?? 'غير محدد'}';
    final color = status.toLowerCase() == 'active' || status == 'نشطة' ? Colors.green : status.toLowerCase() == 'maintenance' || status == 'صيانة' ? Colors.orange : cleanOpsMuted;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(13), border: Border.all(color: color.withOpacity(.25))), child: Icon(Icons.construction_rounded, color: color)),
      title: AppText(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: AppText(subtitle.isEmpty ? 'لا توجد تفاصيل إضافية' : subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: _status(status, color),
    );
  }
  Widget _status(String s, Color c) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: c.withOpacity(.1), borderRadius: BorderRadius.circular(15)), child: AppText(s, style: TextStyle(color: c, fontSize: 9, fontWeight: FontWeight.w800)));
}
