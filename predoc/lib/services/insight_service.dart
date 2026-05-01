// InsightService — Day 10 (FULL REWRITE)
//
// PURE RULE-BASED. Zero AI. Deterministic.
//
// HEALTH SCORE FORMULA (strict):
//   score = 100
//   score -= cough_count  * 2
//   score -= sneeze_count * 1.5
//   score -= snore_count  * 2
//   if night_usage > 60:  score -= 10
//   if screen_time > 5h:  score -= 7
//   if low_activity:      score -= 8
//   score = clamp(score, 0, 100)
//
// SEVERITY:
//   >= 80  → good
//   50–79  → moderate
//   < 50   → risk

// ─────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────

enum HealthColor { green, yellow, red }

enum HealthSeverity { good, moderate, risk }

class InsightMessage {
  final String emoji;
  final String title;
  final String body;
  final HealthSeverity severity;

  const InsightMessage({
    required this.emoji,
    required this.title,
    required this.body,
    this.severity = HealthSeverity.moderate,
  });
}

class HealthPattern {
  final String emoji;
  final String label;
  final String description;

  const HealthPattern({
    required this.emoji,
    required this.label,
    required this.description,
  });
}

class InsightResult {
  final int score;
  final HealthColor color;
  final HealthSeverity severity;
  final double coughLoad;
  final double sneezeLoad;
  final double snoreLoad;
  final double penalty;
  final List<InsightMessage> messages;
  final List<HealthPattern> patterns;

  // Legacy passive flags (still used by DashboardService)
  final bool screenRisk;
  final bool sleepRisk;
  final bool sedentary;

  const InsightResult({
    required this.score,
    required this.color,
    required this.severity,
    required this.coughLoad,
    required this.sneezeLoad,
    required this.snoreLoad,
    required this.penalty,
    required this.messages,
    required this.patterns,
    this.screenRisk = false,
    this.sleepRisk  = false,
    this.sedentary  = false,
  });

  String get colorLabel {
    switch (color) {
      case HealthColor.green:  return 'Good';
      case HealthColor.yellow: return 'Moderate';
      case HealthColor.red:    return 'Risk';
    }
  }

  String get severityLabel {
    switch (severity) {
      case HealthSeverity.good:     return 'Good';
      case HealthSeverity.moderate: return 'Moderate';
      case HealthSeverity.risk:     return 'At Risk';
    }
  }

  String get severityEmoji {
    switch (severity) {
      case HealthSeverity.good:     return '✅';
      case HealthSeverity.moderate: return '⚠️';
      case HealthSeverity.risk:     return '🔴';
    }
  }
}

// ─────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────

class InsightService {
  const InsightService();

