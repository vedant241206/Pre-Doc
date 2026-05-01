// UserContextService — Day 10
//
// Reads Day 10 multi-condition flags from StorageService and computes
// personalized detection thresholds.
//
// Day 10 Spec:
//   if asthma:         cough_threshold = 0.25
//   if frequent cold:  sneeze_threshold = 0.30
//   if sleep issues:   snore_penalty += 3 (snore min windows raised to 7)
//
// Also retains legacy single-condition support for ContinuousAudioService.

import '../utils/local_storage.dart';
import '../services/storage_service.dart';

// ─────────────────────────────────────────────────────────────
// HEALTH CONDITION ENUM (legacy — kept for ContinuousAudioService)
// ─────────────────────────────────────────────────────────────

enum HealthCondition {
  none,
  asthma,
  cold,
  copd,
  allergy,
  bronchitis,
  sleepApnea,
  flu,
}

extension HealthConditionExtension on HealthCondition {
  String get key {
    switch (this) {
      case HealthCondition.none:        return 'none';
      case HealthCondition.asthma:      return 'asthma';
      case HealthCondition.cold:        return 'cold';
      case HealthCondition.copd:        return 'copd';
      case HealthCondition.allergy:     return 'allergy';
      case HealthCondition.bronchitis:  return 'bronchitis';
      case HealthCondition.sleepApnea:  return 'sleep_apnea';
      case HealthCondition.flu:         return 'flu';
    }
  }

  String get label {
    switch (this) {
      case HealthCondition.none:        return 'None';
      case HealthCondition.asthma:      return 'Asthma';
      case HealthCondition.cold:        return 'Cold / Common Cold';
      case HealthCondition.copd:        return 'COPD';
      case HealthCondition.allergy:     return 'Allergy / Hay Fever';
      case HealthCondition.bronchitis:  return 'Bronchitis';
      case HealthCondition.sleepApnea:  return 'Sleep Apnea';
      case HealthCondition.flu:         return 'Flu / Influenza';
    }
  }

  String get description {
    switch (this) {
      case HealthCondition.none:
        return 'No known respiratory condition';
      case HealthCondition.asthma:
        return 'Increases cough detection sensitivity';
      case HealthCondition.cold:
        return 'Increases sneeze detection sensitivity';
      case HealthCondition.copd:
        return 'Increases cough and snore sensitivity';
      case HealthCondition.allergy:
        return 'Increases sneeze detection sensitivity';
      case HealthCondition.bronchitis:
        return 'Increases cough detection sensitivity';
      case HealthCondition.sleepApnea:
        return 'Increases snore detection sensitivity';
      case HealthCondition.flu:
        return 'Moderately increases all detection sensitivity';
    }
  }

  String get emoji {
    switch (this) {
      case HealthCondition.none:        return '✅';
      case HealthCondition.asthma:      return '💨';
      case HealthCondition.cold:        return '🤧';
      case HealthCondition.copd:        return '🫁';
      case HealthCondition.allergy:     return '🌿';
      case HealthCondition.bronchitis:  return '🔴';
      case HealthCondition.sleepApnea:  return '😴';
      case HealthCondition.flu:         return '🤒';
    }
  }

  static HealthCondition fromKey(String key) {
    for (final c in HealthCondition.values) {
      if (c.key == key) return c;
    }
    return HealthCondition.none;
  }
}

// ─────────────────────────────────────────────────────────────
// THRESHOLD PROFILE
// ─────────────────────────────────────────────────────────────

class ThresholdProfile {
  final double coughThreshold;
  final double sneezeThreshold;
  final double snoreThreshold;
  /// Day 10: extra minimum windows required for snore (snore_penalty)
  final int    snoreMinWindowsExtra;

  const ThresholdProfile({
    required this.coughThreshold,
    required this.sneezeThreshold,
    required this.snoreThreshold,
    this.snoreMinWindowsExtra = 0,
  });
}

// ─────────────────────────────────────────────────────────────
// USER CONTEXT SERVICE
// ─────────────────────────────────────────────────────────────

class UserContextService {
  // ── Baseline thresholds ──
  static const double _baseCough  = 0.30;
  static const double _baseSneeze = 0.35;
  static const double _baseSnore  = 0.40;

  // ── Legacy persistence key (single-condition) ───────────────
  static const String _keyCondition = 'user_health_condition';

