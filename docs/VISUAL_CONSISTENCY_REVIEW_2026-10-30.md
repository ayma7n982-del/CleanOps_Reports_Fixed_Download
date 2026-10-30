# CleanOps — Visual Consistency Review | 2026-10-30

Repository: CleanOps_Reports_Fixed_Download.  
Scope: 27 screens in lib/presentation/screens, app shell, native and Flutter startup.

## Accepted Eco visual design

Primary emerald #087F6B; ink #173B35; mint #E7F9F1; border #D5EBE1. For Arabic RTL, short two-column illustrated shortcuts put the pictorial icon to the right, readable title alongside it, and action indicator to the left. Every role-supplied shortcut keeps its original callback and visibility check.

Reusable implementation: EcoShortcutCard and EcoShortcutGrid in lib/presentation/widgets/eco_shortcuts.dart. Other existing adapters: CreativeShortcutGrid, AssistantShortcutGrid, AiGlassCard, AiSectionCard. Native Cards, AppBars, dialog, form, chip and button surfaces inherit the common Material theme in lib/main.dart.

## Full screen inventory

| Screen | Visual framework | Feature-specific behavior preserved |
| --- | --- | --- |
| action_decision_hub.dart | Emerald hero, themed cards | Decisions and PDF |
| ai_bot_screen.dart | Shared illustrated assistant shortcuts and hero | Analysis, records, RBAC |
| ai_command_center.dart | Eco shortcut grid, branded KPI cards | Live indicators and routes |
| attendance_reports_home_screen.dart | Common Card and form theme | Attendance and reports |
| container_management.dart | Common Ai cards, themed FAB | Container CRUD |
| cycle_manual_attendance_screen.dart | Global form theme | Manual attendance |
| enterprise_login.dart | Mint brand backdrop and logo card | Online/offline login, password reset |
| enterprise_operations_hub.dart | Common Ai cards | Operations and search |
| enterprise_settings_pages.dart | Common Ai cards | Settings |
| equipment_search.dart | Common Ai cards | Equipment |
| global_search.dart | Re-export of global search screen | Search navigation |
| level1_supervisor.dart | Shared workspace and SOS Eco card | Attendance, trips, SOS |
| level2_municipality.dart | Shared workplace shortcuts | Municipal scopes |
| level3_jsc.dart | Shared shortcuts and themed Card | Council scopes |
| level4_unicef.dart | Themed simulation banner | Simulation confirmation |
| live_operations_map.dart | Themed overlays | Map layers and gestures |
| messages_center.dart | Themed message UI | Recipient permissions and attachments |
| monthly_attendance_report_screen.dart | Themed form and cards | Monthly reports |
| operations_management.dart | Shared Ai cards and themed Card | Dumpsites, trips |
| report_approval_screen.dart | Themed Card | Approval workflow |
| report_branding_settings_screen.dart | Themed form | Identity settings |
| reports_center.dart | Eco illustrated report shortcuts | Reports and PDF exports |
| simulation_preview_screen.dart | Themed Card | Preview functionality |
| supply_chain_dashboard.dart | Emerald hero and themed cards | Charts, comparisons, PDF |
| user_management_settings.dart | Shared Ai cards | User management RBAC |
| work_entry_form_screen.dart | Themed form | Work reports and offline write |
| work_reports_dashboard.dart | Themed Card | Work report filtering |

## Startup

Flutter boot uses lib/presentation/widgets/eco_boot_splash.dart, with navigation still owned by SplashScreen in lib/main.dart. Android 11 and below use android/app/src/main/res/drawable/launch_background.xml. Android 12+ uses android/app/src/main/res/values-v31/styles.xml, setting the system splash background and logo explicitly to avoid the default white launcher phase.

## Automated regression checks

See test/eco_boot_splash_test.dart, test/visual_consistency_contract_test.dart, test/unified_visual_language_test.dart, and test/eco_visual_system_test.dart. The visual widgets have no new network/API dependencies. No Firebase rules, authorization checks, backend services, report calculations or message-sending logic were intentionally changed.

## Release sign-off

Run Flutter analysis and widget tests on the same commit as the APK. Inspect Arabic RTL on 320 dp and 390 dp devices and English on a narrow device. Check role-based navigation, splash transitions, bottom dock, report filters, assistant grid, maps, message composer, SOS, and keyboard-safe forms. Verify the installed APK commit before signing off.

Static inspection and widget tests do not prove a perfect layout on every physical Android device. Production visual acceptance requires device screenshots and interaction tests.
