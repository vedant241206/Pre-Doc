import 'package:shared_preferences/shared_preferences.dart';

/// LocalStorage — Day 13: Unified onboarding flags + strict redirect logic
class LocalStorage {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get prefs {
    if (_prefs == null) throw Exception('LocalStorage not initialized');
    return _prefs!;
  }

  // ── Onboarding state keys ─────────────────────────────────────────────
  static const String _keySeenIntro      = 'seen_intro';
  static const String _keyLoggedIn       = 'logged_in';        // loggedIn = authDone
  static const String _keyPermDone       = 'permissions_done';
  static const String _keyBasicInfoDone  = 'basic_info_done';
  static const String _keyDeviceTestDone = 'device_test_done';

  // Legacy compat keys (kept so old installs don't break)
  static const String _keyOnboardingDone = 'onboarding_done'; // mapped to seenIntro
  static const String _keySkipAuth       = 'skip_auth';
  static const String _keyAuthDone       = 'auth_done';       // mapped to loggedIn

  // ── Extra onboarding flags (Day 8/9 — still persisted but no longer blocking) ──
  static const String _keyPassiveMonitoringDone    = 'passive_monitoring_done';
  static const String _keyUsageStatsEnabled        = 'usage_stats_enabled';
  static const String _keyMonitoringOnboardingDone = 'monitoring_onboarding_done';

  // ── Profile keys ─────────────────────────────────────────────────────
  static const String _keyUserName    = 'user_name';
  static const String _keyUserEmail   = 'user_email';
  static const String _keyGender      = 'gender';
  static const String _keyDob         = 'dob';
  static const String _keyHeight      = 'height';
  static const String _keyWeight      = 'weight';
  static const String _keyHeightUnit  = 'height_unit';
  static const String _keyWeightUnit  = 'weight_unit';
  static const String _keyHeightFtInch = 'height_ft_inch';
  static const String _keyCountry     = 'user_country';
  static const String _keyCity        = 'user_city';

  // ═══════════════════════════════════════════════════════════════
  // ONBOARDING STATE FLAGS
  // ═══════════════════════════════════════════════════════════════

  /// Step 1: User has seen the intro splash screen
  static bool get seenIntro =>
      prefs.getBool(_keySeenIntro) ?? prefs.getBool(_keyOnboardingDone) ?? false;
  static Future<void> setSeenIntro() async {
    await prefs.setBool(_keySeenIntro, true);
    await prefs.setBool(_keyOnboardingDone, true); // compat
  }

  /// Step 2: User has completed auth (login / skip)
  static bool get loggedIn =>
      prefs.getBool(_keyLoggedIn) ??
      prefs.getBool(_keyAuthDone)  ?? false;
  static Future<void> setLoggedIn() async {
    await prefs.setBool(_keyLoggedIn, true);
    await prefs.setBool(_keyAuthDone, true); // compat
  }

  /// Step 3: All permissions granted (mic + camera + location)
  static bool get permissionsGranted => prefs.getBool(_keyPermDone) ?? false;
  static Future<void> setPermissionsGranted() async {
    await prefs.setBool(_keyPermDone, true);
  }

  /// Step 4: Basic profile info filled in
  static bool get basicInfoDone => prefs.getBool(_keyBasicInfoDone) ?? false;
  static Future<void> setBasicInfoDone() async {
    await prefs.setBool(_keyBasicInfoDone, true);
  }

  /// Step 5: Device test completed (mic + camera tested)
  static bool get deviceTestDone => prefs.getBool(_keyDeviceTestDone) ?? false;
  static Future<void> setDeviceTestDone() async {
    await prefs.setBool(_keyDeviceTestDone, true);
    // Mark legacy sub-steps as done too so old installs don't re-show them
    await prefs.setBool(_keyPassiveMonitoringDone, true);
    await prefs.setBool(_keyMonitoringOnboardingDone, true);
  }

  // ═══════════════════════════════════════════════════════════════
  // CENTRAL REDIRECT LOGIC (called by GoRouter.redirect)
  // ═══════════════════════════════════════════════════════════════
  //
  // Flow: Intro → Auth → Permissions → Basic Info → Device Test → Home
  //
  // Returns null if no redirect is needed (allow current route).
  // Returns a route string to redirect to.

