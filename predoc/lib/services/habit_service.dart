// HabitService — Day 11
//
// PURE RULE-BASED. Zero AI. Deterministic. All data stays on-device.
//
// Responsibilities:
//   1. Generate a daily summary string from today's data.
//   2. Detect habits from 7-day snapshot history (3-day rule).
//   3. Build predictive warnings from trend data.
//   4. Generate action suggestions based on detected habits.
//
// DATA FLOW:
//   DailySnapshot (StorageService) → HabitService → HabitReport
//
// SAFETY RULES:
//   ✓ No network calls
//   ✓ No fake data — all logic reads from real StorageService snapshots
//   ✓ Minimum 3 data points required for any detection
// ─────────────────────────────────────────────────────────────

import '../services/storage_service.dart';
import '../services/insight_service.dart';
import '../services/passive_monitoring_service.dart';

// ─────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────

/// A single detected habit with metadata.
class DetectedHabit {
  final String emoji;
  final String title;
  final String description;
  final HealthColor color; // green | yellow | red

  const DetectedHabit({
    required this.emoji,
    required this.title,
    required this.description,
    required this.color,
  });
}

/// A predictive warning derived from 3-day trends.
class PredictiveWarning {
  final String emoji;
  final String title;
  final String detail;
  final HealthColor severity; // yellow | red

  const PredictiveWarning({
    required this.emoji,
    required this.title,
    required this.detail,
    required this.severity,
  });
}

/// An actionable suggestion tied to a detected habit or warning.
class ActionSuggestion {
  final String emoji;
  final String action;

  const ActionSuggestion({required this.emoji, required this.action});
}

/// The complete Day 11 output produced by HabitService.
class HabitReport {
  final String dailySummary;       // Human-readable summary string
  final List<DetectedHabit> habits;
  final List<PredictiveWarning> predictions;
  final List<ActionSuggestion> suggestions;
  final bool hasEnoughData;        // true if ≥3 snapshots exist

  const HabitReport({
    required this.dailySummary,
    required this.habits,
    required this.predictions,
    required this.suggestions,
    required this.hasEnoughData,
  });

  static const HabitReport empty = HabitReport(
    dailySummary: '',
    habits: [],
    predictions: [],
    suggestions: [],
    hasEnoughData: false,
  );
}

// ─────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────

class HabitService {
  const HabitService();

