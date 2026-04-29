import 'package:shared_preferences/shared_preferences.dart';

class LocalStorage {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get prefs {
    if (_prefs == null) throw Exception('LocalStorage not initialized');
    return _prefs!;
  }

  // Keys
  static const String _keyOnboardingDone = 'onboarding_done';
  static const String _keySkipAuth = 'skip_auth';
  static const String _keyAuthDone = 'auth_done';
  static const String _keyPermissionsDone = 'permissions_done';
  static const String _keyUserName = 'user_name';
  static const String _keyUserEmail = 'user_email';
  static const String _keyGender = 'gender';
  static const String _keyDob = 'dob';
  static const String _keyHeight = 'height';
  static const String _keyWeight = 'weight';
  static const String _keyHeightUnit = 'height_unit';
  static const String _keyWeightUnit = 'weight_unit';
  static const String _keyBasicInfoDone = 'basic_info_done';
  static const String _keyHeightFtInch = 'height_ft_inch'; // stored as "5'11"
  static const String _keyCountry = 'user_country';
  static const String _keyCity    = 'user_city';
  // Day 8: Passive monitoring onboarding
  static const String _keyPassiveMonitoringDone = 'passive_monitoring_done';
  static const String _keyUsageStatsEnabled     = 'usage_stats_enabled';

  // Onboarding
  static bool get onboardingDone => prefs.getBool(_keyOnboardingDone) ?? false;
  static Future<void> setOnboardingDone() => prefs.setBool(_keyOnboardingDone, true);

  // Auth
  static bool get skipAuth => prefs.getBool(_keySkipAuth) ?? false;
  static Future<void> setSkipAuth(bool val) => prefs.setBool(_keySkipAuth, val);

  static bool get authDone => prefs.getBool(_keyAuthDone) ?? false;
  static Future<void> setAuthDone() => prefs.setBool(_keyAuthDone, true);

  // Permissions
  static bool get permissionsDone => prefs.getBool(_keyPermissionsDone) ?? false;
  static Future<void> setPermissionsDone() => prefs.setBool(_keyPermissionsDone, true);

  // Basic Info setup
  static bool get basicInfoDone => prefs.getBool(_keyBasicInfoDone) ?? false;
  static Future<void> setBasicInfoDone() => prefs.setBool(_keyBasicInfoDone, true);

  // Passive Monitoring onboarding (Day 8)
  static bool get passiveMonitoringDone =>
      prefs.getBool(_keyPassiveMonitoringDone) ?? false;
  static Future<void> setPassiveMonitoringDone() =>
      prefs.setBool(_keyPassiveMonitoringDone, true);

  static bool get usageStatsEnabled =>
      prefs.getBool(_keyUsageStatsEnabled) ?? false;
  static Future<void> setUsageStatsEnabled(bool val) =>
      prefs.setBool(_keyUsageStatsEnabled, val);

  static String get heightFtInch => prefs.getString(_keyHeightFtInch) ?? '';
  static Future<void> setHeightFtInch(String val) => prefs.setString(_keyHeightFtInch, val);

  // User info
  static String get userName => prefs.getString(_keyUserName) ?? '';
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

  /// Returns the initial route based on saved state
  static String getInitialRoute() {
    if (!onboardingDone)  return '/intro';
    if (!authDone && !skipAuth) return '/auth';
    if (!permissionsDone) return '/permissions';
    if (!basicInfoDone)   return '/basic_info';
    if (!passiveMonitoringDone) return '/passive_permissions';
    return '/home';
  }
}
