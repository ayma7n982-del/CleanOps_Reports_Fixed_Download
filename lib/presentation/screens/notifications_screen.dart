import '../../core/localization.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/notification_target_policy.dart';
import '../notification_navigation.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/data_service.dart';
import '../widgets/app_navigation_bar.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataService>();
    final user = context.watch<AuthService>().currentUser;
    final notices = data.notifications
        .where(
          (n) => user != null && NotificationTargetPolicy.addressedTo(user, n),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const AppText('الإشعارات'),
        bottom: const AppNavigationBar(),
      ),
      body: notices.isEmpty
          ? const Center(child: AppText('لا توجد إشعارات جديدة'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: notices.length,
              itemBuilder: (context, index) {
                final notification = notices[index];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      notification.read
                          ? Icons.notifications_none_rounded
                          : Icons.notifications_active_rounded,
                    ),
                    title: AppText(notification.title),
                    subtitle: AppText(notification.body),
                    trailing: notification.read
                        ? null
                        : const Icon(Icons.circle, size: 9),
                    onTap: () => openAppNotification(context, notification),
                  ),
                );
              },
            ),
    );
  }
}