  // ─────────────────────────────────────────────────────────────
  // PRIMARY ENTRY POINT
  // Call after dashboard is loaded (synchronous — reads SharedPreferences).
  // ─────────────────────────────────────────────────────────────
  HabitReport compute({
    required int todayScore,
    required int todayCough,
    required int todaySneeze,
    required int todaySnore,
    PassiveMonitoringData? passive,
  }) {
    final snapshots = StorageService.getDailySnapshots(days: 7);

    // ── Daily Summary ──────────────────────────────────────────
    final summary = _buildDailySummary(
      score:    todayScore,
      cough:    todayCough,
      snore:    todaySnore,
      passive:  passive,
    );

    if (snapshots.length < 3) {
      // Not enough data for habits/predictions yet — still return summary
      return HabitReport(
        dailySummary:  summary,
        habits:        [],
        predictions:   [],
        suggestions:   [],
        hasEnoughData: false,
      );
    }

    // ── Take last 3 entries (most recent) ─────────────────────
    final recent = snapshots.length >= 3
        ? snapshots.sublist(snapshots.length - 3)
        : snapshots;

    // ── Habit Detection ───────────────────────────────────────
    final habits = _detectHabits(recent, passive);

    // ── Predictive Warnings ───────────────────────────────────
    final predictions = _buildPredictions(recent);

    // ── Action Suggestions ────────────────────────────────────
    final suggestions = _buildSuggestions(habits, predictions);

    return HabitReport(
      dailySummary:  summary,
      habits:        habits,
      predictions:   predictions,
      suggestions:   suggestions,
      hasEnoughData: true,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // PART 2: DAILY SUMMARY ENGINE
  // ─────────────────────────────────────────────────────────────
  String _buildDailySummary({
    required int score,
    required int cough,
    required int snore,
    PassiveMonitoringData? passive,
  }) {
    final sleepLabel    = passive != null
        ? passive.sleepQualityLabel
        : 'Unknown';
    final activityLabel = passive != null
        ? passive.activityLabel
        : 'Unknown';

    return 'Score: $score\n'
           'Cough: $cough\n'
           'Sleep: $sleepLabel\n'
           'Activity: $activityLabel';
  }

  // ─────────────────────────────────────────────────────────────
  // PART 4: HABIT DETECTION LOGIC (3-day rule)
  // ─────────────────────────────────────────────────────────────
  List<DetectedHabit> _detectHabits(
    List<DailySnapshot> recent,
    PassiveMonitoringData? passive,
  ) {
    final habits = <DetectedHabit>[];

    // ── Late night usage habit ──
    // night_usage_risk true for all 3 recent days
    final allNightRisk = recent.every((s) => s.nightUsageRisk);
    if (allNightRisk) {
      habits.add(const DetectedHabit(
        emoji:       '🌙',
        title:       'Late Night Usage Habit',
        description: 'High phone use after 10 PM for 3+ consecutive days.',
        color:       HealthColor.red,
      ));
    }

    // ── Inactive lifestyle habit ──
    // low_activity true for all 3 recent days
    final allInactive = recent.every((s) => s.lowActivity);
    if (allInactive) {
      habits.add(const DetectedHabit(
        emoji:       '🛋️',
        title:       'Inactive Lifestyle',
        description: 'Low activity detected for 3 consecutive days.',
        color:       HealthColor.yellow,
      ));
    }

    // ── Worsening respiratory pattern ──
    // cough strictly increasing over last 3 days
    if (_strictlyIncreasing(recent.map((s) => s.coughCount).toList())) {
      habits.add(const DetectedHabit(
        emoji:       '🫁',
        title:       'Worsening Respiratory Pattern',
        description: 'Coughing has increased each of the last 3 days.',
        color:       HealthColor.red,
      ));
    }

    // ── High screen time habit ──
    final allScreenRisk = recent.every((s) => s.screenTimeRisk);
    if (allScreenRisk) {
      habits.add(const DetectedHabit(
        emoji:       '📱',
        title:       'High Screen Time Habit',
        description: 'Screen time exceeded 5 hours for 3 consecutive days.',
        color:       HealthColor.yellow,
      ));
    }

    return habits;
  }

  // ─────────────────────────────────────────────────────────────
  // PART 5: PREDICTIVE WARNING SYSTEM
  // ─────────────────────────────────────────────────────────────
  List<PredictiveWarning> _buildPredictions(List<DailySnapshot> recent) {
    final warnings = <PredictiveWarning>[];

    // ── Possible upcoming illness — cough increasing 3 days ──
    if (_strictlyIncreasing(recent.map((s) => s.coughCount).toList())) {
      warnings.add(const PredictiveWarning(
        emoji:    '⚕️',
        title:    'Possible Upcoming Illness',
        detail:   'Coughing trend is increasing. Early rest and hydration can help.',
        severity: HealthColor.red,
      ));
    }

    // ── Sleep quality deteriorating — snore increasing 3 days ──
    if (_strictlyIncreasing(recent.map((s) => s.snoreCount).toList())) {
      warnings.add(const PredictiveWarning(
        emoji:    '😴',
        title:    'Sleep Quality Deteriorating',
        detail:   'Snoring has risen each of the last 3 nights. Adjust your sleep schedule.',
        severity: HealthColor.yellow,
      ));
    }

    // ── Health risk due to inactivity — steps decreasing 3 days ──
    if (_strictlyDecreasing(recent.map((s) => s.stepCount).toList())) {
      warnings.add(const PredictiveWarning(
        emoji:    '⚠️',
        title:    'Health Risk Due to Inactivity',
        detail:   'Activity levels have dropped for 3 consecutive days.',
        severity: HealthColor.yellow,
      ));
    }

    // ── Overall health score declining ──
    if (_strictlyDecreasing(recent.map((s) => s.healthScore).toList())) {
      warnings.add(const PredictiveWarning(
        emoji:    '📉',
        title:    'Health Score Declining',
        detail:   'Your health score has dropped 3 days in a row. Review your habits.',
        severity: HealthColor.red,
      ));
    }

    return warnings;
  }

  // ─────────────────────────────────────────────────────────────
  // PART 6: ACTION SUGGESTION ENGINE
  // ─────────────────────────────────────────────────────────────
  List<ActionSuggestion> _buildSuggestions(
    List<DetectedHabit> habits,
    List<PredictiveWarning> predictions,
  ) {
    final suggestions = <ActionSuggestion>[];
    final seen = <String>{};

    void addSuggestion(ActionSuggestion s) {
      if (!seen.contains(s.action)) {
        seen.add(s.action);
        suggestions.add(s);
      }
    }

    for (final h in habits) {
      switch (h.title) {
        case 'Late Night Usage Habit':
          addSuggestion(const ActionSuggestion(
            emoji:  '🌙',
            action: 'Sleep earlier today — avoid phone after 10 PM.',
          ));
          break;
        case 'Inactive Lifestyle':
          addSuggestion(const ActionSuggestion(
            emoji:  '🚶',
            action: 'Take a 10-minute walk to boost your activity.',
          ));
          break;
        case 'Worsening Respiratory Pattern':
          addSuggestion(const ActionSuggestion(
            emoji:  '💧',
            action: 'Drink warm fluids and rest your voice.',
          ));
          break;
        case 'High Screen Time Habit':
          addSuggestion(const ActionSuggestion(
            emoji:  '👁️',
            action: 'Apply the 20-20-20 rule: every 20 min, look 20 ft away for 20 sec.',
          ));
          break;
      }
    }

    for (final p in predictions) {
      switch (p.title) {
        case 'Possible Upcoming Illness':
          addSuggestion(const ActionSuggestion(
            emoji:  '🫖',
            action: 'Drink warm fluids and get extra rest tonight.',
          ));
          break;
        case 'Sleep Quality Deteriorating':
          addSuggestion(const ActionSuggestion(
            emoji:  '🛏️',
            action: 'Set a consistent bedtime and avoid screens 1 hour before sleep.',
          ));
          break;
        case 'Health Risk Due to Inactivity':
          addSuggestion(const ActionSuggestion(
            emoji:  '🏃',
            action: 'Start with a short 10-minute stretch or walk each morning.',
          ));
          break;
      }
    }

    return suggestions;
  }

  // ─────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────

  bool _strictlyIncreasing(List<int> values) {
    if (values.length < 2) return false;
    for (int i = 1; i < values.length; i++) {
      if (values[i] <= values[i - 1]) return false;
    }
    return true;
  }

  bool _strictlyDecreasing(List<int> values) {
    if (values.length < 2) return false;
    for (int i = 1; i < values.length; i++) {
      if (values[i] >= values[i - 1]) return false;
    }
    return true;
  }
}