  // ── Legacy single-condition get/set ─────────────────────────
  static HealthCondition getCondition() {
    final key = LocalStorage.prefs.getString(_keyCondition) ?? 'none';
    return HealthConditionExtension.fromKey(key);
  }

  static Future<void> setCondition(HealthCondition condition) async {
    await LocalStorage.prefs.setString(_keyCondition, condition.key);
  }

  // ─────────────────────────────────────────────────────────────
  // DAY 10: MULTI-CONDITION THRESHOLDS
  //
  // Reads Day 10 multi-condition flags and applies the spec rules:
  //   asthma        → cough_threshold  = 0.25
  //   frequent cold → sneeze_threshold = 0.30
  //   sleep issues  → snore min windows += 3 (stricter snore confirmation)
  // ─────────────────────────────────────────────────────────────
  static ThresholdProfile getThresholdsDay10() {
    double cough  = _baseCough;
    double sneeze = _baseSneeze;
    double snore  = _baseSnore;
    int    snoreExtra = 0;

    if (StorageService.condAsthma) {
      cough = 0.25; // More sensitive to coughs
    }

    if (StorageService.condFrequentCold) {
      sneeze = 0.30; // More sensitive to sneezes
    }

    if (StorageService.condSleepIssues) {
      // snore_penalty += 3 → raise min windows to confirm snore
      // (requires MORE evidence — reduces false alarms during normal sleep)
      snoreExtra = 3;
    }

    return ThresholdProfile(
      coughThreshold:       cough.clamp(0.10, 0.90),
      sneezeThreshold:      sneeze.clamp(0.10, 0.90),
      snoreThreshold:       snore.clamp(0.10, 0.90),
      snoreMinWindowsExtra: snoreExtra,
    );
  }

  // ── Legacy single-condition thresholds (for ContinuousAudioService) ──
  static ThresholdProfile getThresholds() {
    // First apply Day 10 multi-condition logic
    final day10 = getThresholdsDay10();

    // Then overlay with the legacy single condition (e.g., COPD, Allergy)
    final condition = getCondition();
    if (condition == HealthCondition.none) return day10;

    return _mergeWithLegacy(day10, condition);
  }

  static ThresholdProfile _mergeWithLegacy(
    ThresholdProfile base,
    HealthCondition c,
  ) {
    // Take the more sensitive (lower) threshold of Day10 vs legacy
    final legacy = _profileFor(c);
    return ThresholdProfile(
      coughThreshold:       _lower(base.coughThreshold,  legacy.coughThreshold),
      sneezeThreshold:      _lower(base.sneezeThreshold, legacy.sneezeThreshold),
      snoreThreshold:       _lower(base.snoreThreshold,  legacy.snoreThreshold),
      snoreMinWindowsExtra: base.snoreMinWindowsExtra,
    );
  }

  static double _lower(double a, double b) => a < b ? a : b;

  static ThresholdProfile _profileFor(HealthCondition c) {
    switch (c) {
      case HealthCondition.asthma:
        return const ThresholdProfile(
          coughThreshold:  0.25,
          sneezeThreshold: 0.35,
          snoreThreshold:  0.40,
        );
      case HealthCondition.cold:
        return const ThresholdProfile(
          coughThreshold:  0.28,
          sneezeThreshold: 0.28,
          snoreThreshold:  0.40,
        );
      case HealthCondition.copd:
        return const ThresholdProfile(
          coughThreshold:  0.22,
          sneezeThreshold: 0.35,
          snoreThreshold:  0.32,
        );
      case HealthCondition.allergy:
        return const ThresholdProfile(
          coughThreshold:  0.30,
          sneezeThreshold: 0.27,
          snoreThreshold:  0.40,
        );
      case HealthCondition.bronchitis:
        return const ThresholdProfile(
          coughThreshold:  0.23,
          sneezeThreshold: 0.35,
          snoreThreshold:  0.40,
        );
      case HealthCondition.sleepApnea:
        return const ThresholdProfile(
          coughThreshold:  0.30,
          sneezeThreshold: 0.35,
          snoreThreshold:  0.28,
        );
      case HealthCondition.flu:
        return const ThresholdProfile(
          coughThreshold:  0.26,
          sneezeThreshold: 0.28,
          snoreThreshold:  0.38,
        );
      case HealthCondition.none:
        return const ThresholdProfile(
          coughThreshold:  _baseCough,
          sneezeThreshold: _baseSneeze,
          snoreThreshold:  _baseSnore,
        );
    }
  }
}
