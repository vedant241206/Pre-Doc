// PassiveMonitoringService — Day 8
//
// Reads passive behavioral signals (screen time, activity, sleep, light)
// and computes risk flags used by InsightService scoring.
//
// SAFETY RULES:
//   ✓ No continuous polling — called only on app open / manual refresh
//   ✓ No exact app tracking — only aggregate screen time totals
//   ✓ No screen content reading — only usage durations
//   ✓ All data stays on-device in SharedPreferences
//   ✓ No network calls
//
// ARCHITECTURE:
//   PassiveMonitoringService.refresh() → PassiveMonitoringData
//   Caller stores result via StorageService.savePassiveData()

import 'package:flutter/services.dart';
import '../services/storage_service.dart';

// ─────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────

enum ActivityLevel { low, medium, good }

enum SleepQuality { good, fair, poor, unknown }

class PassiveMonitoringData {
  final int screenTimeMinutes;    // total screen time today (minutes)
  final int nightUsageMinutes;    // screen-on between 22:00–05:00 (minutes)
  final ActivityLevel activityLevel;
  final SleepQuality sleepQuality;
  final bool screenRisk;          // screen_time > 5h
  final bool sleepRisk;           // night_usage > 60 min
  final bool sedentary;           // activity = LOW
  final bool lateNightPattern;    // night >60 min for 3+ consecutive days
  final bool eyeStrain;           // low ambient light + screen on
  final bool usageStatsAvailable; // whether native data was readable
  final String dateKey;           // 'yyyy-M-d' of when this was computed

  const PassiveMonitoringData({
    required this.screenTimeMinutes,
    required this.nightUsageMinutes,
    required this.activityLevel,
    required this.sleepQuality,
    required this.screenRisk,
    required this.sleepRisk,
    required this.sedentary,
    required this.lateNightPattern,
    required this.eyeStrain,
    required this.usageStatsAvailable,
    required this.dateKey,
  });

  // ── Label helpers ──────────────────────────────────────────

  String get screenTimeLabel {
    final h = screenTimeMinutes ~/ 60;
    final m = screenTimeMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String get activityLabel {
    switch (activityLevel) {
      case ActivityLevel.low:    return 'Low';
      case ActivityLevel.medium: return 'Moderate';
      case ActivityLevel.good:   return 'Active';
    }
  }

  String get sleepQualityLabel {
    switch (sleepQuality) {
      case SleepQuality.good:    return 'Good';
      case SleepQuality.fair:    return 'Fair';
      case SleepQuality.poor:    return 'Poor';
      case SleepQuality.unknown: return 'No data';
    }
  }

  // ── Serialisation (for StorageService) ────────────────────

  Map<String, dynamic> toJson() => {
    'screen_time_min':       screenTimeMinutes,
    'night_usage_min':       nightUsageMinutes,
    'activity_level':        activityLevel.name,
    'sleep_quality':         sleepQuality.name,
    'screen_risk':           screenRisk,
    'sleep_risk':            sleepRisk,
    'sedentary':             sedentary,
    'late_night_pattern':    lateNightPattern,
    'eye_strain':            eyeStrain,
    'usage_stats_available': usageStatsAvailable,
    'date_key':              dateKey,
  };

  factory PassiveMonitoringData.fromJson(Map<String, dynamic> j) =>
      PassiveMonitoringData(
        screenTimeMinutes:    (j['screen_time_min']    as num?)?.toInt() ?? 0,
        nightUsageMinutes:    (j['night_usage_min']    as num?)?.toInt() ?? 0,
        activityLevel:        _parseActivity(j['activity_level'] as String? ?? 'low'),
        sleepQuality:         _parseSleep(j['sleep_quality']     as String? ?? 'unknown'),
        screenRisk:           j['screen_risk']           as bool? ?? false,
        sleepRisk:            j['sleep_risk']            as bool? ?? false,
        sedentary:            j['sedentary']             as bool? ?? false,
        lateNightPattern:     j['late_night_pattern']    as bool? ?? false,
        eyeStrain:            j['eye_strain']            as bool? ?? false,
        usageStatsAvailable:  j['usage_stats_available'] as bool? ?? false,
        dateKey:              j['date_key']              as String? ?? '',
      );

  static ActivityLevel _parseActivity(String s) {
    switch (s) {
      case 'medium': return ActivityLevel.medium;
      case 'good':   return ActivityLevel.good;
      default:       return ActivityLevel.low;
    }
  }

  static SleepQuality _parseSleep(String s) {
    switch (s) {
      case 'good': return SleepQuality.good;
      case 'fair': return SleepQuality.fair;
      case 'poor': return SleepQuality.poor;
      default:     return SleepQuality.unknown;
    }
  }

  /// Empty / placeholder (no permissions / no data)
  static PassiveMonitoringData get empty => PassiveMonitoringData(
    screenTimeMinutes:   0,
    nightUsageMinutes:   0,
    activityLevel:       ActivityLevel.medium,
    sleepQuality:        SleepQuality.unknown,
    screenRisk:          false,
    sleepRisk:           false,
    sedentary:           false,
    lateNightPattern:    false,
    eyeStrain:           false,
    usageStatsAvailable: false,
    dateKey:             _todayKey(),
  );

  static String _todayKey() {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }
}

// ─────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────

class PassiveMonitoringService {
  const PassiveMonitoringService();

