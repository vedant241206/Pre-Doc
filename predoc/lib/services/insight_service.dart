// InsightService — fully offline, no packages required.
//
// Computes a health score (0–100) and wellness insight messages
// from stored detection counts + camera quality signals.
//
// RULES (from Day 5 spec):
//   cough_load  = min(coughCount / 12.0, 1.0)
//   sneeze_load = min(sneezeCount / 8.0,  1.0)
//   snore_load  = min(snoreCount  / 6.0,  1.0)
//   penalty     = (lowLight ? 0.05 : 0.0) + (faceDetected ? 0.0 : 0.05)
//   score       = 100 - round(40*cough + 25*sneeze + 25*snore + 10*penalty)
//               clamped to [0, 100]
//
// Health color:
//   80–100 → green
//   50–79  → yellow
//   0–49   → red

// ─────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────

enum HealthColor { green, yellow, red }

class InsightMessage {
  final String emoji;
  final String title;
  final String body;

  const InsightMessage({
    required this.emoji,
    required this.title,
    required this.body,
  });
}

class InsightResult {
  final int score;
  final HealthColor color;
  final double coughLoad;
  final double sneezeLoad;
  final double snoreLoad;
  final double penalty;
  final List<InsightMessage> messages;
  // Day 8: passive monitoring flags reflected in score
  final bool screenRisk;
  final bool sleepRisk;
  final bool sedentary;

  const InsightResult({
    required this.score,
    required this.color,
    required this.coughLoad,
    required this.sneezeLoad,
    required this.snoreLoad,
    required this.penalty,
    required this.messages,
    this.screenRisk = false,
    this.sleepRisk  = false,
    this.sedentary  = false,
  });

  /// CSS-style color label for display
  String get colorLabel {
    switch (color) {
      case HealthColor.green:
        return 'Good';
      case HealthColor.yellow:
        return 'Fair';
      case HealthColor.red:
        return 'Needs Attention';
    }
  }
}

// ─────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────

class InsightService {
  const InsightService();

