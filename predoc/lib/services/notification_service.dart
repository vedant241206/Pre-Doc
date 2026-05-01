// NotificationService — Day 11 (SMART NOTIFICATIONS)
//
// RULE-BASED. Deterministic. Zero AI. All logic reads from real data.
//
// SAFETY RULES:
//   ✓ Max 1–2 notifications per calendar day (enforced by SharedPreferences flag)
//   ✓ Notifications only fire if real data exists (no fake data)
//   ✓ All in-app — shown as styled SnackBar overlays
//   ✓ No spamming — at most 2 banners per day (daily summary + 1 alert)
//
// COLOR RULE:
//   Green  → good (score ≥ 80)
//   Yellow → moderate (score 50–79)
//   Red    → risk (score < 50)
//
// TRIGGER LOGIC (checked after session / on app open):
//   score < 50           → "Your health score is low today. Take care."
//   cough_count > 10     → "Frequent coughing detected today. Stay hydrated."
//   snore_count > 8      → "Poor sleep quality detected."
//   night_usage > 60 min → "Late night phone usage affecting sleep."
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../utils/local_storage.dart';
import '../services/dashboard_service.dart';
import '../services/insight_service.dart';
import '../services/passive_monitoring_service.dart';

class NotificationService {
  // ── Persistence keys ────────────────────────────────────────
  static const String _keyLastNotifDate      = 'last_notif_date';
  static const String _keyNotifCountToday    = 'notif_count_today';
  static const int    _maxNotificationsPerDay = 2;

  // ── Date helpers ─────────────────────────────────────────────
  static String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  static bool _canShowMore() {
    final today  = _dateKey(DateTime.now());
    final stored = LocalStorage.prefs.getString(_keyLastNotifDate) ?? '';
    if (stored != today) {
      // New day — reset counter
      LocalStorage.prefs.setString(_keyLastNotifDate, today);
      LocalStorage.prefs.setInt(_keyNotifCountToday, 0);
      return true;
    }
    final count = LocalStorage.prefs.getInt(_keyNotifCountToday) ?? 0;
    return count < _maxNotificationsPerDay;
  }

  static Future<void> _markShown() async {
    final today = _dateKey(DateTime.now());
    await LocalStorage.prefs.setString(_keyLastNotifDate, today);
    final count = LocalStorage.prefs.getInt(_keyNotifCountToday) ?? 0;
    await LocalStorage.prefs.setInt(_keyNotifCountToday, count + 1);
  }

  // ── Color mapping ─────────────────────────────────────────────
  static Color _bgColor(HealthColor hc) {
    switch (hc) {
      case HealthColor.green:  return const Color(0xFF16A34A);
      case HealthColor.yellow: return const Color(0xFFD97706);
      case HealthColor.red:    return const Color(0xFFDC2626);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PUBLIC — maybeShowDailyBanner
  // Shows a styled daily health summary banner (1st notification of the day).
  // Called from HomeScreen after first build.
  // ─────────────────────────────────────────────────────────────
  static Future<void> maybeShowDailyBanner(
    BuildContext context,
    TodaySummary today,
  ) async {
    if (!today.hasData) return;
    if (!_canShowMore()) return;

    await _markShown();
    if (!context.mounted) return;

    final color = _bgColor(today.color);

    _showBanner(
      context: context,
      backgroundColor: color,
      icon: Icons.health_and_safety_rounded,
      title: "Today's Health · ${today.severity.name.toUpperCase()}",
      body:  'Score: ${today.score}  ·  '
             'Cough: ${today.coughCount}  ·  '
             'Snore: ${today.snoreCount}',
    );
  }

  // ─────────────────────────────────────────────────────────────
  // PUBLIC — maybeShowSmartAlert
  // Fires ONE condition-based alert (the most critical one).
  // Call after refreshPassive / after session ends.
  // ─────────────────────────────────────────────────────────────
  static Future<void> maybeShowSmartAlert(
    BuildContext context, {
    required int score,
    required int coughCount,
    required int snoreCount,
    PassiveMonitoringData? passive,
  }) async {
    if (!_canShowMore()) return;
    if (!context.mounted) return;

    // Priority order: most severe first
    _Alert? alert;

    if (score < 50) {
      alert = _Alert(
        color: HealthColor.red,
        icon:  Icons.warning_amber_rounded,
        title: 'Low Health Score Today',
        body:  'Your health score is $score. Take care and rest well.',
      );
    } else if (coughCount > 10) {
      alert = const _Alert(
        color: HealthColor.red,
        icon:  Icons.air_rounded,
        title: 'Frequent Coughing Detected',
        body:  'Frequent coughing detected today. Stay hydrated and rest your voice.',
      );
    } else if (snoreCount > 8) {
      alert = const _Alert(
        color: HealthColor.yellow,
        icon:  Icons.bedtime_rounded,
        title: 'Poor Sleep Quality Detected',
        body:  'High snoring indicates disrupted sleep. Try a consistent bedtime.',
      );
    } else if ((passive?.nightUsageMinutes ?? 0) > 60) {
      alert = const _Alert(
        color: HealthColor.yellow,
        icon:  Icons.phone_android_rounded,
        title: 'Late Night Screen Usage',
        body:  'Late night phone usage is affecting your sleep quality.',
      );
    }

    if (alert == null) return;

    await _markShown();
    if (!context.mounted) return;

    _showBanner(
      context:         context,
      backgroundColor: _bgColor(alert.color),
      icon:            alert.icon,
      title:           alert.title,
      body:            alert.body,
      durationSec:     6,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // INTERNAL — shared SnackBar builder
  // ─────────────────────────────────────────────────────────────
  static void _showBanner({
    required BuildContext context,
    required Color     backgroundColor,
    required IconData  icon,
    required String    title,
    required String    body,
    int durationSec = 5,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration:        Duration(seconds: durationSec),
        backgroundColor: backgroundColor,
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// INTERNAL MODEL
// ─────────────────────────────────────────────────────────────

class _Alert {
  final HealthColor color;
  final IconData    icon;
  final String      title;
  final String      body;

  const _Alert({
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
  });
}
