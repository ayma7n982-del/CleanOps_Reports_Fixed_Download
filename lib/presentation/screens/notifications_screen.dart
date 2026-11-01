import '../../core/localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/data_service.dart';
import '../widgets/app_navigation_bar.dart';
import '../widgets/app_design.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataService>();
    return Scaffold(
      appBar: AppBar(
        title: const AppText('الإشعارات'),
        bottom: const AppNavigationBar(),
      ),
      body: data.notifications.isEmpty
          ? const Center(child: AppText('لا توجد إشعارات جديدة'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: data.notifications.length,
              itemBuilder: (context, index) {
                final notification = data.notifications[index];
                return Card(
                  child: ListTile(
                    leading: Icon(notification.read
                        ? Icons.notifications_none_rounded
                        : Icons.notifications_active_rounded),
                    title: AppText(notification.title),
                    subtitle: AppText(notification.body),
                    trailing: notification.read
                        ? null
                        : const Icon(Icons.circle, size: 9),
                    onTap: () => data.markRead(notification.id),
                  ),
                );
              },
            ),
    );
  }
}
