import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/localization.dart';
import '../../core/models/core_models.dart';
import '../../core/services/ai_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/config_service.dart';
import '../../core/services/data_service.dart';
import '../../core/services/report_service.dart';
import '../../core/services/assistant_shortcut_policy.dart';
import '../../core/services/operations_admin_service.dart';
import '../../core/services/operational_insights.dart';
import 'enterprise_operations_hub.dart';
import '../widgets/app_design.dart';
import 'messages_center.dart';
import 'live_operations_map.dart';
import 'operations_management.dart';
import 'reports_center.dart';
import '../../core/constants/app_constants.dart';

class AIBotScreen extends StatefulWidget {
  const AIBotScreen({super.key});
  @override State<AIBotScreen> createState() => _AIBotScreenState();
}

class _ChatMessage {
  final String text;
  final bool fromUser;
  const _ChatMessage(this.text, {required this.fromUser});
}

class _LinkedOperationalRecord {
  final String collection;
  final String id;
  final String title;
  final String subtitle;
  final String feature;
  final Map<String, dynamic> data;
  const _LinkedOperationalRecord({
    required this.collection,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.feature,
    required this.data,
  });
}

class _AIBotScreenState extends State<AIBotScreen> with TickerProviderStateMixin {
  late final AnimationController orbitController;
  late final AnimationController glowController;
  late final AnimationController entranceController;
  final TextEditingController input = TextEditingController();
  final ScrollController chatScroll = ScrollController();
  final List<_ChatMessage> messages = [];
  List<_LinkedOperationalRecord> linkedRecords = const [];
  bool loading = false;
  bool exportingPdf = false;

