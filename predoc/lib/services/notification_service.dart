// NotificationService — Day 6
//
// Fully local — no cloud, no flutter_local_notifications.
// Uses SharedPreferences to track "already shown today" so the
// in-app banner fires at most once per calendar day.
//
// The caller (HomeScreen) passes a BuildContext so we can show
// a styled overlay SnackBar after the screen is built.

import 'package:flutter/material.dart';
import '../utils/local_storage.dart';
import 'dashboard_service.dart';
import 'insight_service.dart';

class NotificationService {
  static const String _keyLastNotifDate = 'last_notif_date';

  // ── Has the in-app banner been shown today? ──
  static bool _shouldShowToday() {
    final stored = LocalStorage.prefs.getString(_keyLastNotifDate) ?? '';
    final today  = _dateKey(DateTime.now());
    return stored != today;
  }

  static Future<void> _markShown() async {
    await LocalStorage.prefs.setString(
      _keyLastNotifDate,
      _dateKey(DateTime.now()),
    );
  }

  static String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  // ── Color based on health status ──
  static Color _colorFor(HealthColor hc) {
    switch (hc) {
      case HealthColor.green:  return const Color(0xFF22C55E);
      case HealthColor.yellow: return const Color(0xFFF59E0B);
      case HealthColor.red:    return const Color(0xFFEF4444);
    }
  }

  static String _statusLabel(HealthColor hc) {
    switch (hc) {
      case HealthColor.green:  return 'Good ✓';
      case HealthColor.yellow: return 'Average';
      case HealthColor.red:    return 'Needs Attention ⚠';
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PUBLIC — call from HomeScreen after first build
  // ─────────────────────────────────────────────────────────────

  /// Shows a one-time daily in-app health summary banner.
  /// Safe to call even if there's no data (silently skipped).
  static Future<void> maybeShowDailyBanner(
    BuildContext context,
    TodaySummary today,
  ) async {
    if (!today.hasData) return;
    if (!_shouldShowToday()) return;

    await _markShown();

    if (!context.mounted) return;

    final bgColor = _colorFor(today.color);
    final status  = _statusLabel(today.color);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration:        const Duration(seconds: 5),
        backgroundColor: bgColor,
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.health_and_safety_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  "Today's Health · $status",
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Score: ${today.score}  ·  '
              'Cough: ${today.coughCount}  ·  '
              'Sneeze: ${today.sneezeCount}  ·  '
              'Snore: ${today.snoreCount}',
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
