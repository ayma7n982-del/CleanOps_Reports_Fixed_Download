import '../../core/services/trip_dumpsite.dart';
import '../widgets/trip_dumpsite_picker.dart';
import '../../core/services/feature_route_policy.dart';
import '../feature_navigation.dart';
import '../widgets/field_shortcuts.dart';
import '../widgets/app_navigation_bar.dart';
import '../widgets/decision_directive_banner.dart';
import '../../core/services/decision_route_policy.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../core/services/worker_roster.dart';
import '../../core/localization.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/config_service.dart';
import '../../core/services/data_service.dart';
import '../../core/services/image_service.dart';
import '../../core/services/report_service.dart';
import '../../core/services/trip_lifecycle.dart';
import '../../core/services/worker_ppe_checklist.dart';
import '../../core/services/operational_insights.dart';
import 'reports_center.dart';
import '../widgets/app_design.dart';
import '../widgets/operations_overview.dart';
import '../widgets/workspace_overview.dart';
import 'global_search.dart';

class Level1SupervisorScreen extends StatefulWidget {
  final String? initialAction;
  const Level1SupervisorScreen({super.key, this.initialAction});
  @override
  State<Level1SupervisorScreen> createState() => _Level1SupervisorState();
}

class _Level1SupervisorState extends State<Level1SupervisorScreen> {
  int tab = 0, remaining = 0;
  int get trips => _todayTripCount(false);
  int get alternativeTrips => _todayTripCount(true);

  int _todayTripCount(bool alternative) {
    final user = context.read<AuthService>().currentUser;
    final groupId = user?.groupId?.trim() ?? '';
    if (groupId.isEmpty) return 0;
    final now = DateTime.now();
    return context.read<DataService>().operations.where((trip) {
      if (trip['_entity'] != 'trip' || trip['isDeleted'] == true ||
          trip['groupId'] != groupId) return false;
      final started = DateTime.tryParse('${trip["startedAt"] ?? trip["createdAt"] ?? ""}')?.toLocal();
      final isAlternative = trip['alternative'] == true || trip['cartType'] == 'alternative';
      return started != null && started.year == now.year &&
          started.month == now.month && started.day == now.day &&
          isAlternative == alternative;
    }).length;
  }
  bool emergencyLock = false, recording = false, loadingWorkers = true;
  String? selectedDumpsiteId;
  List<TripDumpsite> tripDumpsites = [];
  bool loadingDumpsites = true, dumpsitesFromCache = false;
  String? dumpsiteError;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? dumpsiteUpdates;
  int tripTargetMinutes = 90;
  Position? reportPosition;
  String? audioPath;
  Timer? timer;
  StreamSubscription? sosUpdates;
  final street = TextEditingController();
  final issue = TextEditingController();
  final solution = TextEditingController();
  final quantity = TextEditingController();
  final recorder = AudioRecorder();
  final imageService = ImageService();
  final WorkerPpeChecklist ppe = WorkerPpeChecklist();
  final Map<String, String> attendanceStatus = {};
  bool savingAttendance = false;
  bool savingTrip = false;
  bool sendingEmergency = false;
  String emergencyStatus = '';
  String? activeEmergencyId;
  final Map<String, bool> tripPpe = {'بوت': false, 'قفازات': false, 'كمامة': false, 'قبعة': false, 'صديري': false};
  final List<String> tripPhotoPaths = [];
  List<Map<String, String>> workers = [];
  List<Map<String, String>>? _liveWorkers;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? rosterUpdates;
  int _rosterLoad = 0;
  String? workerLoadError;