  static String? computeRedirect(String currentLocation) {
    // Allow the target route itself (no loop)
    if (!seenIntro)          return currentLocation == '/intro'       ? null : '/intro';
    if (!loggedIn)           return currentLocation == '/auth'        ? null : '/auth';
    if (!permissionsGranted) return currentLocation == '/permissions' ? null : '/permissions';
    if (!basicInfoDone)      return currentLocation == '/basic_info'  ? null : '/basic_info';
    if (!deviceTestDone)     return currentLocation == '/device_test' ? null : '/device_test';
    // Onboarding complete — allow anything EXCEPT onboarding screens
    const onboardingRoutes = ['/intro', '/auth', '/permissions', '/basic_info', '/device_test'];
    if (onboardingRoutes.contains(currentLocation)) return '/home';
    return null; // no redirect needed
  }

  /// Returns the correct initial route based on saved state
  static String getInitialRoute() {
    if (!seenIntro)          return '/intro';
    if (!loggedIn)           return '/auth';
    if (!permissionsGranted) return '/permissions';
    if (!basicInfoDone)      return '/basic_info';
    if (!deviceTestDone)     return '/device_test';
    return '/home';
  }

  // ═══════════════════════════════════════════════════════════════
  // LEGACY COMPAT GETTERS (kept for existing code references)
  // ═══════════════════════════════════════════════════════════════

  /// @deprecated Use [seenIntro] — kept for compat
  static bool get onboardingDone => seenIntro;
  static Future<void> setOnboardingDone() => setSeenIntro();

  /// @deprecated Use [loggedIn] — kept for compat
  static bool get authDone => loggedIn;
  static Future<void> setAuthDone() => setLoggedIn();

  /// @deprecated Use [permissionsGranted] — kept for compat
  static bool get permissionsDone => permissionsGranted;
  static Future<void> setPermissionsDone() => setPermissionsGranted();

  static bool get skipAuth => prefs.getBool(_keySkipAuth) ?? false;
  static Future<void> setSkipAuth(bool val) => prefs.setBool(_keySkipAuth, val);

  static bool get passiveMonitoringDone =>
      prefs.getBool(_keyPassiveMonitoringDone) ?? false;
  static Future<void> setPassiveMonitoringDone() =>
      prefs.setBool(_keyPassiveMonitoringDone, true);

  static bool get usageStatsEnabled =>
      prefs.getBool(_keyUsageStatsEnabled) ?? false;
  static Future<void> setUsageStatsEnabled(bool val) =>
      prefs.setBool(_keyUsageStatsEnabled, val);

  static bool get monitoringOnboardingDone =>
      prefs.getBool(_keyMonitoringOnboardingDone) ?? false;
  static Future<void> setMonitoringOnboardingDone() =>
      prefs.setBool(_keyMonitoringOnboardingDone, true);

  // ═══════════════════════════════════════════════════════════════
  // PROFILE DATA
  // ═══════════════════════════════════════════════════════════════

  static String get heightFtInch => prefs.getString(_keyHeightFtInch) ?? '';
  static Future<void> setHeightFtInch(String val) => prefs.setString(_keyHeightFtInch, val);

  static String get userName  => prefs.getString(_keyUserName) ?? '';
  static Future<void> setUserName(String val) => prefs.setString(_keyUserName, val);

  static String get userEmail => prefs.getString(_keyUserEmail) ?? '';
  static Future<void> setUserEmail(String val) => prefs.setString(_keyUserEmail, val);

  static String get gender => prefs.getString(_keyGender) ?? '';
  static Future<void> setGender(String val) => prefs.setString(_keyGender, val);

  static String get dob => prefs.getString(_keyDob) ?? '';
  static Future<void> setDob(String val) => prefs.setString(_keyDob, val);

  static double get height => prefs.getDouble(_keyHeight) ?? 170.0;
  static Future<void> setHeight(double val) => prefs.setDouble(_keyHeight, val);

  static double get weight => prefs.getDouble(_keyWeight) ?? 65.0;
  static Future<void> setWeight(double val) => prefs.setDouble(_keyWeight, val);

  static String get heightUnit => prefs.getString(_keyHeightUnit) ?? 'cm';
  static Future<void> setHeightUnit(String val) => prefs.setString(_keyHeightUnit, val);

  static String get weightUnit => prefs.getString(_keyWeightUnit) ?? 'kg';
  static Future<void> setWeightUnit(String val) => prefs.setString(_keyWeightUnit, val);

  static String get country => prefs.getString(_keyCountry) ?? '';
  static Future<void> setCountry(String val) => prefs.setString(_keyCountry, val);

  static String get city => prefs.getString(_keyCity) ?? '';
  static Future<void> setCity(String val) => prefs.setString(_keyCity, val);
}
