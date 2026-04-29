import 'package:go_router/go_router.dart';
import '../screens/intro_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/permissions_screen.dart';
import '../screens/basic_info_screen.dart';
import '../screens/device_test_screen.dart';
import '../screens/home_screen.dart';
import '../screens/leaderboard_screen.dart';
import '../screens/passive_monitoring_permission_screen.dart';
import '../screens/monitoring_permission_screen.dart';
import '../screens/settings_screen.dart';
import '../utils/local_storage.dart';


GoRouter createRouter() {
  final initialLocation = LocalStorage.getInitialRoute();

  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/intro',
        name: 'intro',
        builder: (context, state) => const IntroScreen(),
      ),
      GoRoute(
        path: '/auth',
        name: 'auth',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/permissions',
        name: 'permissions',
        builder: (context, state) => const PermissionsScreen(),
      ),
      GoRoute(
        path: '/basic_info',
        name: 'basic_info',
        builder: (context, state) => const BasicInfoScreen(),
      ),
      // Day 8: Passive monitoring onboarding (shown once after basic_info)
      GoRoute(
        path: '/passive_permissions',
        name: 'passive_permissions',
        builder: (context, state) =>
            const PassiveMonitoringPermissionScreen(),
      ),
      // Day 9: Monitoring permission onboarding (Part 4)
      GoRoute(
        path: '/monitoring_permission',
        name: 'monitoring_permission',
        builder: (context, state) => const MonitoringPermissionScreen(),
      ),
      GoRoute(
        path: '/device_test',
        name: 'device_test',
        builder: (context, state) => const DeviceTestScreen(),
      ),
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/leaderboard',
        name: 'leaderboard',
        builder: (context, state) => const LeaderboardScreen(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}
