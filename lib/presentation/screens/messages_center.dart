import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_constants.dart';
import '../../core/localization.dart';
import '../../core/models/core_models.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/data_service.dart';
import '../../core/services/messaging_service.dart';
import '../widgets/app_design.dart';

class MessagesCenterScreen extends StatefulWidget {
  const MessagesCenterScreen({super.key});

  @override
  State<MessagesCenterScreen> createState() => _MessagesCenterScreenState();
}

class _MessagesCenterScreenState extends State<MessagesCenterScreen> {
  final composer = TextEditingController();
  String type = 'info';
  String? selectedGroup;
  bool sending = false;
  bool supervisorBroadcast = false;
  String recipientMode = 'broadcast';
  String? selectedRecipient;
  DateTime? scheduledAt;
  String messageFilter = 'all';
  String searchText = '';
  final searchController = TextEditingController();

  @override
  void dispose() {
    composer.dispose();
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messaging = context.watch<MessagingService>();
    final user = context.watch<AuthService>().currentUser;
    if (user == null) return const SizedBox.shrink();
    final visibleMessages = messaging.messages.where((message) {
      if (messageFilter == 'inbox' && message.senderId == user.id) return false;
      if (messageFilter == 'sent' && message.senderId != user.id) return false;
      if (messageFilter == 'unread' && (message.isRead || message.senderId == user.id)) return false;
      final term = searchText.trim().toLowerCase();
      return term.isEmpty || message.content.toLowerCase().contains(term) ||
          message.senderName.toLowerCase().contains(term) ||
          message.senderId.toLowerCase().contains(term) ||
          (message.targetGroupId ?? '').toLowerCase().contains(term);
    }).toList();
    return Directionality(
      textDirection: context.watch<LocaleController>().isArabic ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: const AppText('مركز الرسائل'),
          actions: [
            if (messaging.canSend('info')) IconButton(
              tooltip: 'الرسائل المجدولة',
              icon: const Icon(Icons.event_note_outlined),
              onPressed: () => _showScheduledMessages(user, messaging),
            ),
            if (const ['municipality_coordinator','jsc_coordinator','donor_manager'].contains(user.role))
              IconButton(
                tooltip: 'الرسائل الخارجية SMS',
                icon: const Icon(Icons.sms_outlined),
                onPressed: () => _openExternalSms(user, messaging),
              ),
            if (messaging.syncing) const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            Badge(
              isLabelVisible: messaging.unreadCount > 0,
              label: Text('${messaging.unreadCount}'),
              child: const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.mark_email_unread_outlined)),
            ),
          ],
        ),
        body: RefreshIndicator(
                onRefresh: messaging.retryPendingWrites,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
                  children: [
                    _statusBanner(messaging),
                    const SizedBox(height: 12),
                    AiHero(
                      user: user,
                      eyebrow: 'SECURE • FIRESTORE MESSAGING',
                      title: 'تواصل تشغيلي مباشر',
                      subtitle: 'رسائل داخلية لحظية تعمل مع التخزين المحلي ولا تعتمد على FCM.',
                      trailing: IconButton(onPressed: messaging.retryPendingWrites, icon: const Icon(Icons.sync_rounded, color: Colors.white)),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: searchController,
                      onChanged: (value) => setState(() => searchText = value),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: 'ابحث في الرسائل أو المرسل أو المجموعة',
                        suffixIcon: searchText.isEmpty ? null : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () { searchController.clear(); setState(() => searchText = ''); },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final filter in const [
                          ('all', 'الكل'), ('inbox', 'الوارد'),
                          ('sent', 'المرسل'), ('unread', 'غير المقروء'),
                        ]) Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ChoiceChip(
                            label: Text(filter.$2),
                            selected: messageFilter == filter.$1,
                            onSelected: (_) => setState(() => messageFilter = filter.$1),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    if (visibleMessages.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: AppText('لا توجد رسائل مطابقة للعرض الحالي.')),
                      ),
                    ...visibleMessages.map((message) => _messageCard(message, user.id, messaging)),
                  ],
                ),
              ),
        floatingActionButton: messaging.canSend(type) ? FloatingActionButton.extended(
          onPressed: sending ? null : () => _openComposer(user, messaging),
          icon: const Icon(Icons.edit_rounded),
          label: const AppText('رسالة جديدة'),
        ) : null,
      ),
    );
  }

  Widget _emptyState(AppUser user, MessagingService messaging) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: [
          _statusBanner(messaging),
          const SizedBox(height: 28),
          const Icon(Icons.mark_email_unread_outlined, size: 78, color: aiCyan),
          const SizedBox(height: 16),
          const AppText('لا توجد رسائل بعد', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const AppText('ستظهر الرسائل الموجهة إليك أو إلى مجموعتك هنا تلقائيًا.', textAlign: TextAlign.center, style: TextStyle(color: cleanOpsMuted)),
          const SizedBox(height: 18),
          if (messaging.canSend(type))
            FilledButton.icon(onPressed: sending ? null : () => _openComposer(user, messaging), icon: const Icon(Icons.send_rounded), label: const AppText('إرسال رسالة')),
        ],
      );

  Widget _statusBanner(MessagingService service) {
    final error = service.lastError;
    return Card(
      color: error == null ? aiDark2.withOpacity(.75) : red.withOpacity(.10),
      child: ListTile(
        dense: true,
        leading: Icon(error == null ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, color: error == null ? aiGreen : red),
        title: AppText(error == null ? 'المراسلة الداخلية • مزامنة Firestore' : 'تعذر إكمال عملية مراسلة. راجع التفاصيل أدناه.'),
        subtitle: error == null ? const AppText('لا توجد خدمة FCM مطلوبة للتراسل الداخلي.') : AppText(error),
      ),
    );
  }

  Widget _messageCard(MessageItem message, String uid, MessagingService messaging) {
    final isMine = message.senderId == uid;
    final style = switch (message.type) {
      'emergency' => (red, Icons.warning_amber_rounded, 'طوارئ / SOS'),
      'warning' => (orange, Icons.priority_high_rounded, 'تحذير'),
      _ => (aiCyan, Icons.info_outline_rounded, 'معلومة'),
    };
    final unread = !message.isRead && !isMine;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AiGlassCard(
        color: unread ? style.$1.withOpacity(.08) : null,
        onTap: () {
          if (unread) messaging.markRead(message.messageId);
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: cleanOpsSurface,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            builder: (sheetContext) => SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * .8),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const AppText('تفاصيل الرسالة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 12),
                    AppText(message.content, style: const TextStyle(fontSize: 16, height: 1.5)),
                    const SizedBox(height: 16),
                    AppText('المرسل: ${message.senderName.isEmpty ? message.senderId : message.senderName}'),
                    AppText('الوجهة: ${message.targetGroupId ?? message.targetUserId ?? "غير محددة"}'),
                    AppText('الوقت: ${DateFormat('yyyy/MM/dd • HH:mm').format(message.timestamp)}'),
                    const SizedBox(height: 12),
                    if (isMine && message.deliveryStatus == 'sent' && Firebase.apps.isNotEmpty)
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance.collection('messages')
                            .doc(message.messageId).collection('receipts').snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return const AppText('إيصالات الاستلام غير متاحة؛ تحقق من نشر قواعد Firebase.',
                                style: TextStyle(color: cleanOpsMuted, fontSize: 12));
                          }
                          if (!snapshot.hasData) {
                            return const LinearProgressIndicator();
                          }
                          final receipts = snapshot.data!.docs;
                          final acknowledged = receipts.where((d) => d.data()['status'] == 'acknowledged').length;
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            AppText('إيصالات القراءة: ${receipts.length} • تأكيدات الاستلام: $acknowledged',
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                            for (final receipt in receipts)
                              AppText('${receipt.id}: ${receipt.data()['status'] == 'acknowledged' ? 'تم التأكيد' : 'تمت القراءة'}${receipt.metadata.hasPendingWrites ? ' • قيد المزامنة' : ''}',
                                  style: const TextStyle(fontSize: 12, color: cleanOpsMuted)),
                          ]);
                        },
                      ),
                    if (Firebase.apps.isNotEmpty && message.deliveryStatus == 'sent')
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance.collection('messages')
                            .doc(message.messageId).collection('attachments').snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return const AppText('المرفقات غير متاحة حتى نشر قواعد التخزين.',
                              style: TextStyle(color: cleanOpsMuted, fontSize: 12));
                          }
                          if (!snapshot.hasData) return const SizedBox.shrink();
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (snapshot.data!.docs.isNotEmpty)
                              const AppText('صور الرسالة', style: TextStyle(fontWeight: FontWeight.w800)),
                            for (final file in snapshot.data!.docs)
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.image_outlined, color: aiCyan),
                                title: const AppText('عرض الصورة المرفقة'),
                                subtitle: AppText('${file.data()['sizeBytes'] ?? 0} بايت'),
                                onTap: () => _showAttachmentImage(
                                  sheetContext, '${file.data()['path'] ?? ''}'),
                              ),
                          ]);
                        },
                      ),
                    if (isMine && message.deliveryStatus == 'sent') ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const AppText('إرفاق صور (حتى 5 صور، 500 كيلوبايت لكل صورة)'),
                        onPressed: () => _pickMessageImages(message, messaging),
                      ),
                    ],
                    if (!isMine) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () async {
                          await messaging.acknowledgeMessage(message.messageId);
                          if (sheetContext.mounted) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(content: AppText('تم تسجيل طلب تأكيد الاستلام للمزامنة.')));
                          }
                        },
                        icon: const Icon(Icons.task_alt_rounded),
                        label: const AppText('تأكيد استلام الرسالة'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const AppText('إغلاق'),
                    )),
                  ]),
                ),
              ),
            ),
          );
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: style.$1.withOpacity(.12), borderRadius: BorderRadius.circular(15), border: Border.all(color: style.$1.withOpacity(.35))),
              child: Icon(style.$2, color: style.$1),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: AppText(style.$3, style: TextStyle(color: style.$1, fontWeight: FontWeight.w900))),
                    if (unread) Container(width: 8, height: 8, decoration: const BoxDecoration(color: aiGreen, shape: BoxShape.circle)),
                  ]),
                  const SizedBox(height: 5),
                  AppText(message.content, style: const TextStyle(fontSize: 15, height: 1.45)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 5, children: [
                    if (isMine) Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(
                        message.deliveryStatus == 'sent' ? Icons.cloud_done_rounded
                            : message.deliveryStatus == 'failed' ? Icons.error_outline_rounded
                            : Icons.cloud_upload_outlined,
                        size: 17,
                        color: message.deliveryStatus == 'failed' ? red : aiCyan,
                      ),
                      label: AppText(message.deliveryStatus == 'sent' ? 'وصل للخادم'
                          : message.deliveryStatus == 'failed' ? 'فشل الإرسال' : 'بانتظار المزامنة',
                          style: const TextStyle(fontSize: 11)),
                    ),
                    if (isMine && message.deliveryStatus == 'failed') TextButton.icon(
                      icon: const Icon(Icons.refresh_rounded, size: 17),
                      label: const AppText('إعادة المحاولة'),
                      onPressed: () async {
                        try {
                          await messaging.retryFailedMessage(message.messageId);
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: AppText('$e')));
                        }
                      },
                    ),
                    AppText(isMine ? 'أنت' : (message.senderName.isEmpty ? message.senderId : message.senderName), style: const TextStyle(color: cleanOpsMuted, fontSize: 11, fontWeight: FontWeight.w700)),
                    AppText(DateFormat('yyyy/MM/dd • HH:mm').format(message.timestamp), style: const TextStyle(color: cleanOpsMuted, fontSize: 10)),
                    if (message.targetGroupId != null && message.targetGroupId!.startsWith('__USER__:')) const AppText('رسالة مباشرة', style: TextStyle(color: aiCyan, fontSize: 10)),
                    if (message.targetGroupId != null && !message.targetGroupId!.startsWith('__USER__:')) AppText(message.targetGroupId == MessagingService.allMunicipalitiesGroup ? 'بث للبلديات' : 'مجموعة ${message.targetGroupId}', style: const TextStyle(color: aiCyan, fontSize: 10)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openComposer(AppUser user, MessagingService messaging) async {
    composer.clear();
    type = user.role == 'group_supervisor' ? 'emergency' : 'info';
    selectedGroup = null;
    supervisorBroadcast = false;
    recipientMode = 'broadcast';
    selectedRecipient = null;
    scheduledAt = null;
    final data = context.read<DataService>();
    try { await data.refreshOperations(); } catch (_) {}
    if (!mounted) return;
    final directRecipients = await _loadDirectRecipients(user);
    if (!mounted) return;
    if (directRecipients.isNotEmpty) selectedRecipient = directRecipients.first.$1;
    final groups = <String>{};
    for (final item in data.operations) {
      if ('${item['_entity'] ?? ''}' == 'group' && item['isDeleted'] != true &&
          (user.role != 'municipality_coordinator' ||
           item['municipalityCoordinatorId'] == user.id)) {
        final id = '${item['id'] ?? item['number'] ?? ''}'.trim();
        if (id.isNotEmpty) groups.add(id);
      }
      final gid = '${item['groupId'] ?? ''}'.trim();
      if (gid.isNotEmpty &&
          (user.role != 'municipality_coordinator' ||
           item['municipalityCoordinatorId'] == user.id) &&
          ('${item['_entity'] ?? ''}' == 'worker' ||
           '${item['_entity'] ?? ''}' == 'group_supervisor')) groups.add(gid);
    }
    if ((user.groupId ?? '').isNotEmpty) groups.add(user.groupId!);
    if (groups.isNotEmpty) selectedGroup = groups.first;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cleanOpsSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => StatefulBuilder(builder: (context, setSheetState) {
        final isL1 = user.role == 'group_supervisor';
        final isManagement = user.role == 'municipality_coordinator' || user.role == 'jsc_coordinator' || user.role == 'donor_manager';
        final canChooseGroup = user.role == 'municipality_coordinator' && recipientMode == 'broadcast';
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 16, 18, MediaQuery.of(context).viewInsets.bottom + 18),
          child: ListView(
            shrinkWrap: true,
            children: [
              Row(children: [const Icon(Icons.forum_rounded, color: aiCyan), const SizedBox(width: 10), const Expanded(child: AppText('إرسال رسالة داخلية', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))]),
              const SizedBox(height: 14),
              if (isManagement && directRecipients.isNotEmpty) ...[
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ChoiceChip(
                    label: const AppText('بث جماعي'),
                    selected: recipientMode == 'broadcast',
                    onSelected: (_) => setSheetState(() => recipientMode = 'broadcast'),
                  ),
                  ChoiceChip(
                    label: const AppText('رسالة مباشرة'),
                    selected: recipientMode == 'direct',
                    onSelected: (_) => setSheetState(() => recipientMode = 'direct'),
                  ),
                ]),
                const SizedBox(height: 12),
                if (recipientMode == 'direct')
                  DropdownButtonFormField<String>(
                    value: directRecipients.any((entry) => entry.$1 == selectedRecipient)
                        ? selectedRecipient : directRecipients.first.$1,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'المستلم المسموح'),
                    items: directRecipients.map((entry) => DropdownMenuItem(
                      value: entry.$1,
                      child: Text(entry.$2, overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (value) => setSheetState(() => selectedRecipient = value),
                  ),
              ],
              DropdownButtonFormField<String>(
                value: type,
                decoration: InputDecoration(labelText: tr('نوع الرسالة')),
                items: [
                  if (!isL1) const DropdownMenuItem(value: 'info', child: AppText('معلومة')),
                  if (isL1) const DropdownMenuItem(value: 'info', child: AppText('تقرير ميداني')),
                  if (!isL1) const DropdownMenuItem(value: 'warning', child: AppText('تحذير')),
                  const DropdownMenuItem(value: 'emergency', child: AppText('طوارئ / SOS')),
                ],
                onChanged: (value) { if (value != null) setSheetState(() => type = value); },
              ),
              const SizedBox(height: 10),
              if (isManagement) Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppText(recipientMode == 'direct' ? 'ستصل إلى الشخص المختار فقط، وفق صلاحيات حسابك.' : type == 'emergency' ? 'سيتم توجيه الرسالة وفق نطاق الدور والصلاحيات.' : user.role == 'municipality_coordinator' ? 'ستصل الرسالة إلى المجموعة المختارة.' : 'ستصل الرسالة إلى جميع منسقي البلديات.'),
              ),
              if (canChooseGroup && groups.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 12),
                  child: AppText('لا توجد مجموعات تابعة لبلديتك. لا يمكن إرسال رسالة جماعية.')),
              if (canChooseGroup && groups.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: groups.contains(selectedGroup) ? selectedGroup : groups.first,
                  decoration: InputDecoration(labelText: tr('المجموعة المستهدفة')),
                  items: groups.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                  onChanged: (value) => setSheetState(() => selectedGroup = value),
                ),
              if (isL1) SwitchListTile(
                title: const AppText('إرسال لجميع أفراد مجموعتي'),
                subtitle: AppText(supervisorBroadcast ? 'سيتم الإرسال إلى المجموعة المرتبطة بحسابك فقط.' : 'سيتم الإرسال إلى منسق البلدية.'),
                value: supervisorBroadcast,
                onChanged: (value) => setSheetState(() => supervisorBroadcast = value),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 7, runSpacing: 7, children: [
                for (final template in const [
                  ('تعليمات', 'تعليمات تشغيلية: '),
                  ('متابعة', 'يرجى متابعة المهمة وإبلاغنا بالنتيجة: '),
                  ('طوارئ', 'تنبيه عاجل: يرجى اتخاذ الإجراء اللازم في الموقع: '),
                ])
                  ActionChip(
                    avatar: const Icon(Icons.description_outlined, size: 16),
                    label: Text(template.$1),
                    onPressed: () {
                      composer.text = template.$2;
                      composer.selection = TextSelection.collapsed(offset: composer.text.length);
                      setSheetState(() {});
                    },
                  ),
              ]),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule_rounded),
                label: AppText(scheduledAt == null
                    ? 'جدولة الإرسال في وقت لاحق'
                    : 'الإرسال المجدول: ${DateFormat('yyyy/MM/dd • HH:mm').format(scheduledAt!)}'),
                onPressed: () async {
                  final today = DateTime.now();
                  final date = await showDatePicker(
                    context: context, initialDate: today.add(const Duration(days: 1)),
                    firstDate: today, lastDate: today.add(const Duration(days: 30)));
                  if (date == null || !context.mounted) return;
                  final clock = await showTimePicker(
                    context: context, initialTime: TimeOfDay.now());
                  if (clock == null || !context.mounted) return;
                  setSheetState(() => scheduledAt = DateTime(
                    date.year, date.month, date.day, clock.hour, clock.minute));
                },
              ),
              if (scheduledAt != null) TextButton.icon(
                onPressed: () => setSheetState(() => scheduledAt = null),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const AppText('إلغاء الجدولة والإرسال الآن'),
              ),
              const SizedBox(height: 10),
              TextField(controller: composer, minLines: 4, maxLines: 8, textInputAction: TextInputAction.newline, decoration: InputDecoration(labelText: tr('محتوى الرسالة'), hintText: tr('اكتب الرسالة هنا...'))),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: type == 'emergency' ? red : null, minimumSize: const Size.fromHeight(54)),
                onPressed: sending || (recipientMode == 'direct' && selectedRecipient == null) || (canChooseGroup &&
                    (selectedGroup == null || !groups.contains(selectedGroup)))
                    ? null : () async {
                  setSheetState(() => sending = true);
                  try {
                    if (scheduledAt != null) {
                      String? targetUserId;
                      String? targetGroupId;
                      if (isL1 && !supervisorBroadcast) {
                        targetUserId = await _resolveCoordinator(user, data);
                        if (targetUserId == null || targetUserId.isEmpty) {
                          throw StateError('منسق البلدية غير محدد.');
                        }
                      } else if (isL1 && supervisorBroadcast) {
                        targetGroupId = user.groupId;
                      } else if (recipientMode == 'direct') {
                        targetUserId = selectedRecipient;
                      } else if (user.role == 'municipality_coordinator') {
                        targetGroupId = selectedGroup;
                      } else {
                        targetGroupId = MessagingService.allMunicipalitiesGroup;
                      }
                      final result = await messaging.scheduleInternalMessage(
                        content: composer.text, type: type, sendAt: scheduledAt!,
                        targetUserId: targetUserId, targetGroupId: targetGroupId);
                      if (result != 'scheduled') throw StateError('حالة الجدولة: $result');
                    } else if (isL1 && supervisorBroadcast) {
                      await messaging.sendBroadcast(content: composer.text, type: type, groupId: user.groupId);
                    } else if (isL1) {
                      final target = await _resolveCoordinator(user, data);
                      if (target == null || target.isEmpty) throw StateError('لم يتم العثور على منسق البلدية المرتبط بهذه المجموعة.');
                      await messaging.sendToUser(targetUserId: target, content: composer.text, type: type);
                    } else if (recipientMode == 'direct' && selectedRecipient != null) {
                      await messaging.sendToUser(targetUserId: selectedRecipient!, content: composer.text, type: type);
                    } else if (user.role == 'municipality_coordinator') {
                      await messaging.sendBroadcast(content: composer.text, type: type, groupId: selectedGroup);
                    } else {
                      await messaging.sendBroadcast(content: composer.text, type: type);
                    }
                    if (context.mounted) Navigator.pop(context);
                    if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(
                      content: AppText(scheduledAt == null ? 'أُضيفت الرسالة لقائمة الانتظار، وتنتظر تأكيد الخادم.' : 'تم تسجيل موعد الإرسال لدى خادم Firebase.')));
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: AppText('تعذر إرسال الرسالة: $e')));
                  } finally {
                    if (context.mounted) setSheetState(() => sending = false);
                  }
                },
                icon: const Icon(Icons.send_rounded),
                label: AppText(sending ? 'جارٍ الحفظ...' : 'إرسال'),
              ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _showScheduledMessages(AppUser user, MessagingService messaging) async {
    if (Firebase.apps.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: cleanOpsSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .65,
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.all(18),
              child: AppText('سجل الرسائل المجدولة',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('scheduled_messages')
                    .where('senderId', isEqualTo: user.id).limit(50).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return const Center(
                    child: AppText('سجل الجدولة غير متاح حتى نشر قواعد Firebase.'));
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  if (snapshot.data!.docs.isEmpty) return const Center(
                    child: AppText('لا توجد رسائل مجدولة.'));
                  return ListView(
                    children: [
                      for (final item in snapshot.data!.docs)
                        ListTile(
                          title: AppText('${item.data()['content'] ?? ''}', maxLines: 2),
                          subtitle: AppText('الحالة: ${item.data()['status'] ?? ''}'),
                          trailing: item.data()['status'] == 'scheduled'
                              ? IconButton(
                                  tooltip: 'إلغاء الجدولة',
                                  icon: const Icon(Icons.cancel_outlined),
                                  onPressed: () async {
                                    try {
                                      await messaging.cancelScheduledMessage(item.id);
                                    } catch (e) {
                                      if (sheetContext.mounted) ScaffoldMessenger.of(sheetContext)
                                          .showSnackBar(SnackBar(content: AppText('$e')));
                                    }
                                  },
                                )
                              : const Icon(Icons.history_rounded),
                        ),
                    ],
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickMessageImages(MessageItem message, MessagingService messaging) async {
    try {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 90, maxWidth: 1920);
      if (picked.isEmpty) return;
      if (picked.length > 5) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: AppText('يمكن إرفاق خمس صور في كل عملية.')));
        return;
      }
      final bytes = <Uint8List>[];
      for (final photo in picked) {
        bytes.add(await photo.readAsBytes());
      }
      await messaging.addMessageImages(message.messageId, bytes);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('تم حفظ الصور المرفقة على Firebase.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText('تعذر رفع الصور: $e')));
    }
  }

  void _showAttachmentImage(BuildContext parent, String path) {
    if (path.isEmpty) return;
    showDialog<void>(
      context: parent,
      builder: (dialogContext) => AlertDialog(
        title: const AppText('الصورة المرفقة'),
        content: FutureBuilder<Uint8List?>(
          future: FirebaseStorage.instance.ref().child(path).getData(500 * 1024),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const AppText('تعذر عرض الصورة أو لا توجد صلاحية.');
            }
            if (!snapshot.hasData) return const CircularProgressIndicator();
            return Image.memory(snapshot.data!, fit: BoxFit.contain);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: const AppText('إغلاق')),
        ],
      ),
    );
  }

  Future<void> _openExternalSms(AppUser user, MessagingService messaging) async {
    final recipients = await _loadDirectRecipients(user);
    if (!mounted) return;
    if (recipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: AppText('لا يوجد مستلمون مصرح بهم أو لم يمكن تحميلهم.')));
      return;
    }
    final body = TextEditingController();
    String? recipientId = recipients.first.$1;
    bool busy = false;
    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: cleanOpsSurface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (sheetContext) => StatefulBuilder(builder: (context, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 16, 18,
                  MediaQuery.viewInsetsOf(context).bottom + 18),
              child: ListView(
                shrinkWrap: true,
                children: [
                  const AppText('رسالة خارجية SMS',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  const AppText('يحدد الخادم رقم الهاتف من حساب المستلم ويُراجع صلاحياتك. قبول المزود لا يعني وصول الرسالة إلى الهاتف.',
                    style: TextStyle(color: cleanOpsMuted, fontSize: 12)),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: recipientId,
                    decoration: const InputDecoration(labelText: 'المستلم'),
                    items: recipients.map((entry) => DropdownMenuItem(
                      value: entry.$1,
                      child: Text(entry.$2, overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: busy ? null : (value) =>
                        setSheetState(() => recipientId = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: body,
                    maxLength: 500,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: 'نص SMS'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: busy || recipientId == null ? null : () async {
                      setSheetState(() => busy = true);
                      try {
                        final status = await messaging.sendExternalSms(
                          targetUserId: recipientId!, content: body.text);
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                        if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(content: AppText(
                            status == 'submitted'
                              ? 'قبل مزود SMS طلب الرسالة؛ التسليم النهائي غير مؤكد.'
                              : 'حالة طلب SMS: $status')));
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(content: AppText('تعذر إرسال SMS: $e')));
                      } finally {
                        if (sheetContext.mounted) setSheetState(() => busy = false);
                      }
                    },
                    icon: const Icon(Icons.send_rounded),
                    label: AppText(busy ? 'جارٍ الإرسال...' : 'إرسال SMS عبر الخادم'),
                  ),
                  const SizedBox(height: 18),
                  const AppText('آخر الطلبات الخارجية', style: TextStyle(fontWeight: FontWeight.w800)),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance.collection('external_messages')
                        .where('senderId', isEqualTo: user.id).limit(15).snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const AppText('السجل غير متاح قبل نشر قواعد الرسائل الخارجية.',
                          style: TextStyle(color: cleanOpsMuted, fontSize: 12));
                      }
                      if (!snapshot.hasData) return const LinearProgressIndicator();
                      final docs = snapshot.data!.docs;
                      if (docs.isEmpty) {
                        return const AppText('لا توجد طلبات SMS مسجلة.',
                          style: TextStyle(color: cleanOpsMuted, fontSize: 12));
                      }
                      return Column(children: [
                        for (final item in docs)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.sms_outlined, color: aiCyan),
                            title: AppText('${item.data()['content'] ?? ''}', maxLines: 2),
                            subtitle: AppText('المستلم: ${item.data()['targetUserId'] ?? ''}'),
                            trailing: AppText(
                              item.data()['status'] == 'submitted' ? 'قبله المزود'
                                : item.data()['status'] == 'failed' ? 'فشل'
                                : 'قيد المعالجة',
                              style: const TextStyle(fontSize: 11)),
                          ),
                      ]);
                    },
                  ),
                ],
              ),
            ),
          );
        }),
      );
    } finally {
      body.dispose();
    }
  }

  Future<List<(String, String)>> _loadDirectRecipients(AppUser user) async {
    if (Firebase.apps.isEmpty) return [];
    if (!const ['municipality_coordinator','jsc_coordinator','donor_manager'].contains(user.role)) return [];
    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('users');
      if (user.role == 'municipality_coordinator') {
        query = query.where('municipalityCoordinatorId', isEqualTo: user.id);
      }
      final docs = await query.limit(200).get();
      return docs.docs.where((doc) {
        final data = doc.data();
        if (doc.id == user.id || data['isActive'] == false) return false;
        final role = '${data['role'] ?? ''}';
        return user.role == 'municipality_coordinator'
            ? const ['worker', 'group_supervisor'].contains(role)
            : const ['municipality_coordinator', 'jsc_coordinator', 'donor_manager'].contains(role);
      }).map((doc) {
        final name = '${doc.data()['name'] ?? doc.id}';
        return (doc.id, '$name • ${doc.data()['role'] ?? ''}');
      }).toList();
    } catch (e) {
      debugPrint('Authorized direct recipients unavailable: $e');
      return [];
    }
  }

  Future<String?> _resolveCoordinator(AppUser user, DataService data) async {
    if ((user.municipalityCoordinatorId ?? '').isNotEmpty) return user.municipalityCoordinatorId;
    final groupId = user.groupId ?? '';
    for (final item in data.operations) {
      if ('${item['_entity'] ?? ''}' != 'group') continue;
      if ('${item['id'] ?? ''}' == groupId || '${item['number'] ?? ''}' == groupId || '${item['groupId'] ?? ''}' == groupId) {
        final id = '${item['municipalityCoordinatorId'] ?? ''}'.trim();
        if (id.isNotEmpty) return id;
      }
    }
    return null;
  }
}
