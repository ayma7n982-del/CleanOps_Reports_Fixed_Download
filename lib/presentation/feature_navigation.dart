import 'widgets/operations_overview.dart';
import '../core/models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/services/auth_service.dart';
import '../core/services/feature_route_policy.dart';
import 'screens/attendance_reports_home_screen.dart';
import 'screens/container_management.dart';
import 'screens/enterprise_operations_hub.dart';
import 'screens/level1_supervisor.dart';
import 'screens/messages_center.dart';
import 'screens/operations_management.dart';
import 'screens/reports_center.dart';
import 'screens/scoped_operation_records.dart';

void openAppFeature(BuildContext context, String feature) {
  final user = context.read<AuthService>().currentUser;
  if (user == null) return;
  final page = appFeaturePage(user, feature);
  if (page == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('هذه المهمة غير متاحة ضمن صلاحيات حسابك.')));
    return;
  }
  Navigator.push(context, MaterialPageRoute(builder: (_) => page));
}

Widget? appFeaturePage(AppUser user, String feature) {
  final target = FeatureRoutePolicy.resolve(user, feature);
  return switch (target) {
    FeatureDestination.attendanceEntry => const Level1SupervisorScreen(initialAction: 'attendance'),
    FeatureDestination.leaveEntry => const Level1SupervisorScreen(initialAction: 'leave'),
    FeatureDestination.attendanceReport => const AttendanceReportsHomeScreen(),
    FeatureDestination.leaveReport => const AttendanceReportsHomeScreen(leavesOnly: true),
    FeatureDestination.tripEntry => const Level1SupervisorScreen(initialAction: 'trips'),
    FeatureDestination.tripRecords => const ScopedOperationRecordsScreen(feature: 'trips', entity: 'trip', title: 'سجل النقلات'),
    FeatureDestination.streetEntry => const Level1SupervisorScreen(initialAction: 'streets'),
    FeatureDestination.streetRecords => const ScopedOperationRecordsScreen(feature: 'streets', entity: 'street_photo', title: 'سجل توثيق الشوارع'),
    FeatureDestination.emergencyEntry => const Level1SupervisorScreen(initialAction: 'emergency'),
    FeatureDestination.emergencyRecords => user.role == 'worker' || user.role == 'group_supervisor'
        ? const ScopedOperationRecordsScreen(feature: 'emergency', entity: 'emergency', title: 'البلاغات والطوارئ')
        : const AlertsCenterPage(),
    FeatureDestination.containers => const ContainerManagementScreen(),
    FeatureDestination.groups => const GroupsCommandCenterPage(),
    FeatureDestination.reports => const ReportsCenterScreen(),
    FeatureDestination.dumpsites => user.role == 'donor_manager'
        ? const DumpsitesOverviewScreen()
        : OperationsManagementScreen(initialTab: user.role == 'municipality_coordinator' ? 1 : 0),
    FeatureDestination.cycles => const OperationsManagementScreen(initialTab: 0),
    FeatureDestination.messages => const MessagesCenterScreen(),
    null => null,
  };
}