  /// Compute the offline health score and insight messages.
  ///
  /// Parameters:
  ///   [coughCount]   — confirmed cough events in the session
  ///   [sneezeCount]  — confirmed sneeze events
  ///   [snoreCount]   — confirmed snore events
  ///   [faceDetected] — whether the camera found a face
  ///   [brightness]   — average Y-channel brightness (0–255)
  ///
  /// Day 8 optional passive monitoring parameters (all default false → no penalty):
  ///   [screenRisk]   — screen time > 5h today
  ///   [sleepRisk]    — night screen usage > 60 min
  ///   [sedentary]    — steps < 2000 (very low activity)
  ///
  /// Camera signals are quality checks only — not health predictions.
  InsightResult compute({
    required int    coughCount,
    required int    sneezeCount,
    required int    snoreCount,
    required bool   faceDetected,
    required double brightness,
    // Day 8 passive monitoring (optional — defaults keep existing behaviour)
    bool screenRisk = false,
    bool sleepRisk  = false,
    bool sedentary  = false,
  }) {
    // ── Load factors ──
    final coughLoad  = (coughCount  / 12.0).clamp(0.0, 1.0);
    final sneezeLoad = (sneezeCount / 8.0).clamp(0.0, 1.0);
    final snoreLoad  = (snoreCount  / 6.0).clamp(0.0, 1.0);

    // ── Camera quality penalty (not a health signal) ──
    final lowLight   = brightness < 50.0;
    double penalty   = 0.0;
    if (lowLight)       penalty += 0.05;
    if (!faceDetected)  penalty += 0.05;

    // ── Health score ──
    final raw = 100.0 -
        (40.0 * coughLoad +
         25.0 * sneezeLoad +
         25.0 * snoreLoad  +
         10.0 * penalty    +
         // Day 8: passive monitoring penalties
         (screenRisk ? 7.0  : 0.0) +
         (sleepRisk  ? 10.0 : 0.0) +
         (sedentary  ? 8.0  : 0.0));
    final score = raw.round().clamp(0, 100);

    // ── Color band ──
    HealthColor color;
    if (score >= 80) {
      color = HealthColor.green;
    } else if (score >= 50) {
      color = HealthColor.yellow;
    } else {
      color = HealthColor.red;
    }

    // ── Actionable wellness insight messages ──
    final messages = <InsightMessage>[];

    if (coughCount >= 4) {
      messages.add(const InsightMessage(
        emoji: '💧',
        title: 'Stay Hydrated',
        body:  'Frequent coughing was detected. Drink water and rest your voice.',
      ));
    }

    if (coughCount >= 8) {
      messages.add(const InsightMessage(
        emoji: '🛌',
        title: 'Rest Recommended',
        body:  'High cough count detected. Consider taking a break and resting.',
      ));
    }

    if (snoreCount >= 3) {
      messages.add(const InsightMessage(
        emoji: '🌙',
        title: 'Sleep Routine',
        body:  'Snoring patterns detected. A consistent sleep schedule may help.',
      ));
    }

    if (sneezeCount >= 3) {
      messages.add(const InsightMessage(
        emoji: '🌿',
        title: 'Allergen Check',
        body:  'Multiple sneezes detected. Consider checking for dust or allergens nearby.',
      ));
    }

    if (lowLight) {
      messages.add(const InsightMessage(
        emoji: '💡',
        title: 'Improve Lighting',
        body:  'Camera brightness was low. Move to a well-lit area for better results.',
      ));
    }

    if (!faceDetected) {
      messages.add(const InsightMessage(
        emoji: '📷',
        title: 'Retry Camera',
        body:  'No face was detected. Centre your face in the camera during the test.',
      ));
    }

    // ── Day 8: Behaviour insight messages ─────────────────────────
    if (screenRisk) {
      messages.add(const InsightMessage(
        emoji: '📱',
        title: 'Late-Night Screen Usage',
        body:  'Excessive screen time detected. Try reducing usage after 10 PM for better sleep.',
      ));
    }

    if (sleepRisk) {
      messages.add(const InsightMessage(
        emoji: '🌙',
        title: 'Sleep Pattern Needs Improvement',
        body:  'High phone usage at night detected. A consistent bedtime routine can improve sleep quality.',
      ));
    }

    if (sedentary) {
      messages.add(const InsightMessage(
        emoji: '🧍',
        title: 'Low Activity Today',
        body:  'Very few steps recorded. Try to take short walks throughout the day.',
      ));
    }

    if (messages.isEmpty) {
      messages.add(const InsightMessage(
        emoji: '✅',
        title: 'Looking Good!',
        body:  'No significant respiratory sounds or camera issues detected.',
      ));
    }

    return InsightResult(
      score:       score,
      color:       color,
      coughLoad:   coughLoad,
      sneezeLoad:  sneezeLoad,
      snoreLoad:   snoreLoad,
      penalty:     penalty,
      messages:    messages,
      // Day 8 passive flags
      screenRisk:  screenRisk,
      sleepRisk:   sleepRisk,
      sedentary:   sedentary,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // DAY 8: COMBINED LIVE SCORE (continuous monitoring formula)
  // ─────────────────────────────────────────────────────────────
  //
  // score = 100
  // score -= cough_count  * 2
  // score -= sneeze_count * 1.5
  // score -= snore_count  * 2
  // if night_usage > 60 min:  score -= 10
  // if screen_time > 5h:      score -= 7
  // if low_activity:          score -= 8
  // score = clamp(score, 0, 100)

  InsightResult computeCombined({
    required int  liveCoughCount,
    required int  liveSneezeCount,
    required int  liveSnoreCount,
    required bool nightUsageRisk,   // night_usage > 60 min
    required bool screenTimeRisk,   // screen_time > 5h
    required bool lowActivity,      // steps < 2000
  }) {
    double score = 100.0;

    score -= liveCoughCount  * 2.0;
    score -= liveSneezeCount * 1.5;
    score -= liveSnoreCount  * 2.0;

    if (nightUsageRisk) score -= 10.0;
    if (screenTimeRisk) score -= 7.0;
    if (lowActivity)    score -= 8.0;

    final finalScore = score.round().clamp(0, 100);

    HealthColor color;
    if (finalScore >= 80) {
      color = HealthColor.green;
    } else if (finalScore >= 50) {
      color = HealthColor.yellow;
    } else {
      color = HealthColor.red;
    }

    final messages = <InsightMessage>[];

    if (liveCoughCount >= 3) {
      messages.add(const InsightMessage(
        emoji: '💧',
        title: 'Coughing Detected',
        body:  'Live monitoring detected repeated coughing. Stay hydrated.',
      ));
    }
    if (liveSneezeCount >= 3) {
      messages.add(const InsightMessage(
        emoji: '🌿',
        title: 'Frequent Sneezing',
        body:  'Live monitoring picked up sneezing. Check for dust or allergens.',
      ));
    }
    if (liveSnoreCount >= 2) {
      messages.add(const InsightMessage(
        emoji: '😴',
        title: 'Snoring Detected',
        body:  'Snoring was detected during monitoring. A regular sleep schedule may help.',
      ));
    }
    if (nightUsageRisk) {
      messages.add(const InsightMessage(
        emoji: '🌙',
        title: 'Late-Night Usage',
        body:  'High phone use after 10 PM is affecting your sleep quality.',
      ));
    }
    if (screenTimeRisk) {
      messages.add(const InsightMessage(
        emoji: '📱',
        title: 'Screen Time High',
        body:  'Over 5 hours of screen time today. Take regular eye breaks.',
      ));
    }
    if (lowActivity) {
      messages.add(const InsightMessage(
        emoji: '🏃',
        title: 'Move More',
        body:  'Very low activity detected. Even a short walk helps.',
      ));
    }

    if (messages.isEmpty) {
      messages.add(const InsightMessage(
        emoji: '✅',
        title: 'All Clear',
        body:  'No health signals detected during live monitoring.',
      ));
    }

    return InsightResult(
      score:      finalScore,
      color:      color,
      coughLoad:  (liveCoughCount  / 12.0).clamp(0.0, 1.0),
      sneezeLoad: (liveSneezeCount / 8.0).clamp(0.0, 1.0),
      snoreLoad:  (liveSnoreCount  / 6.0).clamp(0.0, 1.0),
      penalty:    0.0,
      messages:   messages,
      screenRisk: screenTimeRisk,
      sleepRisk:  nightUsageRisk,
      sedentary:  lowActivity,
    );
  }
}
