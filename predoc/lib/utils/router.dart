import 'package:go_router/go_router.dart';
import '../screens/intro_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/permissions_screen.dart';
import '../screens/basic_info_screen.dart';
import '../screens/home_screen.dart';
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
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
    ],
  );
}
