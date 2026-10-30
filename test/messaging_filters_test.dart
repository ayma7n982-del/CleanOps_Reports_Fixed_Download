import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/messaging_filters.dart';
import 'package:solid_waste_operations/core/services/messaging_service.dart';

void main() {
  final now = DateTime(2026, 10, 30, 10, 0);
  MessageItem message(
    String id, String sender, String content, String type,
    String status, DateTime date, {
    String? group, bool read = false,
  }) => MessageItem(
        messageId: id,
        senderId: sender,
        targetGroupId: group,
        content: content,
        timestamp: date,
        type: type,
        isRead: read,
        deliveryStatus: status,
        senderName: sender == 'me' ? 'المنسق' : 'محمود',
      );

  final items = <MessageItem>[
    message('a', 'me', 'إرسال تنبيه للمجموعة', 'warning', 'pending',
      DateTime(2026, 10, 30, 9), group: 'group-a'),
    message('b', 'head', 'طوارئ بسبب امتلاء الحاوية', 'emergency', 'sent',
      DateTime(2026, 10, 28), group: 'group-a'),
    message('c', 'me', 'تقرير يومي', 'info', 'failed',
      DateTime(2026, 9, 20), group: 'group-b'),
    message('d', 'head', 'تمت معالجة المكب', 'info', 'sent',
      DateTime(2026, 10, 30, 9, 30), group: 'group-b', read: true),
  ];

  test('search normalizes Arabic alef, ya and diacritics', () {
    final filtered = MessagingFilters.apply(items, userId:'me',
      search: 'إِمْتِلَاء', now: now);
    expect(filtered.map((m) => m.messageId), ['b']);
  });

  test('pending and failed show own messages only', () {
    expect(MessagingFilters.apply(items, userId:'me', tab:'pending', now:now)
        .map((m) => m.messageId), ['a']);
    expect(MessagingFilters.apply(items, userId:'me', tab:'failed', now:now)
        .map((m) => m.messageId), ['c']);
  });

  test('urgent, group and weekly filters combine', () {
    final found = MessagingFilters.apply(items, userId:'me',
      tab:'urgent', destination:'group-a', dateRange:'week', now:now);
    expect(found.map((m) => m.messageId), ['b']);
  });

  test('unread filters out own messages and read receipts', () {
    expect(MessagingFilters.apply(items, userId:'me', tab:'unread', now:now)
        .map((m) => m.messageId), ['b']);
  });

  test('newest first and no false empty matches', () {
    expect(MessagingFilters.apply(items, userId:'me', now:now)
        .map((m) => m.messageId), ['d', 'a', 'b', 'c']);
    expect(MessagingFilters.apply(items, userId:'me',
      search:'does-not-exist', now:now), isEmpty);
  });
}
