import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../models/core_models.dart';
import 'config_service.dart';
import 'operational_insights.dart';

class AIService {
  final FirebaseFirestore firestore;
  final ConfigService config;

  AIService({FirebaseFirestore? firestore, required this.config})
      : firestore = firestore ?? FirebaseFirestore.instance;

  Future<String> answer({required AppUser user, required String question}) async {
    if (!user.isActive || !user.can('operations', 'view')) {
      throw StateError('هذا الحساب غير نشط أو لا يملك صلاحية عرض العمليات.');
    }
    if (user.role != 'donor_manager' && user.role != 'jsc_coordinator') {
      throw StateError('المساعد الذكي متاح للمستوى 3 والمستوى 4 فقط.');
    }
    final localAnswer = await _answerLocally(user, question);
    if (localAnswer != null) return localAnswer;
    if (!config.aiEnabled || config.aiApiKey.trim().isEmpty) {
      return 'المساعد المحلي متاح دون مفتاح API. اسأل عن ملخص اليوم أو العمال أو المجموعات أو الترحيلات أو الطوارئ أو المكبات.';
    }
    if (!config.aiEnabled) {
      throw StateError('المساعد الذكي غير مفعّل. يمكن للمستوى 3 أو 4 تفعيله وإضافة مفتاح API من الإعدادات.');
    }
    final apiKey = config.aiApiKey.trim();
    if (apiKey.isEmpty) {
      throw StateError('مفتاح OpenAI غير مضبوط. افتح إعدادات الذكاء الاصطناعي وأدخل المفتاح بأمان.');
    }
    final prompt = await _buildPrompt(user, question);
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/responses'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': config.aiModel.trim().isEmpty ? 'gpt-4.1-mini' : config.aiModel.trim(),
        'instructions': 'أنت CleanOps AI، مساعد تشغيلي لمنظومة إدارة النفايات الصلبة. استخدم فقط البيانات التشغيلية الموجودة في السياق المرفق. لا تخترع أرقامًا أو مستخدمين أو ترحيلات أو تنبيهات. إذا كانت المعلومة غير موجودة فقل بوضوح إنها غير متاحة. لا تنفذ أي إجراء تشغيلي أو تغيّر بيانات؛ أنت مساعد تحليلي فقط. احترم مستوى المستخدم وصلاحياته. أجب بالعربية إذا كان السؤال عربيًا وبالإنجليزية إذا كان السؤال إنجليزيًا. اجعل الإجابة مختصرة ومفيدة للإدارة.',
        'input': prompt,
        'store': false,
        'max_output_tokens': 900,
      }),
    ).timeout(Duration(seconds: config.apiTimeoutSeconds.clamp(10, 120)));

    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = body['error'];
      final message = error is Map
          ? '${error['message'] ?? 'تعذر الاتصال بخدمة الذكاء الاصطناعي.'}'
          : 'تعذر الاتصال بخدمة الذكاء الاصطناعي (${response.statusCode}).';
      if (response.statusCode == 401) throw StateError('مفتاح API غير صالح. راجع إعدادات الذكاء الاصطناعي.');
      if (response.statusCode == 429) throw StateError('تم بلوغ حد استخدام خدمة الذكاء الاصطناعي. حاول لاحقًا أو راجع الرصيد.');
      if (response.statusCode == 404) throw StateError('نموذج الذكاء الاصطناعي غير متاح. راجع اسم النموذج في الإعدادات.');
      throw StateError(message);
    }
    final outputText = body['output_text'];
    if (outputText is String && outputText.trim().isNotEmpty) return outputText.trim();
    final output = body['output'];
    if (output is List) {
      for (final item in output) {
        if (item is Map && item['content'] is List) {
          for (final content in item['content']) {
            if (content is Map && content['text'] is String && '${content['text']}'.trim().isNotEmpty) {
              return '${content['text']}'.trim();
            }
          }
        }
      }
    }
    throw StateError('لم تُرجع خدمة الذكاء الاصطناعي نصًا صالحًا.');
  }

  static String _normalizeArabic(String input) {
    return input.toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
        .replaceAll(RegExp('[أإآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'[^\u0621-\u064A\u0660-\u0669a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<String?> _answerLocally(AppUser user, String question) async {
    final q = _normalizeArabic(question);
    bool has(List<String> terms) => terms.any((term) => q.contains(_normalizeArabic(term)));
    final summary = has(['ملخص', 'اليوم', 'تقرير', 'احصائيات', 'احصاء', 'الوضع العام', 'شو الوضع', 'كيف الوضع', 'اعطيني الوضع', 'summary', 'overview']);
    final workers = has(['عمال', 'عامل', 'موظفين', 'موظف', 'الطاقم', 'القوى العاملة', 'workforce', 'worker']);
    final groups = has(['مجموعة', 'مجموعات', 'المجموعه', 'الفرق', 'فريق', 'الفرق الميدانية', 'group', 'team']);
    final trips = has(['ترحيل', 'ترحيلات', 'رحلات', 'نقل النفايات', 'النقلات', 'حمولات', 'الشحنات', 'trip', 'load']);
    final alerts = has(['طوارئ', 'تنبيه', 'انذارات', 'بلاغات', 'بلاغ', 'استغاثة', 'sos', 'emergency', 'alert']);
    final sites = has(['مكب', 'مكبات', 'مكبات النفايات', 'امتلاء', 'المطامر', 'مطمر', 'مواقع التخلص', 'dumpsite', 'landfill']);
    final risks = has(['مخاطر', 'تأخر', 'متأخر', 'مشاكل التشغيل', 'اولويات', 'توصيات', 'نقص العمال', 'risk', 'overdue']);
    if (!(summary || workers || groups || trips || alerts || sites || risks)) return null;
    final data = await _fetchOperationalContext(user);
    final lines = <String>[];
    if (summary) lines.add('ملخص التشغيل بتاريخ ${data['date']}:');
    if (summary || workers) lines.add('العمال النشطون: ${data['activeWorkers']}، المشرفون: ${data['activeGroupSupervisors']}');
    if (summary || groups || risks) lines.add('المجموعات النشطة: ${data['activeGroups']}');
    if (summary || workers || groups || risks) {
      final gaps = data['supervisedGroupsWithoutWorkers'] as int;
      if (gaps > 0) lines.add('تنبيه توزيع: $gaps مجموعة لديها مشرف نشط دون عمال نشطين ضمن البيانات المقروءة.');
    }
    if (summary || trips || risks) {
      lines.add('الترحيلات اليوم: ${data['loadsTransferredToday']}');
      final assessed = data['assessableTripDeadlines'] as int;
      final overdue = data['overdueTrips'] as int;
      if (assessed == 0) {
        lines.add('تأخر الترحيلات: لا توجد رحلات بمواعيد إنجاز وحالات مفتوحة قابلة للتحقق ضمن البيانات المقروءة.');
      } else {
        lines.add('ترحيلات تجاوزت موعد الإنجاز: $overdue من أصل $assessed رحلة قابلة للتقييم.');
        if (overdue > 0) lines.add('أولوية متابعة: راجع الرحلات المتأخرة في شاشة الترحيلات.');
      }
    }
    if (summary || alerts || risks) {
      lines.add('حالات الطوارئ غير المغلقة: ${data['activeSOSorEmergencies']}');
      if ((data['activeSOSorEmergencies'] as int) > 0) lines.add('تنبيه تشغيلي: توجد حالات طوارئ تحتاج مراجعة في شاشة العمليات.');
    }
    if (summary || sites || risks) {
      lines.add('المكبات النشطة: ${data['activeDumpsites']}');
      final critical = (data['dumpsites'] as List).where((site) => (site['fillPercentage'] as num) >= 85).length;
      if (critical > 0) lines.add('تنبيه تشغيلي: $critical مكب/مكبات بنسبة امتلاء 85% أو أكثر. يُنصح بمراجعة السعة المتاحة قبل توجيه الترحيلات.');
      final items = data['dumpsites'] as List;
      for (final item in items.take(12)) {
        lines.add('• ${item['name']}: الامتلاء ${item['fillPercentage']}%');
      }
    }
    if (summary) lines.addAll(_buildProactiveInsights(data));
    if (data['scopeLimited'] == true) {
      lines.add('النطاق: بيانات المجلس المحددة فقط. السجلات دون هوية مجلس أو بلدية واضحة لا تدخل في المؤشرات.');
    }
    if (data['dataMayBeIncomplete'] == true) {
      lines.add('تنبيه دقة: وصلت إحدى القراءات إلى حد السجلات؛ الأعداد تخص العينة المقروءة وليست بالضرورة إجمالي النظام.');
    }
    lines.add(data['source'] == 'Firestore server data'
        ? 'المصدر: Firebase / Firestore (اتصال بالخادم).'
        : 'المصدر: نسخة Firestore المخزنة على الجهاز؛ قد تكون قديمة أو غير مكتملة.');
    return lines.join('\n');
  }

  Future<String> _buildPrompt(AppUser user, String question) async {
    final context = await _fetchOperationalContext(user);
    return 'السؤال من المستخدم: $question\n\nالسياق التشغيلي الحقيقي من Firestore (تم جلبه الآن):\n${_pretty(context)}\n\nأجب اعتمادًا على هذا السياق فقط. عند السؤال عن اليوم استخدم تاريخ اليوم المذكور في السياق.';
  }

  Future<Map<String, dynamic>> _fetchOperationalContext(AppUser user) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    final usersSnap = await _readQuery(firestore.collection('users').where('isActive', isEqualTo: true).limit(1000));
    var activeWorkers = 0;
    var activeSupervisors = 0;
    final groups = <String>{};
    bool visible(Map<String, dynamic> record) => OperationalInsights.visibleToUser(
      record, role: user.role, userId: user.id,
      scope: user.scope, groupId: user.groupId,
    );
    final scopedUsers = usersSnap.docs.where((doc) => visible(doc.data())).toList();
    for (final doc in scopedUsers) {
      final data = doc.data();
      final role = '${data['role'] ?? ''}';
      if (role == 'worker') activeWorkers++;
      if (role == 'group_supervisor') activeSupervisors++;
      final groupId = '${data['groupId'] ?? ''}'.trim();
      if (groupId.isNotEmpty) groups.add(groupId);
    }

    final coverageGaps = OperationalInsights.supervisedGroupsWithoutWorkers(scopedUsers.map((d) => d.data()));

    final dumpsitesSnap = await _readQuery(firestore.collection('dumpsites').where('isActive', isEqualTo: true).limit(500));
    final dumpsites = <Map<String, dynamic>>[];
    for (final doc in dumpsitesSnap.docs) {
      final d = doc.data();
      final capacity = _number(d['capacity']);
      final fill = _number(d['fillPercentage']);
      dumpsites.add({
        'name': '${d['nameAr'] ?? d['name'] ?? doc.id}',
        'capacity': capacity,
        'fillPercentage': fill,
        'availableCapacity': capacity > 0 ? capacity * (1 - fill / 100) : null,
      });
    }

    final opsSnap = await _readQuery(firestore.collection('operations').limit(1500));
    var loadsToday = 0;
    var activeEmergencies = 0;
    final tripDocuments = <Map<String, dynamic>>[];
    final addressedEmergencies = opsSnap.docs.where((doc) {
      final record = doc.data();
      return record['_entity'] == 'notification' &&
          record['sourceEntity'] == 'emergency' && visible(record);
    }).map((doc) => '${doc.data()['sourceId'] ?? ''}'.trim())
        .where((id) => id.isNotEmpty).toSet();
    for (final doc in opsSnap.docs) {
      final d = doc.data();
      if (!visible(d) && !(d['_entity'] == 'emergency' && addressedEmergencies.contains(doc.id))) continue;
      final created = _parseDate(d['createdAt']);
      final entity = '${d['_entity'] ?? ''}';
      if (entity == 'trip' && d['isDeleted'] != true) {
        final trip = Map<String, dynamic>.from(d);
        for (final field in const ['deadlineAt', 'dueAt', 'expectedCompletionAt', 'expectedArrivalAt', 'plannedEndAt']) {
          if (trip[field] is Timestamp) trip[field] = (trip[field] as Timestamp).toDate();
        }
        tripDocuments.add(trip);
      }
      if (entity == 'trip' && created != null && !created.isBefore(start) && created.isBefore(end) && d['isDeleted'] != true) {
        loadsToday++;
      }
      if (entity == 'emergency' && d['isDeleted'] != true) {
        final status = '${d['status'] ?? ''}'.toLowerCase();
        if (OperationalInsights.isOpenAlert(d) && status != 'completed') {
          activeEmergencies++;
        }
      }
    }

    final reviewedTrips = OperationalInsights.reviewTrips(tripDocuments, now: now);

    return {
      'supervisedGroupsWithoutWorkers': coverageGaps,
      'assessableTripDeadlines': reviewedTrips.assessable,
      'overdueTrips': reviewedTrips.overdue,
      'date': '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}',
      'managementLevel': user.role == 'donor_manager' ? 4 : 3,
      'activeWorkers': activeWorkers,
      'activeGroupSupervisors': activeSupervisors,
      'activeGroups': groups.length,
      'scopeLimited': user.role == 'jsc_coordinator',
      'loadsTransferredToday': loadsToday,
      'activeSOSorEmergencies': activeEmergencies,
      'activeDumpsites': dumpsites.length,
      'dumpsites': dumpsites,
      'source': (usersSnap.metadata.isFromCache || dumpsitesSnap.metadata.isFromCache || opsSnap.metadata.isFromCache)
          ? 'Firestore offline cached data; potentially stale or incomplete'
          : 'Firestore server data',
      'dataMayBeIncomplete': usersSnap.docs.length >= 1000 || dumpsitesSnap.docs.length >= 500 || opsSnap.docs.length >= 1500,
    };
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _readQuery(
    Query<Map<String, dynamic>> query,
  ) async {
    try {
      return await query.get(const GetOptions(source: Source.server));
    } on FirebaseException catch (error) {
      if (error.code != 'unavailable' && error.code != 'deadline-exceeded') rethrow;
      return query.get(const GetOptions(source: Source.cache));
    }
  }

  List<String> _buildProactiveInsights(Map<String, dynamic> data) {
    final insights = <String>[];
    final emergencies = data['activeSOSorEmergencies'] as int? ?? 0;
    final uncoveredGroups = data['supervisedGroupsWithoutWorkers'] as int? ?? 0;
    final assessableTrips = data['assessableTripDeadlines'] as int? ?? 0;
    final overdueTrips = data['overdueTrips'] as int? ?? 0;
    final dumpsites = (data['dumpsites'] as List?) ?? const [];
    final criticalSites = dumpsites.where((site) {
      if (site is! Map) return false;
      final fill = site['fillPercentage'];
      final value = fill is num ? fill.toDouble() : double.tryParse('$fill') ?? 0;
      return value >= 85;
    }).length;

    if (emergencies > 0) {
      insights.add('أولوية عالية: توجد $emergencies حالة طوارئ غير مغلقة تحتاج متابعة.');
    }
    if (criticalSites > 0) {
      insights.add('أولوية عالية: يوجد $criticalSites مكب بنسبة امتلاء 85% أو أكثر.');
    }
    if (overdueTrips > 0) {
      insights.add('تنبيه ترحيلات: توجد $overdueTrips رحلة متأخرة وفق موعد مستهدف مسجل.');
    } else if (assessableTrips > 0) {
      insights.add('الترحيلات: لا توجد رحلات متأخرة ضمن $assessableTrips رحلة لها موعد مستهدف قابل للتقييم.');
    } else {
      insights.add('ملاحظة ترحيلات: لا توجد مواعيد مستهدفة كافية لتقييم التأخر بشكل موثوق.');
    }
    if (uncoveredGroups > 0) {
      insights.add('تنبيه موارد: توجد $uncoveredGroups مجموعة بإشراف نشط دون عامل نشط مسجل.');
    }
    if (emergencies == 0 && criticalSites == 0 && overdueTrips == 0 && uncoveredGroups == 0) {
      insights.add('لا تظهر مؤشرات تشغيلية حرجة ضمن البيانات المقروءة والقواعد الحالية.');
    }
    return insights;
  }

  double _number(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return DateTime.tryParse('$value');
  }

  String _pretty(Map<String, dynamic> data) {
    final buffer = StringBuffer();
    data.forEach((key, value) {
      if (key == 'dumpsites' && value is List) {
        buffer.writeln('dumpsites:');
        for (final site in value) {
          buffer.writeln('- ${site['name']}: capacity=${site['capacity']}, fill=${site['fillPercentage']}%, available=${site['availableCapacity']}');
        }
      } else {
        buffer.writeln('$key: $value');
      }
    });
    return buffer.toString();
  }
}