  @override
  void initState() {
    super.initState();
    orbitController = AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();
    glowController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
    entranceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))..forward();
    messages.add(const _ChatMessage('أنا CleanOps AI. أستطيع تحليل مؤشرات التشغيل الحقيقية من Firestore للمستوى 3 و4. اطرح سؤالك وسأوضح مصدر الأرقام بدل اختلاقها.', fromUser: false));
  }

  @override
  void dispose() {
    orbitController.dispose();
    glowController.dispose();
    entranceController.dispose();
    input.dispose();
    chatScroll.dispose();
    super.dispose();
  }

  Future<void> _toggleLanguage() async {
    final locale = context.read<LocaleController>();
    locale.toggle();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', locale.locale.languageCode);
  }

  Future<void> _send() async {
    final question = input.text.trim();
    final user = context.read<AuthService>().currentUser;
    if (question.isEmpty || loading || user == null) return;
    if (user.role != 'donor_manager' && user.role != 'jsc_coordinator') {
      setState(() => messages.add(const _ChatMessage('المساعد الذكي متاح للمستوى 3 والمستوى 4 فقط.', fromUser: false)));
      return;
    }
    input.clear();
    setState(() {
      messages.add(_ChatMessage(question, fromUser: true));
      loading = true;
    });
    _scrollToBottom();
    try {
      final service = AIService(config: context.read<ConfigService>());
      final answer = await service.answer(user: user, question: question);
      var links = const <_LinkedOperationalRecord>[];
      try {
        links = await _loadLinkedRecords(user, question);
      } on FirebaseException {
        links = const <_LinkedOperationalRecord>[];
      }
      if (!mounted) return;
      setState(() {
        messages.add(_ChatMessage(answer, fromUser: false));
        linkedRecords = links;
      });
    } catch (e) {
      if (!mounted) return;
      final error = e.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
      setState(() => messages.add(_ChatMessage(error, fromUser: false)));
    } finally {
      if (mounted) {
        setState(() => loading = false);
        _scrollToBottom();
      }
    }
  }


  String _normalizeLinkQuestion(String value) => value.toLowerCase()
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه');

  DateTime _recordTime(Map<String, dynamic> data) {
    final value = data['createdAt'] ?? data['timestamp'] ?? data['updatedAt'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse('${value}') ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<List<_LinkedOperationalRecord>> _loadLinkedRecords(
      AppUser user, String question) async {
    final q = _normalizeLinkQuestion(question);
    bool has(List<String> terms) => terms.any((term) => q.contains(_normalizeLinkQuestion(term)));
    final broad = has(['ملخص', 'تحليل', 'مخاطر', 'مشاكل', 'اولويات', 'الوضع']);
    final wantsWorkers = broad || has(['عامل', 'عمال', 'موظف', 'موظفين', 'نقص العمال', 'الطاقم']);
    final wantsGroups = broad || has(['مجموعه', 'مجموعات', 'فريق', 'فرق', 'توزيع']);
    final wantsTrips = broad || has(['ترحيل', 'ترحيلات', 'رحله', 'رحلات', 'حموله', 'نقله', 'تاخر']);
    final wantsAlerts = broad || has(['طوارئ', 'تنبيه', 'بلاغ', 'بلاغات', 'sos', 'استغاثه']);
    final wantsSites = broad || has(['مكب', 'مكبات', 'مطمر', 'مطامر', 'امتلاء']);
    final result = <_LinkedOperationalRecord>[];

    bool visible(Map<String, dynamic> data) => OperationalInsights.visibleToUser(
      data, role: user.role, userId: user.id, scope: user.scope, groupId: user.groupId,
    );

    if (wantsWorkers) {
      final snap = await FirebaseFirestore.instance.collection('users')
          .where('isActive', isEqualTo: true).limit(400).get();
      final docs = snap.docs.where((doc) {
        final data = doc.data();
        return data['role'] == 'worker' && visible(data);
      }).take(4);
      for (final doc in docs) {
        final data = doc.data();
        result.add(_LinkedOperationalRecord(
          collection: 'users', id: doc.id, feature: 'workers',
          title: '${data['name'] ?? data['fullName'] ?? data['displayName'] ?? 'عامل'}',
          subtitle: 'عامل • ${data['groupName'] ?? data['groupId'] ?? 'دون مجموعة'}',
          data: data,
        ));
      }
    }

    if (wantsGroups || wantsTrips || wantsAlerts || wantsWorkers) {
      final snap = await FirebaseFirestore.instance.collection('operations').limit(1000).get();
      final docs = snap.docs.where((doc) => visible(doc.data())).toList()
        ..sort((a, b) => _recordTime(b.data()).compareTo(_recordTime(a.data())));

      if (wantsGroups) {
        for (final doc in docs.where((d) => d.data()['_entity'] == 'group').take(4)) {
          final data = doc.data();
          result.add(_LinkedOperationalRecord(
            collection: 'operations', id: doc.id, feature: 'workers',
            title: '${data['name'] ?? data['groupName'] ?? data['groupId'] ?? 'مجموعة'}',
            subtitle: 'مجموعة • ${data['municipalityName'] ?? data['municipality'] ?? ''}',
            data: data,
          ));
        }
      }
      if (wantsTrips) {
        final trips = docs.where((d) => d.data()['_entity'] == 'trip' && d.data()['isDeleted'] != true);
        for (final doc in trips.take(4)) {
          final data = doc.data();
          final review = OperationalInsights.reviewTrips([data], now: DateTime.now());
          result.add(_LinkedOperationalRecord(
            collection: 'operations', id: doc.id, feature: 'trips',
            title: '${data['title'] ?? data['operation'] ?? data['tripNumber'] ?? 'ترحيل'}',
            subtitle: review.overdue > 0
                ? 'ترحيل متأخر • ${data['status'] ?? 'قيد التنفيذ'}'
                : 'ترحيل • ${data['status'] ?? 'مسجل'}',
            data: data,
          ));
        }
      }
      if (wantsAlerts) {
        for (final doc in docs.where((d) =>
            (d.data()['_entity'] == 'emergency' || d.data()['_entity'] == 'notification') &&
            OperationalInsights.isOpenAlert(d.data())).take(4)) {
          final data = doc.data();
          result.add(_LinkedOperationalRecord(
            collection: 'operations', id: doc.id, feature: 'emergency',
            title: '${data['title'] ?? data['name'] ?? data['body'] ?? 'تنبيه تشغيلي'}',
            subtitle: 'تنبيه • ${data['statusLevel'] ?? data['level'] ?? data['status'] ?? 'مفتوح'}',
            data: data,
          ));
        }
      }
      if (wantsWorkers) {
        for (final doc in docs.where((d) => d.data()['_entity'] == 'worker').take(3)) {
          final data = doc.data();
          result.add(_LinkedOperationalRecord(
            collection: 'operations', id: doc.id, feature: 'workers',
            title: '${data['name'] ?? data['workerName'] ?? 'عامل'}',
            subtitle: 'عامل مسجل بالعمليات • ${data['groupName'] ?? data['groupId'] ?? 'دون مجموعة'}',
            data: data,
          ));
        }
      }
    }

    if (wantsSites && user.can('dumpsite', 'view')) {
      final snap = await FirebaseFirestore.instance.collection('dumpsites')
          .where('isActive', isEqualTo: true).limit(200).get();
      final docs = [...snap.docs]..sort((a, b) {
        double fill(Map<String, dynamic> d) {
          final value = d['fillPercentage'];
          return value is num ? value.toDouble() : double.tryParse('${value}') ?? 0;
        }
        return fill(b.data()).compareTo(fill(a.data()));
      });
      for (final doc in docs.take(4)) {
        final data = doc.data();
        result.add(_LinkedOperationalRecord(
          collection: 'dumpsites', id: doc.id, feature: 'dumpsite',
          title: '${data['nameAr'] ?? data['name'] ?? 'مكب'}',
          subtitle: 'مكب • الامتلاء ${data['fillPercentage'] ?? 0}%',
          data: data,
        ));
      }
    }

    final unique = <String>{};
    return result.where((item) => unique.add('${item.collection}:${item.id}')).take(10).toList();
  }

  Future<void> _exportPeriodPdf() async {
    if (exportingPdf) return;
    final user = context.read<AuthService>().currentUser;
    if (user == null || !user.can('reports', 'export')) return;
    final today = DateTime.now();
    final period = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(today.year + 5, 12, 31),
      initialDateRange: DateTimeRange(
        start: today.subtract(const Duration(days: 6)),
        end: today,
      ),
      helpText: 'فترة التقرير التشغيلي (يمكن اختيار أكثر من 60 يومًا)',
      saveText: 'اعتماد الفترة',
    );
    if (period == null || !mounted) return;
    setState(() => exportingPdf = true);
    try {
      final reports = ReportService(context.read<DataService>());
      final snapshot = await reports.load(
        user: user, startDate: period.start, endDate: period.end,
      );
      final result = await reports.exportOperationalPdf(
        snapshot: snapshot, user: user, title: 'تقرير CleanOps التشغيلي',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: AppText(result == null
            ? 'تعذر حفظ ملف PDF.'
            : 'تم إعداد ملف PDF للفترة المحددة: $result'),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: AppText('تعذر تصدير التقرير: $error'),
      ));
    } finally {
      if (mounted) setState(() => exportingPdf = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (chatScroll.hasClients) chatScroll.animateTo(chatScroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final locale = context.watch<LocaleController>();
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 390;
    final titleSize = (width * .055).clamp(19.0, 25.0);
    final allowed = user?.role == 'donor_manager' || user?.role == 'jsc_coordinator';
    final shortcuts = user == null
        ? const <String>{}
        : AssistantShortcutPolicy.visibleKeys(
            user,
            liveOperationsMapEnabled:
                context.watch<ConfigService>().liveOperationsMapEnabled,
          );
    return Scaffold(
      backgroundColor: const Color(0xFFF3F8F5),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF7FBF8), Color(0xFFEAF6F0), Color(0xFFDDF3EC)])),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(compact ? 14 : 18, 14, compact ? 14 : 18, 120),
            children: [
              Row(children: [
                const AiFeatureIcon('operations', size: 18), const SizedBox(width: 10),
                Expanded(child: AppText('المساعد التشغيلي الذكي', style: TextStyle(color: cleanOpsText, fontSize: titleSize, fontWeight: FontWeight.w900))),
                _LanguagePill(onTap: _toggleLanguage, isArabic: locale.isArabic),
              ]),
              const SizedBox(height: 8),
              const AppText('اسأل عن العمليات والبيانات المتاحة لصلاحياتك', style: TextStyle(color: cleanOpsMuted, fontSize: 12)),
              const SizedBox(height: 10),
              if (!allowed)
                const _AccessNotice()
              else ...[
                Builder(builder: (context) {
                  final settings = context.watch<ConfigService>();
                  final ready = settings.aiEnabled && settings.aiApiKey.trim().isNotEmpty;
                  if (ready) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AiGlassCard(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        const Icon(Icons.info_outline_rounded, color: Colors.orange),
                        const SizedBox(width: 10),
                        Expanded(child: AppText(
                          !settings.aiEnabled
                              ? 'المساعد المحلي يعمل دون API. الذكاء الخارجي اختياري.'
                              : 'المساعد المحلي جاهز. لا تحتاج إلى مفتاح API.',
                          style: const TextStyle(color: cleanOpsText, fontSize: 12),
                        )),
                      ]),
                    ),
                  );
                }),
                FutureBuilder<Map<String, dynamic>>(
                  future: context.read<OperationsAdminService>().liveOperationalSnapshot(user!),
                  builder: (context, snap) {
                    if (!snap.hasData) return const SizedBox.shrink();
                    final x = snap.data!;
                    return AiGlassCard(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [AiFeatureIcon('dashboard', size: 16), SizedBox(width: 8), AppText('بيانات تشغيلية حقيقية', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)), Spacer(), AppText('Firestore', style: TextStyle(fontSize: 9, color: aiGreen))]),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [_LiveChip('العمال', '${x['workers']}'), _LiveChip('المجموعات', '${x['groups']}'), _LiveChip('الترحيلات', '${x['trips']}'), _LiveChip('الطوارئ', '${x['emergencies']}'), _LiveChip('المكبات الحرجة', '${x['criticalDumpsites']}')]),

                    ]));
                  },
                ),
                if (user.can('dumpsite', 'view'))
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance.collection('dumpsites')
                        .where('isActive', isEqualTo: true).limit(500).snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox.shrink();
                      final critical = snapshot.data!.docs.where((doc) {
                        final data = doc.data();
                        if (data['isDeleted'] == true) return false;
                        final value = data['fillPercentage'];
                        final fill = value is num ? value.toDouble()
                            : double.tryParse('$value') ?? 0;
                        return fill >= 85;
                      }).length;
                      if (critical == 0) return const SizedBox.shrink();
                      return AiGlassCard(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppText('تنبيه مباشر: $critical مكب بنسبة امتلاء 85% أو أكثر.',
                                style: const TextStyle(color: Color(0xFF9A4D06),
                                    fontWeight: FontWeight.w700, fontSize: 12)),
                            if (snapshot.data!.metadata.isFromCache)
                              const AppText('البيانات من ذاكرة الجهاز؛ قد لا تكون محدثة.',
                                  style: TextStyle(fontSize: 10, color: cleanOpsMuted)),
                            TextButton.icon(
                              onPressed: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => user.role == 'jsc_coordinator'
                                    ? const OperationsManagementScreen(initialTab: 0)
                                    : const EnterpriseOperationsHubPage(),
                              )),
                              icon: const Icon(Icons.open_in_new_rounded, size: 16),
                              label: const AppText('فتح إدارة المكبات'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 10),
                _ChatPanel(messages: messages, loading: loading, input: input, controller: chatScroll, onSend: _send),
                if (linkedRecords.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  AiGlassCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [
                          Icon(Icons.link_rounded, size: 17, color: aiCyan),
                          SizedBox(width: 7),
                          AppText('السجلات المرتبطة بالتحليل', style: TextStyle(fontWeight: FontWeight.w900)),
                        ]),
                        const SizedBox(height: 8),
                        ...linkedRecords.map((record) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: AiFeatureIcon(record.feature, size: 14),
                          title: AppText(record.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                          subtitle: AppText(record.subtitle, style: const TextStyle(fontSize: 10, color: cleanOpsMuted)),
                          trailing: const Icon(Icons.open_in_new_rounded, size: 17),
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => _AssistantRecordPage(record: record),
                          )),
                        )),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _BotAction(icon: Icons.analytics_rounded, title: 'ملخص اليوم', onTap: () { input.text = 'أعطني ملخصًا لعمليات اليوم بالأرقام الحقيقية.'; _send(); }),
                  _BotAction(icon: Icons.insights_rounded, title: 'تحليل المخاطر', onTap: () { input.text = 'ما أهم مخاطر التشغيل وتأخر الترحيلات ونقص العمال؟'; _send(); }),
                  _BotAction(icon: Icons.warning_amber_rounded, title: 'التنبيهات', onTap: () { input.text = 'ما حالات SOS والطوارئ النشطة الآن؟'; _send(); }),
                  _BotAction(icon: Icons.delete_sweep_rounded, title: 'المكبات', onTap: () { input.text = 'اعرض حالة المكبات ونسب الامتلاء الحالية.'; _send(); }),
                  _BotAction(icon: Icons.local_shipping_rounded, title: 'الترحيلات', onTap: () { input.text = 'كم عدد الترحيلات المسجلة اليوم؟'; _send(); }),
                ]),
                const SizedBox(height: 12),
                LayoutBuilder(builder: (context, constraints) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (shortcuts.contains('messages'))
                      _BotAction(icon: Icons.forum_rounded, title: 'الرسائل', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MessagesCenterScreen()))),
                    if (shortcuts.contains('operations'))
                      _BotAction(icon: Icons.hub_rounded, title: 'مركز التشغيل', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EnterpriseOperationsHubPage()))),
                    if (shortcuts.contains('trips'))
                      _BotAction(icon: Icons.route_rounded, title: 'سجل النقلات', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TripsLogPage()))),
                    if (shortcuts.contains('workers'))
                      _BotAction(icon: Icons.groups_rounded, title: 'المجموعات والعمال', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupsCommandCenterPage()))),
                    if (shortcuts.contains('alerts'))
                      _BotAction(icon: Icons.notification_important_rounded, title: 'مركز التنبيهات', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertsCenterPage()))),
                    if (shortcuts.contains('reports'))
                      _BotAction(icon: Icons.description_rounded, title: 'التقارير', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsCenterScreen()))),
                    if (shortcuts.contains('report_pdf'))
                      _BotAction(icon: Icons.picture_as_pdf_rounded, title: exportingPdf ? 'جاري تجهيز PDF' : 'تقرير PDF لفترة محددة', onTap: _exportPeriodPdf),
                    if (shortcuts.contains('dumpsites'))
                      _BotAction(icon: Icons.location_on_rounded, title: 'المكبات', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OperationsManagementScreen(initialTab: 0)))),
                    if (shortcuts.contains('live_map'))
                      _BotAction(icon: Icons.map_rounded, title: 'العمليات الحية', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveOperationsMapScreen()))),
                  ],
                )),
              ],
              const SizedBox(height: 16),
              const AppText('Developed by @Eman Al-Qahwaji', textAlign: TextAlign.center, style: TextStyle(color: aiDark2, fontSize: 10, letterSpacing: .45, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}


class _AssistantRecordPage extends StatelessWidget {
  final _LinkedOperationalRecord record;
  const _AssistantRecordPage({required this.record});

  bool _allowed(AppUser user, Map<String, dynamic> data) {
    if (record.collection == 'dumpsites') return user.can('dumpsite', 'view');
    if (record.collection == 'users') {
      return user.can('workers', 'view') && OperationalInsights.visibleToUser(
        data, role: user.role, userId: user.id, scope: user.scope, groupId: user.groupId,
      );
    }
    final entity = '${data['_entity'] ?? ''}';
    final feature = entity == 'trip'
        ? 'trips'
        : (entity == 'emergency' || entity == 'notification')
            ? 'emergency'
            : entity == 'worker' || entity == 'group'
                ? 'workers'
                : 'operations';
    return user.can(feature, 'view') && OperationalInsights.visibleToUser(
      data, role: user.role, userId: user.id, scope: user.scope, groupId: user.groupId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    if (user == null) return const Scaffold(body: Center(child: AppText('انتهت جلسة المستخدم.')));
    final ref = FirebaseFirestore.instance.collection(record.collection).doc(record.id);
    return Scaffold(
      appBar: AppBar(title: AppText(record.title)),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? record.data;
          if (!_allowed(user, data)) {
            return const Center(child: AppText('لا تملك صلاحية عرض هذا السجل.'));
          }
          if (snapshot.hasData && snapshot.data?.exists == false) {
            return const Center(child: AppText('لم يعد هذا السجل موجودًا في Firebase.'));
          }
          final fields = <String, Object?>{
            'الاسم': data['name'] ?? data['nameAr'] ?? data['fullName'] ?? data['workerName'],
            'النوع': data['_entity'] ?? data['role'],
            'الحالة': data['status'] ?? (data['isActive'] == true ? 'نشط' : null),
            'المجموعة': data['groupName'] ?? data['groupId'],
            'البلدية': data['municipalityName'] ?? data['municipality'],
            'الموقع': data['location'] ?? data['street'],
            'المكب / الوجهة': data['landfill'] ?? data['destination'],
            'نسبة الامتلاء': data['fillPercentage'] == null ? null : '${data['fillPercentage']}%',
            'السعة': data['capacity'],
            'الهاتف': data['phone'],
            'الموعد المستهدف': data['deadlineAt'] ?? data['dueAt'] ?? data['expectedArrivalAt'],
            'تاريخ التسجيل': data['createdAt'] ?? data['timestamp'],
            'معرّف Firebase': record.id,
          };
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              AiSectionCard(
                title: record.title,
                subtitle: snapshot.data?.metadata.isFromCache == true
                    ? 'سجل Firebase مخزن على الجهاز؛ قد لا يكون محدثًا'
                    : 'سجل Firebase مباشر',
                feature: record.feature,
                child: Column(
                  children: fields.entries
                      .where((entry) => entry.value != null && '${entry.value}'.trim().isNotEmpty)
                      .map((entry) => ListTile(
                        dense: true,
                        title: AppText(entry.key, style: const TextStyle(fontSize: 11, color: cleanOpsMuted)),
                        subtitle: AppText('${entry.value}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ))
                      .toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}


class _ChatPanel extends StatelessWidget {
  final List<_ChatMessage> messages;
  final bool loading;
  final TextEditingController input;
  final ScrollController controller;
  final VoidCallback onSend;
  const _ChatPanel({required this.messages, required this.loading, required this.input, required this.controller, required this.onSend});
  @override Widget build(BuildContext context) => AiGlassCard(padding: const EdgeInsets.all(10), child: Column(children: [
    SizedBox(height: MediaQuery.sizeOf(context).height < 760 ? 250 : 300, child: ListView.builder(controller: controller, padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4), itemCount: messages.length + (loading ? 1 : 0), itemBuilder: (_, i) {
      if (loading && i == messages.length) return const _TypingBubble();
      final m = messages[i];
      return Align(alignment: m.fromUser ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd, child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), constraints: const BoxConstraints(maxWidth: 520), decoration: BoxDecoration(color: m.fromUser ? const Color(0xFFDDF4ED) : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: (m.fromUser ? aiCyan : aiGreen).withOpacity(.20))), child: AppText(m.text, style: const TextStyle(color: cleanOpsText, fontSize: 14, height: 1.55))));
    })),
    const SizedBox(height: 8),
    Row(children: [Expanded(child: TextField(controller: input, minLines: 1, maxLines: 4, onSubmitted: (_) => onSend(), textInputAction: TextInputAction.send, decoration: InputDecoration(hintText: tr('اكتب سؤالك التشغيلي...'), prefixIcon: Icon(Icons.auto_awesome_rounded, color: aiCyan)))), const SizedBox(width: 8), IconButton(onPressed: loading ? null : onSend, icon: const Icon(Icons.send_rounded, color: aiCyan))]),
  ]));
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();
  @override Widget build(BuildContext context) => Align(alignment: AlignmentDirectional.centerEnd, child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: aiCyan))));
}

class _AccessNotice extends StatelessWidget {
  const _AccessNotice();
  @override Widget build(BuildContext context) => const AiGlassCard(padding: EdgeInsets.all(16), child: Row(children: [Icon(Icons.lock_outline_rounded, color: Colors.orange), SizedBox(width: 10), Expanded(child: AppText('CleanOps AI التحليلي متاح للمستوى 3 والمستوى 4 فقط، حفاظًا على بيانات الإدارة.', style: TextStyle(color: cleanOpsMuted, fontSize: 14, height: 1.55)))]));
}

class _LiveChip extends StatelessWidget {
  final String title, value;
  const _LiveChip(this.title, this.value);
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7), decoration: BoxDecoration(color: aiCyan.withOpacity(.07), borderRadius: BorderRadius.circular(12), border: Border.all(color: aiCyan.withOpacity(.16))), child: Row(mainAxisSize: MainAxisSize.min, children: [AppText(title, style: const TextStyle(fontSize: 11, color: cleanOpsMuted)), const SizedBox(width: 6), AppText(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: aiCyan))]));
}

