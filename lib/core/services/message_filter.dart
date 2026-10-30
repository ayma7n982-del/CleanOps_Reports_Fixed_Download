import 'messaging_service.dart';

/// Pure message-center filtering, independent of widgets and Firebase calls.
class MessageFilter {
  static const folders = ['all', 'inbox', 'sent', 'unread', 'pending', 'failed', 'urgent'];

  static String normalized(String value) {
    return value.toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
        .replaceAll(RegExp('[أإآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool matches(
    MessageItem message, {
    required String currentUserId,
    String folder = 'all',
    String search = '',
    String type = 'all',
    String target = 'all',
    String period = 'all',
    DateTime? now,
  }) {
    final mine = message.senderId == currentUserId;
    switch (folder) {
      case 'inbox':
        if (mine) return false;
      case 'sent':
        if (!mine) return false;
      case 'unread':
        if (mine || message.isRead) return false;
      case 'pending':
        if (!mine || message.deliveryStatus != 'pending') return false;
      case 'failed':
        if (!mine || message.deliveryStatus != 'failed') return false;
      case 'urgent':
        if (message.type != 'emergency') return false;
    }
    if (type != 'all' && message.type != type) return false;
    final destination = message.targetGroupId ??
        (message.targetUserId == null ? '' : '__USER__:${message.targetUserId}');
    if (target != 'all' && destination != target) return false;
    final cutoff = now ?? DateTime.now();
    switch (period) {
      case 'week':
        if (message.timestamp.isBefore(cutoff.subtract(const Duration(days: 7)))) return false;
      case 'month':
        if (message.timestamp.isBefore(cutoff.subtract(const Duration(days: 30)))) return false;
    }
    final q = normalized(search);
    if (q.isEmpty) return true;
    return normalized([
      message.content,
      message.senderName,
      message.senderId,
      message.targetUserId ?? '',
      message.targetGroupId ?? '',
      message.type,
    ].join(' ')).contains(q);
  }
}