  // ─────────────────────────────────────────────────────────────
  // LEGACY compute() — kept for DashboardService.computeToday()
  // ─────────────────────────────────────────────────────────────
  InsightResult compute({
    required int    coughCount,
    required int    sneezeCount,
    required int    snoreCount,
    required bool   faceDetected,
    required double brightness,
    bool screenRisk = false,
    bool sleepRisk  = false,
    bool sedentary  = false,
  }) {
    return computeCombined(
      liveCoughCount:  coughCount,
      liveSneezeCount: sneezeCount,
      liveSnoreCount:  snoreCount,
      nightUsageRisk:  sleepRisk,
      screenTimeRisk:  screenRisk,
      lowActivity:     sedentary,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // PRIMARY: computeCombined — Day 10 strict formula
  // ─────────────────────────────────────────────────────────────
  InsightResult computeCombined({
    required int  liveCoughCount,
    required int  liveSneezeCount,
    required int  liveSnoreCount,
    required bool nightUsageRisk,   // night_usage > 60 min
    required bool screenTimeRisk,   // screen_time > 5h
    required bool lowActivity,      // steps < 2000
    List<HealthPattern> patterns = const [],
  }) {
    // ── DAY 10 STRICT SCORE FORMULA ──────────────────────────
    double score = 100.0;

    score -= liveCoughCount  * 2.0;
    score -= liveSneezeCount * 1.5;
    score -= liveSnoreCount  * 2.0;

    if (nightUsageRisk) score -= 10.0;
    if (screenTimeRisk) score -= 7.0;
    if (lowActivity)    score -= 8.0;

    final finalScore = score.round().clamp(0, 100);

    // ── SEVERITY TAGGING ─────────────────────────────────────
    HealthSeverity severity;
    HealthColor color;
    if (finalScore >= 80) {
      severity = HealthSeverity.good;
      color    = HealthColor.green;
    } else if (finalScore >= 50) {
      severity = HealthSeverity.moderate;
      color    = HealthColor.yellow;
    } else {
      severity = HealthSeverity.risk;
      color    = HealthColor.red;
    }

    // ── DAY 10 RULE-BASED INSIGHT MESSAGES ───────────────────
    final messages = <InsightMessage>[];

    // ── RESPIRATORY ──
    if (liveCoughCount > 12) {
      messages.add(const InsightMessage(
        emoji:    '🫁',
        title:    'High Coughing Frequency',
        body:     'Possible irritation or infection. Stay hydrated and rest your voice.',
        severity: HealthSeverity.risk,
      ));
    } else if (liveCoughCount >= 4) {
      messages.add(const InsightMessage(
        emoji:    '💧',
        title:    'Coughing Detected',
        body:     'Drink water and rest your voice.',
        severity: HealthSeverity.moderate,
      ));
    }

    if (liveSneezeCount > 10) {
      messages.add(const InsightMessage(
        emoji:    '🌿',
        title:    'Frequent Sneezing',
        body:     'Possible allergy or cold. Check for dust or allergens nearby.',
        severity: HealthSeverity.risk,
      ));
    } else if (liveSneezeCount >= 3) {
      messages.add(const InsightMessage(
        emoji:    '🤧',
        title:    'Sneezing Detected',
        body:     'Multiple sneezes detected. Consider checking for allergens.',
        severity: HealthSeverity.moderate,
      ));
    }

    // ── SLEEP ──
    if (liveSnoreCount > 8) {
      messages.add(const InsightMessage(
        emoji:    '😴',
        title:    'Snoring Indicates Poor Sleep Quality',
        body:     'High snoring count suggests disrupted sleep. A consistent sleep schedule may help.',
        severity: HealthSeverity.risk,
      ));
    } else if (liveSnoreCount >= 2) {
      messages.add(const InsightMessage(
        emoji:    '🌙',
        title:    'Snoring Pattern Detected',
        body:     'Snoring was detected. A regular sleep routine may help.',
        severity: HealthSeverity.moderate,
      ));
    }

    if (nightUsageRisk) {
      messages.add(const InsightMessage(
        emoji:    '📵',
        title:    'Late Night Usage Affecting Sleep Cycle',
        body:     'High phone usage after 10 PM is disrupting your sleep quality.',
        severity: HealthSeverity.risk,
      ));
    }

    // ── ACTIVITY ──
    if (lowActivity) {
      messages.add(const InsightMessage(
        emoji:    '🏃',
        title:    'Low Activity Detected',
        body:     'Very few steps recorded today. Try to increase movement — even short walks help.',
        severity: HealthSeverity.moderate,
      ));
    }

    // ── SCREEN TIME ──
    if (screenTimeRisk) {
      messages.add(const InsightMessage(
        emoji:    '📱',
        title:    'Screen Time High',
        body:     'Over 5 hours of screen time today. Take regular eye breaks.',
        severity: HealthSeverity.moderate,
      ));
    }

    // ── COMBINED PATTERNS ──
    if (liveCoughCount > 10 && liveSnoreCount > 6) {
      messages.add(const InsightMessage(
        emoji:    '⚠️',
        title:    'Respiratory + Sleep Issue Pattern',
        body:     'High coughing and snoring together suggest a combined respiratory and sleep concern.',
        severity: HealthSeverity.risk,
      ));
    }

    // ── FALLBACK ──
    if (messages.isEmpty) {
      messages.add(const InsightMessage(
        emoji:    '✅',
        title:    'All Clear',
        body:     'No significant health signals detected. Keep it up!',
        severity: HealthSeverity.good,
      ));
    }

    // ── LOAD FACTORS (for backwards compat) ─────────────────
    final coughLoad  = (liveCoughCount  / 12.0).clamp(0.0, 1.0);
    final sneezeLoad = (liveSneezeCount / 8.0).clamp(0.0, 1.0);
    final snoreLoad  = (liveSnoreCount  / 6.0).clamp(0.0, 1.0);

    return InsightResult(
      score:       finalScore,
      color:       color,
      severity:    severity,
      coughLoad:   coughLoad,
      sneezeLoad:  sneezeLoad,
      snoreLoad:   snoreLoad,
      penalty:     0.0,
      messages:    messages,
      patterns:    patterns,
      screenRisk:  screenTimeRisk,
      sleepRisk:   nightUsageRisk,
      sedentary:   lowActivity,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // PATTERN DETECTION — over last 7 days of daily snapshots
  //
  // Expects a list of DailySnapshot objects (most recent last).
  // ─────────────────────────────────────────────────────────────
  List<HealthPattern> detectPatterns(List<DailySnapshot> last7Days) {
    final patterns = <HealthPattern>[];
    if (last7Days.length < 3) return patterns;

    // Take the last 3 entries (most recent)
    final recent = last7Days.length >= 3
        ? last7Days.sublist(last7Days.length - 3)
        : last7Days;

    // ── Worsening respiratory: cough increasing 3 days ──
    if (_increasing(recent.map((s) => s.coughCount).toList())) {
      patterns.add(const HealthPattern(
        emoji:       '📈',
        label:       'Worsening Respiratory Trend',
        description: 'Coughing has increased over the last 3 days.',
      ));
    }

    // ── Snore increasing ──
    if (_increasing(recent.map((s) => s.snoreCount).toList())) {
      patterns.add(const HealthPattern(
        emoji:       '😴',
        label:       'Sleep Deterioration',
        description: 'Snoring has been increasing — sleep quality may be declining.',
      ));
    }

    // ── Inactivity increasing (step count decreasing) ──
    if (_decreasing(recent.map((s) => s.stepCount).toList())) {
      patterns.add(const HealthPattern(
        emoji:       '🛋️',
        label:       'Lifestyle Decline',
        description: 'Activity levels have been declining over the last 3 days.',
      ));
    }

    // ── Score declining ──
    if (_decreasing(recent.map((s) => s.healthScore).toList())) {
      patterns.add(const HealthPattern(
        emoji:       '📉',
        label:       'Health Score Declining',
        description: 'Your overall health score has dropped 3 days in a row.',
      ));
    }

    return patterns;
  }

  // ─────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────

  /// Returns true if values are strictly increasing over the list.
  bool _increasing(List<int> values) {
    if (values.length < 2) return false;
    for (int i = 1; i < values.length; i++) {
      if (values[i] <= values[i - 1]) return false;
    }
    return true;
  }

  /// Returns true if values are strictly decreasing over the list.
  bool _decreasing(List<int> values) {
    if (values.length < 2) return false;
    for (int i = 1; i < values.length; i++) {
      if (values[i] >= values[i - 1]) return false;
    }
    return true;
  }
}

// ─────────────────────────────────────────────────────────────
// DAILY SNAPSHOT — lightweight struct for 7-day pattern tracking
// ─────────────────────────────────────────────────────────────

class DailySnapshot {
  final String dateKey;
  final int coughCount;
  final int sneezeCount;
  final int snoreCount;
  final int stepCount;
  final int healthScore;
  final bool nightUsageRisk;
  final bool screenTimeRisk;
  final bool lowActivity;

  const DailySnapshot({
    required this.dateKey,
    required this.coughCount,
    required this.sneezeCount,
    required this.snoreCount,
    required this.stepCount,
    required this.healthScore,
    this.nightUsageRisk = false,
    this.screenTimeRisk = false,
    this.lowActivity    = false,
  });

  Map<String, dynamic> toJson() => {
        'date_key':         dateKey,
        'cough_count':      coughCount,
        'sneeze_count':     sneezeCount,
        'snore_count':      snoreCount,
        'step_count':       stepCount,
        'health_score':     healthScore,
        'night_usage_risk': nightUsageRisk,
        'screen_time_risk': screenTimeRisk,
        'low_activity':     lowActivity,
      };

  factory DailySnapshot.fromJson(Map<String, dynamic> j) => DailySnapshot(
        dateKey:       j['date_key']         as String? ?? '',
        coughCount:    j['cough_count']      as int?    ?? 0,
        sneezeCount:   j['sneeze_count']     as int?    ?? 0,
        snoreCount:    j['snore_count']      as int?    ?? 0,
        stepCount:     j['step_count']       as int?    ?? 0,
        healthScore:   j['health_score']     as int?    ?? 0,
        nightUsageRisk: j['night_usage_risk'] as bool?  ?? false,
        screenTimeRisk: j['screen_time_risk'] as bool?  ?? false,
        lowActivity:   j['low_activity']     as bool?   ?? false,
      );
}