  static const _channel = MethodChannel('predoc/usage_stats');

  // ── THRESHOLDS ────────────────────────────────────────────
  static const int _screenRiskThresholdMin = 300;  // 5 hours
  static const int _sleepRiskThresholdMin  = 60;   // 1 hour
  static const int _lateNightConsecutiveDays = 3;
  static const int _sedentaryStepThreshold  = 2000;
  static const int _mediumStepThreshold     = 6000;

  // ─────────────────────────────────────────────────────────
  // PRIMARY ENTRY POINT
  // Call this on app open / pull-to-refresh only (NOT in a loop).
  // ─────────────────────────────────────────────────────────

  Future<PassiveMonitoringData> refresh() async {
    // 1. Check if usage stats permission is available
    final usageGranted = await _isUsageStatsGranted();

    // 2. Read screen time from native (returns -1 if not granted)
    int screenTimeMin = 0;
    int nightUsageMin = 0;

    if (usageGranted) {
      screenTimeMin = await _getTodayScreenTime();
      nightUsageMin = await _getNightUsage();
    }

    // 3. Compute risk flags
    final screenRisk = usageGranted && screenTimeMin > _screenRiskThresholdMin;
    final sleepRisk  = usageGranted && nightUsageMin > _sleepRiskThresholdMin;

    // 4. Late-night pattern: check last 7 days history
    bool lateNightPattern = false;
    if (usageGranted) {
      final history = await _getLast7DaysNightUsage();
      lateNightPattern = _detectLateNightPattern(history);
    }

    // 5. Activity level — read stored step count (set externally or default 0)
    final steps = StorageService.todaySteps;
    final activityLevel = _computeActivityLevel(steps);
    final sedentary = activityLevel == ActivityLevel.low;

    // 6. Sleep detection — heuristic from night usage + screen patterns
    final sleepQuality = _computeSleepQuality(
      nightUsageMin: nightUsageMin,
      usageGranted: usageGranted,
    );

    // 7. Eye strain — use last session's brightness as ambient light proxy
    final lastBrightness = StorageService.brightnessLevel;
    final eyeStrain = lastBrightness < 40.0 && screenTimeMin > 60;

    return PassiveMonitoringData(
      screenTimeMinutes:   screenTimeMin,
      nightUsageMinutes:   nightUsageMin,
      activityLevel:       activityLevel,
      sleepQuality:        sleepQuality,
      screenRisk:          screenRisk,
      sleepRisk:           sleepRisk,
      sedentary:           sedentary,
      lateNightPattern:    lateNightPattern,
      eyeStrain:           eyeStrain,
      usageStatsAvailable: usageGranted,
      dateKey:             _todayKey(),
    );
  }

  // ── PLATFORM CALLS ────────────────────────────────────────

  Future<bool> isUsageStatsGranted() => _isUsageStatsGranted();

  Future<bool> _isUsageStatsGranted() async {
    try {
      final result = await _channel.invokeMethod<bool>('isUsageStatsGranted');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<int> _getTodayScreenTime() async {
    try {
      final result = await _channel.invokeMethod<int>('getTodayScreenTime');
      return (result ?? 0).clamp(0, 1440); // max 24 hours
    } catch (_) {
      return 0;
    }
  }

  Future<int> _getNightUsage() async {
    try {
      final result = await _channel.invokeMethod<int>('getNightUsage');
      return (result ?? 0).clamp(0, 420); // max 7 hours (22:00–05:00)
    } catch (_) {
      return 0;
    }
  }

  Future<List<int>> _getLast7DaysNightUsage() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getLast7DaysNightUsage');
      return result?.map((e) => (e as num).toInt()).toList() ?? List.filled(7, 0);
    } catch (_) {
      return List.filled(7, 0);
    }
  }

  Future<bool> openUsageSettings() async {
    try {
      final result = await _channel.invokeMethod<bool>('openUsageSettings');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── COMPUTATIONS ──────────────────────────────────────────

  /// Detect if night usage exceeded 60 min for 3+ consecutive recent days.
  bool _detectLateNightPattern(List<int> last7Days) {
    if (last7Days.length < _lateNightConsecutiveDays) return false;

    int streak = 0;
    // Check from most recent day backwards
    for (int i = last7Days.length - 1; i >= 0; i--) {
      if (last7Days[i] > _sleepRiskThresholdMin) {
        streak++;
        if (streak >= _lateNightConsecutiveDays) return true;
      } else {
        streak = 0;
      }
    }
    return false;
  }

  /// Map stored step count to activity level.
  ActivityLevel _computeActivityLevel(int steps) {
    if (steps < _sedentaryStepThreshold) return ActivityLevel.low;
    if (steps < _mediumStepThreshold)    return ActivityLevel.medium;
    return ActivityLevel.good;
  }

  /// Heuristic sleep quality from night screen usage.
  SleepQuality _computeSleepQuality({
    required int nightUsageMin,
    required bool usageGranted,
  }) {
    if (!usageGranted) return SleepQuality.unknown;
    if (nightUsageMin == 0) return SleepQuality.good;      // phone off all night
    if (nightUsageMin <= 20) return SleepQuality.fair;     // brief checks
    if (nightUsageMin <= _sleepRiskThresholdMin) return SleepQuality.fair;
    return SleepQuality.poor;                               // > 60 min late night
  }

  String _todayKey() {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }
}
