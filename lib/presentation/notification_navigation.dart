import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/core_models.dart';
import '../core/services/auth_service.dart';
import '../core/services/notification_target_policy.dart';
import 'screens/notification_record_screen.dart';

void openAppNotification(BuildContext context, NotificationItem notice) {
  final user = context.read<AuthService>().currentUser;
  if (user == null || !NotificationTargetPolicy.addressedTo(user, notice)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('هذا الإشعار غير متاح ضمن صلاحيات حسابك.')),
    );
    return;
  }
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => NotificationRecordScreen(notice: notice, userId: user.id),
    ),
  );
}