class _LanguagePill extends StatelessWidget {
  final VoidCallback onTap;
  final bool isArabic;
  const _LanguagePill({required this.onTap, required this.isArabic});
  @override Widget build(BuildContext context) => Material(color: aiBlue.withOpacity(.08), borderRadius: BorderRadius.circular(22), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(22), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.language_rounded, color: Color(0xFF6FE8FF), size: 17), const SizedBox(width: 5), AppText(isArabic ? 'English' : 'العربية', style: const TextStyle(color: cleanOpsText, fontSize: 13, fontWeight: FontWeight.w800))]))));
}

class _BotCoreAnimation extends StatelessWidget {
  final AnimationController orbitController;
  final AnimationController glowController;
  final AnimationController entranceController;
  final double width;
  const _BotCoreAnimation({required this.orbitController, required this.glowController, required this.entranceController, required this.width});

  @override
  Widget build(BuildContext context) {
    final size = math.min(width * .55, 250.0);
    return AnimatedBuilder(
      animation: Listenable.merge([orbitController, glowController, entranceController]),
      builder: (context, child) {
        final t = orbitController.value * math.pi * 2;
        final glow = 0.72 + (math.sin(glowController.value * math.pi * 2) + 1) * .14;
        final entrance = Curves.easeOutBack.transform(entranceController.value);
        final rings = <Widget>[
          for (final factor in [0.82, 0.68, 0.54])
            Container(
              width: size * factor,
              height: size * factor,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF18D7FF).withOpacity(.10 * glow), width: 1.2),
              ),
            ),
        ];
        return Opacity(
          opacity: entranceController.value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: .82 + .18 * entrance,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: size * .72,
                    height: size * .72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF18D7FF).withOpacity(.20 * glow), blurRadius: 70, spreadRadius: 18),
                        BoxShadow(color: const Color(0xFF00E676).withOpacity(.12 * glow), blurRadius: 45, spreadRadius: 6),
                      ],
                    ),
                  ),
                  ...rings,
                  Transform.rotate(
                    angle: t,
                    child: Container(
                      width: size * .76,
                      height: size * .76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF18D7FF).withOpacity(.48), width: 2),
                      ),
                    ),
                  ),
                  Container(
                    width: size * .48,
                    height: size * .48,
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFEAF6F0),
                      border: Border.all(color: const Color(0xFF18D7FF).withOpacity(.82), width: 2),
                      boxShadow: [BoxShadow(color: const Color(0xFF18D7FF).withOpacity(.34 * glow), blurRadius: 32, spreadRadius: 4)],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/brand/cleanops_icon_new.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.eco_rounded, color: aiCyan, size: 70),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BotAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _BotAction({required this.icon, required this.title, required this.onTap});
  @override Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11), decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.white, const Color(0xFFF0FAF5)]), borderRadius: BorderRadius.circular(16), border: Border.all(color: aiCyan.withOpacity(.24))), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: aiBlue, size: 20), const SizedBox(width: 7), Flexible(child: AppText(title, textAlign: TextAlign.center, style: const TextStyle(color: cleanOpsText, fontSize: 13, fontWeight: FontWeight.w800)))])));
}