  @override
  void initState() {
    super.initState();
    _watchWorkers();
    _watchTripDumpsites();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreEmergency());
    final groupId = context.read<AuthService>().currentUser?.groupId?.trim() ?? '';
    if (groupId.isNotEmpty) sosUpdates = FirebaseFirestore.instance.collection('operations')
        .where('groupId', isEqualTo: groupId).snapshots().listen((_) async {
      if (!mounted || activeEmergencyId == null) return;
      final data = context.read<DataService>();
      await data.refreshOperations();
      if (mounted) _refreshEmergencyStatus(data);
    }, onError: (Object error) {
      debugPrint('Emergency updates unavailable; retaining local state: $error');
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    sosUpdates?.cancel();
    rosterUpdates?.cancel();
    dumpsiteUpdates?.cancel();
    street.dispose();
    issue.dispose();
    solution.dispose();
    quantity.dispose();
    recorder.dispose();
    super.dispose();
  }

  void _watchTripDumpsites() {
    dumpsiteUpdates?.cancel();
    setState(() { loadingDumpsites = true; dumpsiteError = null; });
    // No arbitrary result cap: this is the complete active destination catalog.
    dumpsiteUpdates = FirebaseFirestore.instance.collection('dumpsites')
        .where('isActive', isEqualTo: true)
        .snapshots(includeMetadataChanges: true).listen((snapshot) {
      if (!mounted) return;
      final sites = snapshot.docs.map((doc) =>
          TripDumpsite.fromRecord(doc.id, doc.data())).whereType<TripDumpsite>()
          .toList()..sort((a, b) => a.name.compareTo(b.name));
      setState(() {
        tripDumpsites = sites;
        loadingDumpsites = false;
        dumpsitesFromCache = snapshot.metadata.isFromCache;
        dumpsiteError = null;
        if (!sites.any((site) => site.id == selectedDumpsiteId)) {
          selectedDumpsiteId = null;
        }
      });
    }, onError: (Object error) {
      if (!mounted) return;
      setState(() {
        loadingDumpsites = false;
        dumpsiteError = error is FirebaseException && error.code == 'permission-denied'
            ? 'تعذر الوصول إلى المكبات. يُرجى مراجعة المنسق لتحديث صلاحية قراءة وجهات النقلات.'
            : 'تعذر تحميل المكبات. تحقق من الاتصال وأعد المحاولة.';
      });
    });
  }

  Future<void> _restoreEmergency() async {
    if (!mounted) return;
    final user = context.read<AuthService>().currentUser;
    if (user == null) return;
    final data = context.read<DataService>();
    await data.refreshOperations();
    if (!mounted) return;
    final emergencies = data.operations.where((item) =>
      item['_entity'] == 'emergency' &&
      item['reportedBy'] == user.id &&
      item['groupId'] == user.groupId &&
      item['isDeleted'] != true &&
      item['status'] != 'closed' &&
      item['status'] != 'resolved').toList();
    if (emergencies.isEmpty) return;
    emergencies.sort((a, b) => '${b['createdAt'] ?? ''}'.compareTo('${a['createdAt'] ?? ''}'));
    setState(() {
      emergencyLock = true;
      activeEmergencyId = '${emergencies.first['id']}';
      emergencyStatus = 'يوجد بلاغ طوارئ مفتوح. تحقق من حالته قبل استئناف العمل.';
    });
    _refreshEmergencyStatus(data);
  }

  void _watchWorkers() {
    final user = context.read<AuthService>().currentUser;
    final group = user?.groupId?.trim() ?? '';
    if (user == null || group.isEmpty) {
      loadingWorkers = false;
      return;
    }
    final store = context.read<DataService>().store;
    if (store.hasWorkerRoster(user.id, group)) {
      _liveWorkers = store.cachedWorkerRoster(user.id, group)
          .map((r) => r.map((key, value) => MapEntry(key, '$value'))).toList();
    }
    unawaited(_loadWorkers());
    if (Firebase.apps.isEmpty) return;
    rosterUpdates = FirebaseFirestore.instance.collection('operations')
        .where('groupId', isEqualTo: group)
        .where('_entity', isEqualTo: 'worker')
        .snapshots(includeMetadataChanges: true).listen((snapshot) async {
      if (!mounted) return;
      // Replace the whole roster, including an empty server snapshot. Merging
      // here would keep a worker removed by a transfer in the old group's cache.
      if (snapshot.metadata.isFromCache && snapshot.docs.isEmpty &&
          _liveWorkers != null) return;
      final records = snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id});
      _liveWorkers = WorkerRoster.forGroup(records, group);
      workerLoadError = null;
      await store.saveWorkerRoster(user.id, group, _liveWorkers!);
      if (mounted) await _loadWorkers();
    }, onError: (Object error) {
      if (mounted) setState(() => workerLoadError =
          'تعذر تحديث كشف العمال. تظهر آخر نسخة محفوظة؛ سيُعاد الاتصال تلقائيًا.');
      debugPrint('Group worker roster listener failed: $error');
    });
  }

  Future<void> _loadWorkers() async {
    final generation = ++_rosterLoad;
    final user = context.read<AuthService>().currentUser;
    final group = user?.groupId?.trim() ?? '';
    final base = _liveWorkers ?? WorkerRoster.forGroup(
        context.read<DataService>().operations, group);
    final loaded = {for (final worker in base) worker['id']!: worker};
    if (user != null && group.isNotEmpty) {
      try {
        for (final worker in await temporaryDecisionWorkers(user)) {
          loaded.putIfAbsent(worker['id']!, () => worker);
        }
      } catch (error) {
        debugPrint('Temporary coverage roster is unavailable: $error');
      }
    }
    if (!mounted || generation != _rosterLoad) return;
    setState(() {
      workers = loaded.values.toList()
        ..sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
      final ids = loaded.keys.toSet();
      attendanceStatus.removeWhere((id, _) => !ids.contains(id));
      ppe.retainWorkers(ids);
      loadingWorkers = false;
    });
  }

  Future<void> _call(String phone) async {
    final normalized = phone.trim();
    if (normalized.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: normalized);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<Position?> _gps() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (_) {
      return await Geolocator.getLastKnownPosition();
    }
  }

  Future<void> _captureGps() async {
    final p = await _gps();
    if (!mounted) return;
    setState(() => reportPosition = p);
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('تعذر التقاط GPS. تأكد من تفعيل الموقع ومنح الإذن.')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: AppText('تم التقاط GPS: ${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)} • الدقة ${p.accuracy.round()} م')));
  }

  Future<void> _addTripPhoto() async {
    final config = context.read<ConfigService>();
    if (emergencyLock || tripPhotoPaths.length >= 3) return;
    try {
      final paths = await imageService.pickTripPhotos(targetKb: 500, remainingSlots: 3 - tripPhotoPaths.length, context: context);
      if (paths.isEmpty || !mounted) return;
      setState(() => tripPhotoPaths.addAll(paths));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('تمت إضافة صورة للنقلة.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: AppText('تعذر إضافة الصورة: $e')));
    }
  }

  void _removeTripPhoto(String path) {
    setState(() => tripPhotoPaths.remove(path));
    try { File(path).delete(); } catch (_) {}
  }

  Future<void> _takePhoto(String phase) async {
    final u = context.read<AuthService>().currentUser;
    final c = context.read<ConfigService>();
    if (c.stageFrozen) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('المرحلة مجمّدة — التعديلات التشغيلية مقفلة')));
      return;
    }
    if (u == null || !c.streetPhotosEnabled || !u.can('streets', 'create') || emergencyLock) return;
    final id = '${DateTime.now().millisecondsSinceEpoch}_${phase}_${u.id}';
    try {
      final localPath = await imageService.pickCompressLocal(targetKb: c.imageTargetKb, context: context);
      final p = await _gps();
      if (localPath != null) {
        final d = context.read<DataService>();
        await d.enqueue('street_photo', 'create', {
          'id': id,
          'street': street.text.trim(),
          'phase': phase,
          'localAttachmentPath': localPath,
          'attachmentType': 'image',
          'userId': u.id,
          'latitude': p?.latitude,
          'longitude': p?.longitude,
          'caption': ReportService(d).autoCaption(phase: phase == 'قبل' ? 'before' : 'after', streetName: street.text.trim()),
          'createdAt': DateTime.now().toIso8601String(),
          'isDeleted': false,
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: AppText(localPath == null ? 'لم يتم التقاط الصورة.' : 'تم حفظ صورة $phase محليًا وستتم مزامنتها تلقائيًا عند توفر الاتصال.'),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: AppText('تعذر حفظ الصورة: $e')));
    }
  }

  Future<void> _registerTrip(bool alternative) async {
    final u = context.read<AuthService>().currentUser;
    final config = context.read<ConfigService>();
    if (config.stageFrozen) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('المرحلة مجمّدة — التعديلات التشغيلية مقفلة')));
      return;
    }
    if (u == null || emergencyLock || savingTrip || !u.can('trips', 'create')) return;
    if ((u.groupId ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('يجب ربط المشرف بمجموعة قبل تسجيل النقلة.')));
      return;
    }
    if (double.tryParse(quantity.text.trim()) == null || double.parse(quantity.text.trim()) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('أدخل كمية صحيحة أكبر من صفر.')));
      return;
    }
    if (street.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('أدخل موقع أو شارع جمع النفايات.')));
      return;
    }
    if (loadingDumpsites || dumpsiteError != null ||
        !tripDumpsites.any((site) => site.id == selectedDumpsiteId)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('اختر المكب أو نقطة التجميع قبل تسجيل النقلة.')));
      return;
    }
    if (config.ppeEnabled && !tripPpe.values.every((v) => v)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('لا يمكن اعتماد النقلة قبل تأكيد البوت والقفازات والكمامة والقبعة والصديري.')));
      return;
    }
    final d = context.read<DataService>();
    final startedAt = DateTime.now();
    final lifecycle = TripLifecycle.startFields(
      startedAt: startedAt,
      targetMinutes: tripTargetMinutes,
    );
    final id = startedAt.microsecondsSinceEpoch.toString();
    setState(() => savingTrip = true);
    try {
      final selected = tripDumpsites.firstWhere((site) => site.id == selectedDumpsiteId);
      final route = await resolveDecisionRoute(u, selected.name,
          requestedDumpsiteId: selected.id);
      // Resolve again after the async directive read: the list may have changed.
      if (dumpsiteError != null || loadingDumpsites) {
        throw StateError('تعذر التحقق من قائمة المكبات. أعد تحميلها قبل التسجيل.');
      }
      final destination = resolveTripDestination(tripDumpsites, route);
      final landfill = destination.name;
      await d.enqueue('trip', 'create', {
        'id': id,
        'groupId': u.groupId,
        'groupName': u.groupId,
        'municipalityCoordinatorId': u.municipalityCoordinatorId,
        'municipalityName': u.scope == 'all' ? '' : u.scope,
        'municipality': u.scope == 'all' ? '' : u.scope,
        'supervisorId': u.id,
        'title': 'نقلة إلى $landfill',
        ...lifecycle,
        'cartType': alternative ? 'alternative' : 'primary',
        'alternative': alternative,
        ...destination.tripFields,
        'requestedDumpsiteId': selected.id,
        if (route['routeDecisionId'] != null) 'routeDecisionId': route['routeDecisionId'],
        'estimatedQuantity': quantity.text.trim(),
        'quantityUnit': 'ton',
        'issue': issue.text.trim(),
        'solution': solution.text.trim(),
        'shift': config.shift,
        'street': street.text.trim(),
        'latitude': reportPosition?.latitude,
        'longitude': reportPosition?.longitude,
        'ppeComplete': tripPpe.values.every((v) => v),
        'ppe': Map<String, bool>.from(tripPpe),
        'photoCount': tripPhotoPaths.length,
        'createdAt': DateTime.now().toIso8601String(),
        'isDeleted': false,
      });
      for (var i = 0; i < tripPhotoPaths.length; i++) {
        await d.enqueue('trip_photo', 'create', {
          'id': '${id}_photo_$i',
          'parentTripId': id,
          'localAttachmentPath': tripPhotoPaths[i],
          'attachmentType': 'image',
          'userId': u.id,
          'createdAt': DateTime.now().toIso8601String(),
          'isDeleted': false,
        });
      }
      await d.addActivity(
        'بدء نقلة',
        'بدأت ${alternative ? 'نقلة كارة بديلة' : 'نقلة كارة أساسية'} إلى $landfill، والمدة المستهدفة $tripTargetMinutes دقيقة، مع ${tripPhotoPaths.length} صورة.',
        level: 'success',
      );
      if (mounted) {
        setState(() {
          tripPhotoPaths.clear();
          tripPpe.updateAll((key, value) => false);
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('حُفظت النقلة محليًا وتنتظر تأكيد مزامنتها مع الخادم.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: AppText('تعذر تسجيل النقلة. تم الاحتفاظ بالبيانات محليًا إن أمكن. التفاصيل: $e')));
    } finally {
      if (mounted) setState(() => savingTrip = false);
    }
  }

  Future<void> _startAudio() async {
    final c = context.read<ConfigService>();
    if (!c.voiceEnabled || recording || emergencyLock) return;
    if (!await recorder.hasPermission()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('يلزم السماح باستخدام الميكروفون.')));
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/emergency_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    if (mounted) {
      setState(() {
        recording = true;
        remaining = 10;
        audioPath = path;
      });
    }
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (remaining <= 1) {
        t.cancel();
        await _stopAudio();
      } else {
        setState(() => remaining--);
      }
    });
  }

  Future<void> _stopAudio() async {
    if (!recording) return;
    final path = await recorder.stop();
    if (mounted) {
      setState(() {
        recording = false;
        remaining = 0;
        audioPath = path ?? audioPath;
      });
    }
  }

  void _refreshEmergencyStatus(DataService data) {
    final id = activeEmergencyId;
    if (id == null) return;
    final pending = data.queue.any((item) => item.entity == 'emergency' && (item.payload.contains('"id":"$id"') || item.payload.contains('"id": "$id"')));
    final record = data.operations.where((item) => '${item['id']}' == id && item['_entity'] == 'emergency').firstOrNull;
    final next = pending
        ? 'البلاغ محفوظ محليًا وينتظر المزامنة.'
        : record == null
            ? 'لا تتوفر حالة مؤكدة للبلاغ. تحقق من الاتصال والمزامنة.'
            : record['acknowledged'] == true
                ? 'تم تأكيد استلام البلاغ من المسؤول.'
                : 'اكتملت المعالجة المحلية؛ تأكيد استلام المسؤول لم يصل بعد.';
    if (mounted && record != null && record['status'] == 'closed' && !pending) {
      setState(() {
        emergencyLock = false;
        activeEmergencyId = null;
        emergencyStatus = 'تم إغلاق البلاغ من المسؤول المخوّل.';
      });
      return;
    }
    if (mounted && next != emergencyStatus) setState(() => emergencyStatus = next);
  }

  Future<void> _sendEmergency() async {
    final u = context.read<AuthService>().currentUser;
    final d = context.read<DataService>();
    if (u == null || emergencyLock || sendingEmergency || !u.can('emergency', 'create')) return;
    if (street.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('اسم الشارع أو الموقع إلزامي لبلاغ SOS.')));
      return;
    }
    setState(() => sendingEmergency = true);
    try {
    final p = await _gps();
    if (p == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('الإحداثيات إلزامية. فعّل GPS وأعد المحاولة؛ لم يُرسل البلاغ.')));
      return;
    }
    if (recording) await _stopAudio();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await d.enqueue('emergency', 'create', {
      'id': id,
      'type': 'war_remnants',
      'street': street.text.trim(),
      'latitude': p.latitude,
      'longitude': p.longitude,
      'localAttachmentPath': audioPath,
      'attachmentType': 'audio',
      'userId': u.id,
      'reportedBy': u.id,
      'createdAt': DateTime.now().toIso8601String(),
      'status': 'urgent',
      'deliveryStatus': 'pending_sync',
      'acknowledged': false,
      'groupId': u.groupId,
      'municipalityCoordinatorId': u.municipalityCoordinatorId,
      'recipientLayers': ['L2', 'L3', 'UNICEF'],
      'statusLevel': 'critical',
      'isDeleted': false,
    });
    await d.enqueue('notification', 'urgent', {
      'id': '${id}_L2',
      'targetLayer': 'L2',
      'targetRole': 'municipality_coordinator',
      'targetUserId': u.municipalityCoordinatorId,
      'sourceEntity': 'emergency',
      'title': 'بلاغ مخلفات حربية عاجل',
      'body': 'بلاغ $id — إيقاف الحركة والتنسيق الفوري.',
      'sourceId': id,
      'createdAt': DateTime.now().toIso8601String(),
    });
    // Council routing uses the assigned council coordinator when configured.
    String? councilCoordinatorId;
    if (u.municipalityCoordinatorId != null && u.municipalityCoordinatorId!.isNotEmpty) {
      try {
        final coordinator = await FirebaseFirestore.instance
            .collection('users').doc(u.municipalityCoordinatorId).get();
        councilCoordinatorId = coordinator.data()?['jscCoordinatorId']?.toString();
      } catch (_) {
        // Keep SOS usable offline; unresolved routing is not reported as delivered.
      }
    }
    await d.enqueue('notification', 'urgent', {
      'id': '${id}_L3',
      'targetLayer': 'L3',
      'targetRole': 'jsc_coordinator',
      'targetUserId': councilCoordinatorId,
      'routingStatus': councilCoordinatorId == null || councilCoordinatorId.isEmpty ? 'unresolved' : 'targeted',
      'sourceEntity': 'emergency',
      'title': 'بلاغ مخلفات حربية عاجل',
      'body': 'بلاغ $id صادر من المشرف الميداني.',
      'sourceId': id,
      'createdAt': DateTime.now().toIso8601String(),
    });
    String? unicefRecipientId;
    try {
      final settings = await FirebaseFirestore.instance.collection('config').doc('global').get();
      unicefRecipientId = settings.data()?['unicefSosRecipientUid']?.toString();
    } catch (_) {
      // The emergency is still recorded when recipient configuration is offline.
    }
    await d.enqueue('notification', 'urgent', {
      'id': '${id}_UNICEF',
      'targetLayer': 'UNICEF',
      'targetRole': 'donor_manager',
      'targetUserId': unicefRecipientId,
      'routingStatus': unicefRecipientId == null || unicefRecipientId.isEmpty ? 'unresolved' : 'targeted',
      'sourceEntity': 'emergency',
      'title': 'بلاغ SOS عاجل',
      'body': 'بلاغ $id من مشرف ميداني — الموقع: ${street.text.trim()}',
      'sourceId': id,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await d.writeAudit(actorId: u.id, operation: 'CREATE_EMERGENCY', targetId: id, after: {
      'type': 'war_remnants',
      'street': street.text.trim(),
      'latitude': p.latitude,
      'longitude': p.longitude,
      'audioQueued': audioPath != null,
    });
    if (mounted) {
      setState(() {
        emergencyLock = true;
        activeEmergencyId = id;
        emergencyStatus = 'تم حفظ البلاغ محليًا بانتظار المزامنة؛ لم يتأكد استلام الجهات بعد.';
        tab = 3;
      });
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const AppText('تحذير عاجل'),
          content: const AppText('تراجع 100 متر فوراً', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: red)),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const AppText('تم'))],
        ),
      );
    }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: AppText('تعذر حفظ بلاغ SOS: $e')));
    } finally {
      if (mounted) setState(() => sendingEmergency = false);
    }
  }

  Future<void> _smartReport() async {
    final u = context.read<AuthService>().currentUser;
    if (u == null || !u.can('reports', 'create')) return;
    final d = context.read<DataService>();
    final s = await ReportService(d).load(user: u);
    final summary = await ReportService(d).createSmartReport(user: u, snapshot: s, group: 'مجموعة المشرف');
    if (mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const AppText('التقرير الذكي'),
          content: AppText(summary),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const AppText('إغلاق'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataService>();
    final config = context.watch<ConfigService>();
    final user = context.watch<AuthService>().currentUser!;
    final online = data.online;
    final action = widget.initialAction;
    if (action != null) {
      final permitted = user.role == 'group_supervisor' &&
          user.can(action, 'view') && user.can(action, 'create') &&
          (action != 'leave' || user.can('attendance', 'create'));
      final taskBody = !permitted
          ? const Center(child: AppText('هذه المهمة غير متاحة ضمن صلاحيات حسابك.'))
          : switch (action) {
              'attendance' || 'leave' => _attendance(config),
              'trips' => _trips(config),
              'streets' => _streets(config),
              'emergency' => _emergency(config),
              _ => const Center(child: AppText('المهمة المطلوبة غير متاحة.')),
            };
      return Scaffold(
        appBar: AppBar(bottom: const AppNavigationBar(), title: AppText(const {
          'attendance': 'تسجيل الحضور والغياب', 'leave': 'تسجيل الإجازة أو الإذن',
          'trips': 'تسجيل نقلة', 'streets': 'توثيق الشوارع',
          'emergency': 'بلاغ طارئ',
        }[action] ?? 'المهام الميدانية')),
        body: taskBody,
      );
    }
    return Directionality(
      textDirection: context.watch<LocaleController>().isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(bottom: const AppNavigationBar(),
          title: const AppText('المشرف الميداني'),
          actions: [
            if (data.queue.isNotEmpty)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Center(child: AppText('${data.queue.length} بانتظار المزامنة', style: const TextStyle(fontSize: 10, color: cleanOpsMuted)))),
            IconButton(tooltip: tr('البحث في النظام'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GlobalSearchPage())), icon: const Icon(Icons.search_rounded)),
            Tooltip(
              message: data.automaticSyncStatus,
              child: Icon(
                data.syncing
                    ? Icons.sync_rounded
                    : online
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_off_rounded,
                color: online ? aiGreen : orange,
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 120),
            children: [
              AiHero(
                user: context.read<AuthService>().currentUser!,
                eyebrow: 'مشرف ميداني',
                title: 'تشغيل ميداني سريع',
                subtitle: 'مهام مجموعتك وأدوات التواصل والمتابعة، حسب صلاحيات حسابك.',
              ),
              const SizedBox(height: 12),
              DecisionDirectiveBanner(onCoverageChanged: _loadWorkers),
              const OperationsOverviewStrip(),
              const SizedBox(height: 12),
              WorkspaceOverview(actions: [
                for (final feature in FieldTaskShortcuts.features)
                  if (FeatureRoutePolicy.resolve(user, feature) != null)
                    WorkspaceAction(feature, FieldTaskShortcuts.label(user, feature),
                      FieldTaskShortcuts.icon(feature),
                      () => openAppFeature(context, feature)),
              ]),
              const SizedBox(height: 12),
              FieldSupportShortcuts(user: user),
              const SizedBox(height: 16),
              AiSectionCard(
                title: 'حالة التشغيل',
                subtitle: online ? 'متصل — البيانات تتزامن تلقائيًا.' : 'التحديثات محفوظة على الجهاز وستتزامن عند عودة الاتصال.',
                feature: 'sync',
                child: Row(children: [Icon(online ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, color: online ? aiGreen : orange, size: 28), const SizedBox(width: 10), Expanded(child: AppText(online ? 'متصل بالسحابة' : 'العمل دون اتصال', style: TextStyle(color: online ? aiGreen : orange, fontWeight: FontWeight.w900))), if (data.queue.isNotEmpty) AppText('${data.queue.length}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attendance(ConfigService config) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        AiHero(
          user: context.read<AuthService>().currentUser!,
          eyebrow: 'الحضور والسلامة',
          title: widget.initialAction == 'leave' ? 'الإجازات والأذونات' : 'حضور مجموعتي',
          subtitle: widget.initialAction == 'leave' ? 'اختر العامل ثم حدد إجازة أو إذنًا خاصًا من قائمة الحالة، واحفظ كشف الحضور.' : 'حدد حالة كل عامل قبل حفظ كشف الوردية، ثم افحص معدات الوقاية للحاضرين.',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(width: 160, child: AiStatTile(title: 'النقلات', value: '$trips', subtitle: 'كارات أساسية', feature: 'trips')),
            SizedBox(width: 160, child: AiStatTile(title: 'البديلة', value: '$alternativeTrips', subtitle: 'كارات بديلة', feature: 'operations')),
            SizedBox(width: 160, child: AiStatTile(title: 'الحالة', value: emergencyLock ? 'متوقف' : 'جاهز', subtitle: emergencyLock ? 'بروتوكول طوارئ' : 'تشغيل طبيعي', feature: emergencyLock ? 'emergency' : 'attendance')),
          ],
        ),
        const SizedBox(height: 14),
        SupervisorCardSection(
          title: 'الإعدادات والبيانات الأساسية',
          icon: const Icon(Icons.assignment_outlined),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: ListTile(title: const AppText('التاريخ'), subtitle: AppText(DateTime.now().toString().substring(0, 10)))),
                  Expanded(child: ListTile(title: const AppText('الوقت'), subtitle: AppText(TimeOfDay.now().format(context)))),
                ],
              ),
              DropdownButtonFormField<String>(
                value: config.shift,
                items: const [
                  DropdownMenuItem(value: '08:00 - 16:00', child: AppText('08:00 - 16:00')),
                  DropdownMenuItem(value: '07:00 - 15:00', child: AppText('07:00 - 15:00')),
                  DropdownMenuItem(value: '16:00 - 00:00', child: AppText('16:00 - 00:00')),
                ],
                onChanged: null,
                decoration: InputDecoration(labelText: tr('الوردية المعتمدة')),
              ),
              const SizedBox(height: 8),
              TextField(controller: street, enabled: !emergencyLock, decoration: InputDecoration(labelText: tr('اسم الشارع / المربع'))),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: emergencyLock ? null : _captureGps,
                icon: const Icon(Icons.gps_fixed),
                label: AppText(reportPosition == null ? 'التقاط GPS' : '${reportPosition!.latitude.toStringAsFixed(5)}, ${reportPosition!.longitude.toStringAsFixed(5)}'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SupervisorCardSection(
          title: 'عمال مجموعتي',
          icon: const Icon(Icons.health_and_safety_outlined),
          child: loadingWorkers
              ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
              : workers.isEmpty
                  ? const AppText('لا يوجد عمال نشطون مخصصون لهذه المجموعة ضمن الكشف المتاح.')
                  : Column(children: workers.map((w) => _worker(w, config)).toList()),
        ),
        const SizedBox(height: 12),
        if (workerLoadError != null) AppText(workerLoadError!),
        AppText('العمال: ${workers.length} • حاضر: ${attendanceStatus.values.where((v) => v == 'present').length} • لم تُحدد حالتهم: ${workers.where((w) => !attendanceStatus.containsKey(w['id'])).length}'),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: emergencyLock || workers.isEmpty || savingAttendance ? null : _saveAttendance,
          icon: const Icon(Icons.fact_check_outlined),
          label: AppText(savingAttendance ? 'جارٍ حفظ الكشف...' : 'حفظ كشف حضور مجموعتي'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: emergencyLock ? null : _smartReport,
          icon: const Icon(Icons.auto_awesome),
          label: const AppText('إنشاء التقرير الذكي'),
        ),
      ],
    );
  }

  Future<void> _saveAttendance() async {
    final u = context.read<AuthService>().currentUser;
    final config = context.read<ConfigService>();
    if (config.stageFrozen) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('المرحلة مجمّدة — التعديلات التشغيلية مقفلة')));
      return;
    }
    if (u == null || !u.can('attendance', 'create') || savingAttendance) return;
    final missing = workers.where((w) => !attendanceStatus.containsKey(w['id'])).length;
    if (missing > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: AppText('حدد حالة جميع العمال أولًا. المتبقي: $missing')));
      return;
    }
    if (config.ppeEnabled) {
      final incomplete = workers.where((w) => (attendanceStatus[w['id'] ?? ''] ?? 'unset') == 'present').where((w) {
        return !ppe.isComplete(w['id'] ?? '');
      }).toList();
      if (incomplete.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('اعتمد البوت والقفازات والكمامة والقبعة والصديري لكل عامل حاضر قبل حفظ الكشف.')));
        return;
      }
    }
    setState(() => savingAttendance = true);
    try {
    final d = context.read<DataService>();
    final day = DateTime.now().toIso8601String().substring(0, 10);
    final rosterToSave = List<Map<String, String>>.from(workers);
    for (final w in rosterToSave) {
      final name = w['name'] ?? '';
      final workerId = w['id'] ?? '';
      final state = ppe.snapshot(workerId);
      final id = 'attendance_${u.groupId}_${config.shift.replaceAll(RegExp(r'[^0-9]'), '')}_${day}_${w['id']}';
      await d.enqueue('attendance', 'create', {
        'id': id,
        'workerId': w['id'],
        if (w['temporaryDecisionId'] != null) 'temporaryDecisionId': w['temporaryDecisionId'],
        'workerName': name,
        'workerRole': w['role'] ?? 'worker',
        'groupId': u.groupId ?? w['groupId'] ?? '',
        'groupName': w['groupName'] ?? u.groupId ?? '',
        'municipalityName': u.scope == 'assigned_only' ? (w['municipalityName'] ?? '') : u.scope,
        'municipalityCoordinatorId': u.municipalityCoordinatorId ?? '',
        'status': attendanceStatus[w['id'] ?? ''] ?? 'unset',
        if ((attendanceStatus[w['id'] ?? ''] ?? 'unset') == 'present') 'checkInAt': DateTime.now().toIso8601String(),
        'ppeComplete': ppe.isComplete(workerId),
        'ppe': state,
        'reportedBy': u.id,
        'shift': config.shift,
        'createdAt': DateTime.now().toIso8601String(),
        'isDeleted': false,
      });
    }
    await d.addActivity('الحضور وPPE', 'تم حفظ كشف الحضور وفحص معدات الوقاية للمجموعة.', level: 'success');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: AppText('تم حفظ الكشف محليًا وإضافته لقائمة المزامنة؛ تأكيد الخادم لاحقًا.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: AppText('تعذر حفظ الكشف: $e')));
    } finally {
      if (mounted) setState(() => savingAttendance = false);
    }
  }

  Widget _worker(Map<String, String> w, ConfigService config) {
    final workerId = w['id'] ?? '';
    final state = ppe.forWorker(workerId);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: emergencyLock || savingAttendance ? null : () => _openSafetyApproval(w, config),
        child: Padding(
          padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(backgroundColor: aiBlue, child: Icon(Icons.person_rounded, color: Colors.white)),
                const SizedBox(width: 8),
                Expanded(child: AppText('${w['name']} — ${w['job']} • المجموعة ${w['group']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                if ((w['phone'] ?? '').isNotEmpty)
                  IconButton(onPressed: emergencyLock ? null : () => _call(w['phone']!), icon: const Icon(Icons.phone, color: green)),
              ],
            ),
            DropdownButtonFormField<String>(
              value: attendanceStatus[workerId] ?? 'unset',
              decoration: InputDecoration(labelText: tr('حالة العامل')),
              items: const [
                DropdownMenuItem(value: 'unset', child: AppText('لم يتم تحديد الحالة')),
                DropdownMenuItem(value: 'present', child: AppText('حضور')),
                DropdownMenuItem(value: 'absent', child: AppText('غياب')),
                DropdownMenuItem(value: 'leave', child: AppText('إجازة')),
                DropdownMenuItem(value: 'permission', child: AppText('إذن خاص')),
                DropdownMenuItem(value: 'excused_absence', child: AppText('غياب بعذر')),
                DropdownMenuItem(value: 'unexcused_absence', child: AppText('غياب بدون عذر')),
                DropdownMenuItem(value: 'external_task', child: AppText('مهمة خارج المجموعة')),
              ],
              onChanged: emergencyLock || savingAttendance ? null : (v) => setState(() => attendanceStatus[workerId] = v ?? 'unset'),
            ),
            const SizedBox(height: 8),
            if (config.ppeEnabled && attendanceStatus[workerId] == 'present')
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: state.keys.map((k) => FilterChip(
                  label: AppText(k),
                  selected: state[k]!,
                  onSelected: emergencyLock || savingAttendance ? null : (v) => setState(() => state[k] = v),
                )).toList(),
              ),
          ],
        ),
      ),
      ),
    );
  }

  Future<void> _openSafetyApproval(Map<String, String> worker, ConfigService config) async {
    final workerId = worker['id'] ?? '';
    if (workerId.trim().isEmpty || emergencyLock || savingAttendance) return;
    final name = worker['name'] ?? 'العامل';
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: cleanOpsSurface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.health_and_safety_rounded, color: aiGreen, size: 42),
            const SizedBox(height: 8),
            const AppText('اعتماد السلامة قبل العمل', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            AppText(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const AppText('تأكد من البوت والقفازات والكمامة والقبعة والصديري قبل اعتماد العامل.', textAlign: TextAlign.center, style: TextStyle(color: cleanOpsMuted)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: aiGreen, foregroundColor: Colors.black), onPressed: () => Navigator.pop(sheetContext, true), icon: const Icon(Icons.check_circle_rounded), label: const AppText('مطابق'))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: red, side: const BorderSide(color: red)), onPressed: () => Navigator.pop(sheetContext, false), icon: const Icon(Icons.cancel_rounded, color: red), label: const AppText('غير مطابق', style: TextStyle(color: red)))),
            ]),
          ]),
        ),
      ),
    );
    if (!mounted || result == null || emergencyLock || savingAttendance) return;
    setState(() => ppe.setAll(workerId, result));
    if (result && config.ppeEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: AppText('تم اعتماد السلامة للعامل: $name')));
    } else if (!result) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: AppText('العامل غير مطابق لمتطلبات السلامة: $name')));
    }
  }

  Future<void> _completeTrip(String tripId) async {
    final user = context.read<AuthService>().currentUser;
    final data = context.read<DataService>();
    if (user == null || !user.can('trips', 'edit')) return;
    final index = data.operations.indexWhere((item) =>
        item['_entity'] == 'trip' && '${item['id'] ?? ''}' == tripId);
    if (index < 0) return;
    final trip = data.operations[index];
    if (!TripLifecycle.canSupervisorComplete(
      trip: trip,
      supervisorId: user.id,
      groupId: user.groupId ?? '',
    )) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: AppText('لا يمكن إنهاء نقلة لا تتبع مجموعتك أو تم إغلاقها مسبقًا.'),
        ));
      }
      return;
    }
    await data.enqueue('trip', 'update', {
      'id': tripId,
      ...TripLifecycle.completionFields(
        completedAt: DateTime.now(),
        completedBy: user.id,
      ),
    });
    await data.addActivity(
      'إنهاء نقلة',
      'تم اعتماد وصول النقلة وإغلاقها بواسطة رئيس المجموعة.',
      level: 'success',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: AppText('تم إنهاء النقلة محليًا وستتم مزامنتها تلقائيًا.'),
      ));
    }
  }

  Widget _activeTripsCard() {
    final data = context.watch<DataService>();
    final user = context.watch<AuthService>().currentUser;
    final groupId = user?.groupId?.trim() ?? '';
    if (user == null || groupId.isEmpty) return const SizedBox.shrink();
    final active = data.operations.where((item) =>
      TripLifecycle.canSupervisorComplete(
        trip: item,
        supervisorId: user.id,
        groupId: groupId,
      ),
    ).toList()
      ..sort((a, b) => '${b['startedAt'] ?? b['createdAt'] ?? ''}'
          .compareTo('${a['startedAt'] ?? a['createdAt'] ?? ''}'));
    if (active.isEmpty) return const SizedBox.shrink();
    return AiSectionCard(
      title: 'النقلات النشطة',
      subtitle: 'إنهاء النقلة يوقف احتساب التأخير ويُزامن تلقائيًا.',
      feature: 'trips',
      child: Column(
        children: active.map((trip) {
          final overdue = OperationalInsights.reviewTrips(
            [trip],
            now: DateTime.now(),
          ).overdue > 0;
          final deadline = '${trip['deadlineAt'] ?? ''}';
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              overdue ? Icons.warning_amber_rounded : Icons.local_shipping_rounded,
              color: overdue ? Colors.orange : aiCyan,
            ),
            title: AppText('${trip['title'] ?? 'نقلة إلى ${trip['landfill'] ?? ''}'}'),
            subtitle: AppText(
              overdue
                  ? 'متأخرة عن الموعد المستهدف: $deadline'
                  : 'الموعد المستهدف: $deadline',
              style: TextStyle(
                fontSize: 10,
                color: overdue ? Colors.orange : cleanOpsMuted,
                fontWeight: overdue ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
            trailing: FilledButton.tonal(
              onPressed: emergencyLock ? null : () => _completeTrip('${trip['id']}'),
              child: const AppText('تم الوصول'),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _trips(ConfigService config) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
    children: [
      _activeTripsCard(),
      const SizedBox(height: 12),
      SupervisorCardSection(
        title: 'النقلات والتوثيق',
        icon: const Icon(Icons.local_shipping_outlined),
        child: Column(
          children: [
            Row(children: [
              Expanded(child: _counter('$trips', 'كارة أساسية', navy)),
              Expanded(child: _counter('$alternativeTrips', 'كارة بديلة', orange)),
            ]),
            TextField(
              controller: street,
              enabled: !emergencyLock && !savingTrip,
              decoration: InputDecoration(labelText: tr('اسم الشارع / موقع جمع النفايات')),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: emergencyLock || savingTrip ? null : _captureGps,
              icon: const Icon(Icons.gps_fixed),
              label: AppText(reportPosition == null ? 'تحديد الموقع' : 'تم تحديد الموقع'),
            ),
            const SizedBox(height: 10),
            TripDumpsitePicker(
              sites: tripDumpsites, selectedId: selectedDumpsiteId,
              enabled: !emergencyLock && !savingTrip,
              loading: loadingDumpsites, fromCache: dumpsitesFromCache,
              error: dumpsiteError, onRetry: _watchTripDumpsites,
              onSelected: (id) {
                if (mounted && !savingTrip) setState(() => selectedDumpsiteId =
                    tripDumpsites.any((site) => site.id == id) ? id : null);
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              value: tripTargetMinutes,
              decoration: const InputDecoration(
                labelText: 'المدة المستهدفة للوصول',
                helperText: 'يُحسب موعد التأخير من لحظة بدء النقلة.',
              ),
              items: TripLifecycle.targetMinuteOptions.map((minutes) {
                final label = switch (minutes) {
                  30 => '30 دقيقة',
                  60 => 'ساعة',
                  90 => 'ساعة ونصف',
                  120 => 'ساعتان',
                  180 => '3 ساعات',
                  240 => '4 ساعات',
                  _ => '$minutes دقيقة',
                };
                return DropdownMenuItem(value: minutes, child: AppText(label));
              }).toList(),
              onChanged: emergencyLock || savingTrip ? null : (value) {
                if (value != null) setState(() => tripTargetMinutes = value);
              },
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: FilledButton.icon(onPressed: emergencyLock || savingTrip || loadingDumpsites || dumpsiteError != null || selectedDumpsiteId == null ? null : () => _registerTrip(false), icon: const Icon(Icons.play_arrow_rounded), label: const AppText('بدء نقلة أساسية'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: emergencyLock || savingTrip || loadingDumpsites || dumpsiteError != null || selectedDumpsiteId == null || !config.alternativeCartEnabled ? null : () => _registerTrip(true), icon: const Icon(Icons.swap_horiz), label: const AppText('بدء نقلة بديلة'))),
            ]),
            const SizedBox(height: 10),
            TextField(controller: quantity, enabled: !emergencyLock, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('الكمية التقديرية (طن)'))),
            const SizedBox(height: 8),
            TextField(controller: issue, enabled: !emergencyLock, decoration: InputDecoration(labelText: tr('مشكلة/عطل/إغلاق طريق'))),
            const SizedBox(height: 8),
            TextField(controller: solution, enabled: !emergencyLock, decoration: InputDecoration(labelText: tr('الحل الفوري المتخذ'))),
            if (config.ppeEnabled) ...[
              const SizedBox(height: 14),
              AiSectionCard(title: 'اعتماد السلامة قبل النقلة', subtitle: 'يجب تأكيد جميع معدات الوقاية قبل تسجيل النقلة.', feature: 'permissions', child: Wrap(spacing: 6, runSpacing: 6, children: tripPpe.keys.map((k) => FilterChip(avatar: Icon(k == 'بوت' ? Icons.hiking_rounded : k == 'قفازات' ? Icons.back_hand_rounded : k == 'كمامة' ? Icons.masks_rounded : k == 'قبعة' ? Icons.sports_baseball_rounded : Icons.health_and_safety_rounded, size: 16), label: AppText(k), selected: tripPpe[k]!, onSelected: emergencyLock ? null : (v) => setState(() => tripPpe[k] = v))).toList())),
            ],
            const SizedBox(height: 12),
            AiSectionCard(title: 'صور النقلة', subtitle: 'اختر عدة صور من الاستوديو دفعة واحدة أو التقط صورًا بالكاميرا (حتى 3 صور).', feature: 'streets', child: Column(children: [
              Align(alignment: AlignmentDirectional.centerStart, child: FilledButton.tonalIcon(onPressed: emergencyLock || tripPhotoPaths.length >= 3 ? null : _addTripPhoto, icon: const Icon(Icons.add_a_photo_rounded), label: AppText('إضافة صورة (${tripPhotoPaths.length}/3)'))),
              if (tripPhotoPaths.isNotEmpty) const SizedBox(height: 8),
              if (tripPhotoPaths.isNotEmpty) SizedBox(height: 92, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: tripPhotoPaths.length, separatorBuilder: (_, __) => const SizedBox(width: 8), itemBuilder: (_, i) { final path = tripPhotoPaths[i]; return Stack(children: [ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(path), width: 92, height: 92, fit: BoxFit.cover)), PositionedDirectional(top: 2, end: 2, child: InkWell(onTap: () => _removeTripPhoto(path), child: Container(decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle), padding: const EdgeInsets.all(4), child: const Icon(Icons.close, size: 14, color: Colors.white))))]); })),
            ])),
          ],
        ),
      ),
    ],
  );

  Widget _counter(String v, String label, Color color) => Column(children: [
    AppText(v, style: TextStyle(fontSize: 54, fontWeight: FontWeight.w900, color: color)),
    AppText(label),
  ]);

  Widget _streets(ConfigService config) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
    children: [
      if (!config.streetPhotosEnabled)
        const Card(child: Padding(padding: EdgeInsets.all(16), child: AppText('توثيق الشوارع معطّل من إعدادات المنظومة.')))
      else
        SupervisorCardSection(
          title: 'قبل / بعد + وصف تلقائي',
          icon: const Icon(Icons.camera_alt_outlined),
          child: Column(
            children: [
              TextField(controller: street, enabled: !emergencyLock, decoration: InputDecoration(labelText: tr('اسم الشارع'))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: FilledButton.icon(onPressed: emergencyLock ? null : () => _takePhoto('قبل'), icon: const Icon(Icons.camera_alt), label: const AppText('قبل'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton.icon(onPressed: emergencyLock ? null : () => _takePhoto('بعد'), icon: const Icon(Icons.camera_alt_outlined), label: const AppText('بعد'))),
              ]),
            ],
          ),
        ),
    ],
  );

  Widget _emergency(ConfigService config) {
    final data = context.watch<DataService>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshEmergencyStatus(data));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        Card(
          color: red.withOpacity(.08),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 72, color: red),
                const AppText('بروتوكول مخلفات حربية', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: red)),
                const SizedBox(height: 8),
                const AppText('لا تقترب. احصل على GPS وأرسل البلاغ ثم تراجع 100 متر فوراً.', textAlign: TextAlign.center),
                const SizedBox(height: 14),
                TextField(controller: street, enabled: !emergencyLock, decoration: InputDecoration(labelText: tr('اسم الشارع / الموقع'))),
                const SizedBox(height: 12),
                if (config.voiceEnabled)
                  FilledButton.icon(
                    onPressed: recording ? _stopAudio : (emergencyLock ? null : _startAudio),
                    icon: Icon(recording ? Icons.stop : Icons.mic),
                    label: AppText(recording ? 'تسجيل جارٍ $remaining ثوانٍ' : 'تسجيل صوتي 10 ثوانٍ'),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: red, minimumSize: const Size.fromHeight(58)),
                  onPressed: emergencyLock || sendingEmergency ? null : _sendEmergency,
                  icon: const Icon(Icons.gps_fixed),
                  label: AppText(sendingEmergency ? 'جارٍ حفظ البلاغ...' : 'إرسال إنذار عاجل'),
                ),
                if (emergencyStatus.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 10), child: AppText(emergencyStatus, textAlign: TextAlign.center)),
                if (emergencyLock)
                  const Padding(
                    padding: EdgeInsets.only(top: 14),
                    child: AppText('تم قفل النقلات والإدخال. تراجع 100 متر فوراً وانتظر غرفة العمليات.', style: TextStyle(color: red, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(onPressed: _smartReport, icon: const Icon(Icons.auto_awesome), label: const AppText('إنشاء التقرير الذكي')),
      ],
    );
  }
}

class SupervisorCardSection extends StatelessWidget {
  final String title;
  final Widget icon;
  final Widget child;
  const SupervisorCardSection({super.key, required this.title, required this.icon, required this.child});
  @override
  Widget build(BuildContext context) => AiSectionCard(
    title: title,
    feature: title.contains('طوارئ')
        ? 'emergency'
        : title.contains('الحضور')
            ? 'attendance'
            : title.contains('النقل')
                ? 'trips'
                : title.contains('الشوارع')
                    ? 'streets'
                    : 'operations',
    child: child,
  );
}
