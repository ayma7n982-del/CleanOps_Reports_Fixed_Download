import 'messaging_service.dart';

/// Stable, testable filtering shared by all message-center views.
class MessagingFilters {
  const MessagingFilters._();

  static String normalize(String value) {
    return value.toLowerCase()
        .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u0640]'), '')
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .trim();
  }

  static List<MessageItem> apply(
    Iterable<MessageItem> source, {
    required String userId,
    String tab = 'all',
    String search = '',
    String type = 'all',
    String destination = 'all',
    String dateRange = 'all',
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final needle = normalize(search);
    final tokens = needle.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final filtered = source.where((message) {
      final mine = message.senderId == userId;
      switch (tab) {
        case 'inbox':
          if (mine) return false;
          break;
        case 'sent':
          if (!mine) return false;
          break;
        case 'unread':
          if (mine || message.isRead) return false;
          break;
        case 'pending':
          if (!mine || message.deliveryStatus != 'pending') return false;
          break;
        case 'failed':
          if (!mine || message.deliveryStatus != 'failed') return false;
          break;
        case 'urgent':
          if (message.type != 'emergency') return false;
          break;
      }
      if (type != 'all' && message.type != type) return false;
      if (destination != 'all' &&
          message.targetGroupId != destination &&
          message.targetUserId != destination) return false;
      if (dateRange == 'today') {
        if (message.timestamp.year != current.year ||
            message.timestamp.month != current.month ||
            message.timestamp.day != current.day) return false;
      } else if (dateRange == 'week' &&
          message.timestamp.isBefore(current.subtract(const Duration(days: 7)))) {
        return false;
      } else if (dateRange == 'month' &&
          message.timestamp.isBefore(current.subtract(const Duration(days: 30)))) {
        return false;
      }
      if (tokens.isNotEmpty) {
        final haystack = normalize([
          message.content,
          message.senderName,
          message.senderRole,
          message.senderId,
          message.targetGroupId ?? '',
          message.targetUserId ?? '',
          message.type == 'emergency' ? 'طوارئ عاجل sos' : '',
          message.type == 'warning' ? 'تحذير تنبيه' : '',
          message.type == 'info' ? 'معلومة' : '',
        ].join(' '));
        if (!tokens.every(haystack.contains)) return false;
      }
      return true;
    }).toList();
    filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return filtered;
  }
}
