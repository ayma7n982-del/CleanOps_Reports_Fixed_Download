import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/message_filter.dart';
import 'package:solid_waste_operations/core/services/messaging_service.dart';

MessageItem item({
  String id = 'msg',
  String sender = 'head',
  String? target = 'group-a',
  String text = 'إصلاح الحاوية تم',
  String name = 'مشرف المجموعة',
  String type = 'info',
  bool read = false,
  String delivery = 'sent',
  DateTime? created,
}) => MessageItem(
  messageId: id,
  senderId: sender,
  targetGroupId: target,
  senderName: name,
  content: text,
  type: type,
  isRead: read,
  timestamp: created ?? DateTime(2026, 10, 30, 10),
  deliveryStatus: delivery,
);

void main() {
  final now = DateTime(2026, 10, 30, 12);

  test('Arabic equivalents and first letters match even without diacritics', () {
    final message = item(text: 'إصلاح الحَاوِيَة', name: 'مشرف المجموعة');
    expect(MessageFilter.matches(message,
      currentUserId: 'worker', search: 'اصلاح الحاويه', now: now), isTrue);
    expect(MessageFilter.matches(message,
      currentUserId: 'worker', search: 'اص', now: now), isTrue);
    expect(MessageFilter.matches(message,
      currentUserId: 'worker', search: 'غير موجود', now: now), isFalse);
  });

  test('Inbox, sent, unread, pending and failed remain distinct', () {
    final message = item(sender: 'head', delivery: 'failed');
    expect(MessageFilter.matches(message,
      currentUserId: 'head', folder: 'failed', now: now), isTrue);
    expect(MessageFilter.matches(message,
      currentUserId: 'head', folder: 'pending', now: now), isFalse);
    expect(MessageFilter.matches(message,
      currentUserId: 'worker', folder: 'inbox', now: now), isTrue);
    expect(MessageFilter.matches(message,
      currentUserId: 'head', folder: 'inbox', now: now), isFalse);
    expect(MessageFilter.matches(message,
      currentUserId: 'worker', folder: 'unread', now: now), isTrue);
    expect(MessageFilter.matches(message,
      currentUserId: 'head', folder: 'sent', now: now), isTrue);
  });

  test('Target, type and period filters combine without leaking other messages', () {
    final message = item(target: 'group-b', type: 'emergency',
      created: DateTime(2026, 10, 28));
    expect(MessageFilter.matches(message,
      currentUserId: 'worker', type: 'emergency',
      target: 'group-b', period: 'week', now: now), isTrue);
    expect(MessageFilter.matches(message,
      currentUserId: 'worker', target: 'group-a', now: now), isFalse);
    expect(MessageFilter.matches(message,
      currentUserId: 'worker', type: 'warning', now: now), isFalse);
    expect(MessageFilter.matches(item(created: DateTime(2026, 9, 1)),
      currentUserId: 'worker', period: 'month', now: now), isFalse);
  });

  test('Multiword search matches Arabic words in different order', () {
    final message = item(text: 'تم إصلاح الحاوية في المجموعة');
    expect(MessageFilter.matches(message,
      currentUserId: 'worker', search: 'المجموعة إصلاح', now: now), isTrue);
    expect(MessageFilter.matches(message,
      currentUserId: 'worker', search: 'كلمة مفقودة', now: now), isFalse);
  });

  test('Today period excludes older days', () {
    expect(MessageFilter.matches(item(created: DateTime(2026, 10, 30, 8)),
      currentUserId: 'worker', period: 'today', now: now), isTrue);
    expect(MessageFilter.matches(item(created: DateTime(2026, 10, 29, 23, 59)),
      currentUserId: 'worker', period: 'today', now: now), isFalse);
  });

  test('Direct messages have one understandable destination filter', () {
    final direct = item(target:'__USER__:worker-a');
    expect(MessageFilter.matches(direct,
      currentUserId:'head', target:'__DIRECT__', now:now), isTrue);
    expect(MessageFilter.matches(item(target:'group-a'),
      currentUserId:'head', target:'__DIRECT__', now:now), isFalse);
  });

  test('Only emergency cards enter the urgent folder', () {
    expect(MessageFilter.matches(item(type: 'emergency'),
      currentUserId: 'worker', folder: 'urgent', now: now), isTrue);
    expect(MessageFilter.matches(item(type: 'info'),
      currentUserId: 'worker', folder: 'urgent', now: now), isFalse);
  });
}
