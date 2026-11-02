import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/localization.dart';
import '../../core/models/core_models.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/data_service.dart';
import '../../core/services/notification_target_policy.dart';
import '../widgets/app_navigation_bar.dart';

class NotificationRecordScreen extends StatefulWidget {
  final NotificationItem notice;
  final String userId;
  const NotificationRecordScreen({
    super.key,
    required this.notice,
    required this.userId,
  });
  @override
  State<NotificationRecordScreen> createState() =>
      _NotificationRecordScreenState();
}

class _NotificationRecordScreenState extends State<NotificationRecordScreen> {
  late Future<Map<String, dynamic>?> _record;
  late NotificationItem _notice;
  bool _verifiedRecipient = false;
  bool _cached = false;

  @override
  void initState() {
    super.initState();
    _notice = widget.notice;
    _record = _load();
  }

  Future<Map<String, dynamic>?> _get(String id) async {
    if (id.isEmpty || id.contains('/')) throw const FormatException();
    final data = context.read<DataService>();
    if (data.online && Firebase.apps.isNotEmpty) {
      // Fetch the exact document; list limits and filters cannot hide it.
      final doc = await FirebaseFirestore.instance
          .collection('operations')
          .doc(id)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      return doc.exists ? {...doc.data()!, 'id': doc.id} : null;
    }
    _cached = true;
    for (final record in data.operations) {
      if ('${record['id']}' == id) return record;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _load() async {
    _cached = false;
    _verifiedRecipient = false;
    // Old local inbox entries may lack metadata. Recover it only from the
    // exact authorized notification record, never by guessing from its body.
    if (_notice.sourceId == null || _notice.sourceId!.isEmpty) {
      final original = _notice.level == 'success'
          ? null
          : await _get(_notice.id);
      if (!mounted) return null;
      if (original != null && original['_entity'] == 'notification') {
        _notice = NotificationItem.fromJson({...original, 'id': _notice.id});
        final user = context.read<AuthService>().currentUser;
        _verifiedRecipient =
            user != null &&
            original['targetUserId'] == user.id &&
            original['targetRole'] == user.role;
      }
    }
    if (!mounted) return null;
    final user = context.read<AuthService>().currentUser;
    if (user == null ||
        user.id != widget.userId ||
        !NotificationTargetPolicy.addressedTo(user, _notice)) {
      throw StateError('هذا الإشعار غير متاح ضمن صلاحيات حسابك.');
    }
    if (_notice.sourceId == null || _notice.sourceId!.isEmpty) {
      await context.read<DataService>().markRead(widget.notice.id);
      return null; // Informational notice: display its complete content.
    }
    final record = await _get(_notice.sourceId!);
    if (!mounted) return null;
    final current = context.read<AuthService>().currentUser;
    if (current == null || current.id != widget.userId) {
      throw StateError('تغير الحساب؛ افتح الإشعار من حسابك الحالي.');
    }
    if (record == null)
      throw StateError(
        _cached
            ? 'السجل غير محفوظ على هذا الجهاز. اتصل بالإنترنت ثم أعد المحاولة.'
            : 'السجل المرتبط لم يعد موجودًا.',
      );
    if (current.role == 'municipality_coordinator' &&
        _notice.sourceEntity == 'emergency' &&
        record['municipalityCoordinatorId'] != current.id) {
      final assignment = await _get('${_notice.sourceId}_L2');
      if (!mounted) return null;
      _verifiedRecipient =
          assignment != null &&
          assignment['_entity'] == 'notification' &&
          assignment['sourceEntity'] == 'emergency' &&
          assignment['sourceId'] == _notice.sourceId &&
          assignment['targetUserId'] == current.id &&
          assignment['targetRole'] == current.role;
    }
    final active = context.read<AuthService>().currentUser;
    if (active == null || active.id != widget.userId) {
      throw StateError('تغير الحساب؛ افتح الإشعار من حسابك الحالي.');
    }
    if (!NotificationTargetPolicy.canOpen(
      active,
      _notice,
      record,
      verifiedRecipient: _verifiedRecipient,
    )) {
      throw StateError('السجل محذوف أو غير متاح ضمن صلاحيات حسابك.');
    }
    // A failed open must not consume the unread indicator.
    await context.read<DataService>().markRead(widget.notice.id);
    return record;
  }

  static const _labels = {
    'id': 'رقم السجل',
    'title': 'العنوان',
    'body': 'التفاصيل',
    'description': 'الوصف',
    'issue': 'المشكلة',
    'street': 'الشارع / الموقع',
    'status': 'الحالة',
    'groupName': 'المجموعة',
    'municipalityName': 'البلدية',
    'landfill': 'المكب / الوجهة',
    'estimatedQuantity': 'الكمية التقديرية (طن)',
    'quantity': 'الكمية',
    'latitude': 'خط العرض',
    'longitude': 'خط الطول',
    'createdAt': 'تاريخ التسجيل',
    'acknowledgedAt': 'تاريخ تأكيد الاستلام',
    'resolutionNote': 'توثيق المعالجة',
    'closedAt': 'تاريخ الإغلاق',
    'caption': 'وصف الصورة',
    'phase': 'مرحلة التوثيق',
  };

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final allowed =
        user != null &&
        user.id == widget.userId &&
        NotificationTargetPolicy.addressedTo(user, _notice);
    return Scaffold(
      appBar: AppBar(
        title: AppText(widget.notice.title),
        bottom: const AppNavigationBar(),
      ),
      body: !allowed
          ? const Center(child: AppText('الإشعار غير متاح لهذا الحساب.'))
          : FutureBuilder<Map<String, dynamic>?>(
              future: _record,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  final error = snapshot.error;
                  final message = error is StateError
                      ? error.message
                      : 'تعذر فتح السجل. تحقق من الاتصال وصلاحية الوصول ثم أعد المحاولة.';
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppText(message, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => setState(() => _record = _load()),
                            child: const AppText('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final record = snapshot.data;
                if (record != null &&
                    !NotificationTargetPolicy.canOpen(
                      user!,
                      _notice,
                      record,
                      verifiedRecipient: _verifiedRecipient,
                    )) {
                  return const Center(
                    child: AppText('لم تعد لديك صلاحية لعرض هذا السجل.'),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppText(widget.notice.body),
                            if (record == null)
                              const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: AppText(
                                  'إشعار معلوماتي؛ لا يحتوي على رابط لسجل محدد.',
                                ),
                              ),
                            if (_cached && record != null)
                              const AppText(
                                'نسخة محفوظة على الجهاز؛ قد تكون الحالة تغيرت.',
                              ),
                            if (record != null)
                              ..._labels.entries
                                  .where(
                                    (e) =>
                                        record[e.key] != null &&
                                        '${record[e.key]}'.isNotEmpty,
                                  )
                                  .map(
                                    (e) => ListTile(
                                      title: AppText(e.value),
                                      subtitle: SelectableText(
                                        '${record[e.key]}',
                                      ),
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
