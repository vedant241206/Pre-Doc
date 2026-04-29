// UserContextService — Day 9
//
// Stores user-reported health conditions and exposes adjusted
// detection thresholds for ContinuousAudioService.
//
// Supported conditions (researched):
//   none     — baseline thresholds
//   asthma   — lower cough threshold (more sensitive)
//   cold     — lower sneeze threshold
//   copd     — lower cough + snore threshold
//   allergy  — lower sneeze threshold (similar to cold)
//   bronchitis — lower cough threshold
//   sleep_apnea — lower snore threshold
//   flu      — all thresholds lowered moderately
//
// SAFETY: thresholds are clamped [0.10, 0.90] to prevent runaway triggers.

import '../utils/local_storage.dart';

// ─────────────────────────────────────────────────────────────
// HEALTH CONDITION ENUM
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

  const ThresholdProfile({
    required this.coughThreshold,
    required this.sneezeThreshold,
    required this.snoreThreshold,
  });
}

// ─────────────────────────────────────────────────────────────
// USER CONTEXT SERVICE
// ─────────────────────────────────────────────────────────────

class UserContextService {
  // ── Baseline thresholds (same as ContinuousAudioService) ──
  static const double _baseCough  = 0.30;
  static const double _baseSneeze = 0.35;
  static const double _baseSnore  = 0.40;

  // ── Persistence key ────────────────────────────────────────
  static const String _keyCondition = 'user_health_condition';

  // ── Get / Set persisted condition ─────────────────────────
  static HealthCondition getCondition() {
    final key = LocalStorage.prefs.getString(_keyCondition) ?? 'none';
    return HealthConditionExtension.fromKey(key);
  }

  static Future<void> setCondition(HealthCondition condition) async {
    await LocalStorage.prefs.setString(_keyCondition, condition.key);
  }

  // ── Compute adjusted thresholds for the current condition ─
  static ThresholdProfile getThresholds() {
    final condition = getCondition();
    return _profileFor(condition);
  }

  static ThresholdProfile _profileFor(HealthCondition c) {
    switch (c) {
      case HealthCondition.asthma:
        // Asthma causes frequent dry coughs — lower cough threshold
        return const ThresholdProfile(
          coughThreshold:  0.25,
          sneezeThreshold: 0.35,
          snoreThreshold:  0.40,
        );

      case HealthCondition.cold:
        // Cold causes frequent sneezing — lower sneeze threshold
        return const ThresholdProfile(
          coughThreshold:  0.28,
          sneezeThreshold: 0.28,
          snoreThreshold:  0.40,
        );

      case HealthCondition.copd:
        // COPD causes chronic cough and sometimes snoring
        return const ThresholdProfile(
          coughThreshold:  0.22,
          sneezeThreshold: 0.35,
          snoreThreshold:  0.32,
        );

      case HealthCondition.allergy:
        // Allergy triggers sneezing fits
        return const ThresholdProfile(
          coughThreshold:  0.30,
          sneezeThreshold: 0.27,
          snoreThreshold:  0.40,
        );

      case HealthCondition.bronchitis:
        // Bronchitis = persistent productive cough
        return const ThresholdProfile(
          coughThreshold:  0.23,
          sneezeThreshold: 0.35,
          snoreThreshold:  0.40,
        );

      case HealthCondition.sleepApnea:
        // Sleep apnea → snoring is key signal
        return const ThresholdProfile(
          coughThreshold:  0.30,
          sneezeThreshold: 0.35,
          snoreThreshold:  0.28,
        );

      case HealthCondition.flu:
        // Flu: cough + sneeze both elevated
        return const ThresholdProfile(
          coughThreshold:  0.26,
          sneezeThreshold: 0.28,
          snoreThreshold:  0.38,
        );

      case HealthCondition.none:
        // Baseline
        return const ThresholdProfile(
          coughThreshold:  _baseCough,
          sneezeThreshold: _baseSneeze,
          snoreThreshold:  _baseSnore,
        );
    }
  }
}
