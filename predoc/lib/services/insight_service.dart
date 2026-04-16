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

  const InsightResult({
    required this.score,
    required this.color,
    required this.coughLoad,
    required this.sneezeLoad,
    required this.snoreLoad,
    required this.penalty,
    required this.messages,
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
  /// Camera signals are quality checks only — not health predictions.
  InsightResult compute({
    required int    coughCount,
    required int    sneezeCount,
    required int    snoreCount,
    required bool   faceDetected,
    required double brightness,
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
         10.0 * penalty);
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

    if (messages.isEmpty) {
      messages.add(const InsightMessage(
        emoji: '✅',
        title: 'Looking Good!',
        body:  'No significant respiratory sounds or camera issues detected.',
      ));
    }

    return InsightResult(
      score:      score,
      color:      color,
      coughLoad:  coughLoad,
      sneezeLoad: sneezeLoad,
      snoreLoad:  snoreLoad,
      penalty:    penalty,
      messages:   messages,
    );
  }
}
