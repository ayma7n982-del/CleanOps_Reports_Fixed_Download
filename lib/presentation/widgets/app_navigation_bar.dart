import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/localization.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/data_service.dart';
import '../../core/services/messaging_service.dart';
import '../screens/global_search.dart';
import '../screens/messages_center.dart';
import '../screens/notifications_screen.dart';

/// The same four destinations on every operational page. This is navigation
/// only: each destination retains its existing server-enforced permissions.
class AppNavigationBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onHome;
  const AppNavigationBar({super.key, this.onHome});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  static void goHome(BuildContext context) {
    // Replace the whole route stack, including unnamed legacy workspace routes.
    // The home named route always opens the actual AppShell, never another hub.
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
  }

  static void _open(BuildContext context, String routeName, Widget page) {
    if (ModalRoute.of(context)?.settings.name == routeName) return;
    Navigator.push(context, MaterialPageRoute(
      settings: RouteSettings(name: routeName), builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService?>()?.currentUser;
    final data = context.watch<DataService?>();
    final unreadMessages = context.watch<MessagingService?>()?.unreadCount ?? 0;
    final unreadNotifications = data?.notifications.where((n) => !n.read).length ?? 0;
    final arabic = context.watch<LocaleController?>()?.isArabic ?? true;

    Widget destination(String label, IconData icon, VoidCallback? tap,
        {int unread = 0}) => Expanded(
      child: TextButton(
        onPressed: tap,
        style: TextButton.styleFrom(
          foregroundColor: aiNavigationColor,
          minimumSize: const Size(48, 60),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: Icon(icon, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11)),
        ]),
      ),
    );

    return Directionality(
      textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Material(
        color: cleanOpsSurface,
        child: Row(children: [
          destination(arabic ? 'الرئيسية' : 'Home', Icons.home_outlined,
              onHome ?? () => goHome(context)),
          destination(arabic ? 'البحث' : 'Search', Icons.search_rounded,
              user != null && (user.can('operations', 'view') || user.can('reports', 'view'))
                  ? () => _open(context, '/search', const GlobalSearchPage()) : null),
          destination(arabic ? 'الرسائل' : 'Messages', Icons.forum_outlined,
              user?.can('messages', 'view') == true
                  ? () => _open(context, '/messages', const MessagesCenterScreen()) : null,
              unread: unreadMessages),
          destination(arabic ? 'الإشعارات' : 'Notifications', Icons.notifications_none_rounded,
              user?.can('notifications', 'view') == true
                  ? () => _open(context, '/notifications', const NotificationsPage()) : null,
              unread: unreadNotifications),
        ]),
      ),
    );
  }

  static const aiNavigationColor = Color(0xFF087F6B);
}
