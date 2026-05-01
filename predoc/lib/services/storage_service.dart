import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../utils/local_storage.dart';
import '../services/audio_service.dart';
import '../services/passive_monitoring_service.dart';
import '../services/insight_service.dart';


// ─────────────────────────────────────────────────────────────
// SESSION RESULT  (what gets persisted per test run)
// ─────────────────────────────────────────────────────────────

class SessionResult {
  final String sessionStart;
  final String sessionEnd;
  final int coughCount;
  final int sneezeCount;
  final int snoreCount;
  final bool faceDetected;
  final double brightnessValue;
  final bool lowLight;
  final List<AudioWindowLog> windows;

  const SessionResult({
    required this.sessionStart,
    required this.sessionEnd,
    required this.coughCount,
    required this.sneezeCount,
    required this.snoreCount,
    required this.faceDetected,
    required this.brightnessValue,
    required this.lowLight,
    required this.windows,
  });

  Map<String, dynamic> toJson() => {
        'session_start':   sessionStart,
        'session_end':     sessionEnd,
        'cough_count':     coughCount,
        'sneeze_count':    sneezeCount,
        'snore_count':     snoreCount,
        'face_detected':   faceDetected,
        'brightness_value': brightnessValue,
        'low_light':       lowLight,
        'windows':         windows.map((w) => w.toJson()).toList(),
      };

  factory SessionResult.fromJson(Map<String, dynamic> json) => SessionResult(
        sessionStart:    json['session_start']   as String? ?? '',
        sessionEnd:      json['session_end']     as String? ?? '',
        coughCount:      json['cough_count']     as int?    ?? 0,
        sneezeCount:     json['sneeze_count']    as int?    ?? 0,
        snoreCount:      json['snore_count']     as int?    ?? 0,
        faceDetected:    json['face_detected']   as bool?   ?? false,
        brightnessValue: (json['brightness_value'] as num?)?.toDouble() ?? 0.0,
        lowLight:        json['low_light']       as bool?   ?? false,
        windows:         [], // raw logs are stored but not parsed back for perf
      );
}

// ─────────────────────────────────────────────────────────────
// STORAGE SERVICE
// ─────────────────────────────────────────────────────────────

/// StorageService handles saving/loading detection results locally.
/// All data stays on-device (SharedPreferences — no cloud, no backend).
class StorageService {
  // ── Flat-key store (legacy / screen-facing) ──
  static const String _keyCoughCount    = 'cough_count';
  static const String _keySneeze        = 'sneeze_count';
  static const String _keySnore         = 'snore_count';
  static const String _keyEyeColor      = 'eye_color';
  static const String _keyBrightness    = 'brightness_level';
  static const String _keyFaceDetected  = 'face_detected';
  static const String _keyFaceEmbedding = 'face_embedding';
  static const String _keyDeviceTestDone = 'device_test_done';

  // ── Session JSON log ──
  static const String _keySessionLogs   = 'session_logs';
  static const int    _maxSessions      = 20;

  // ── Calibration threshold offsets ──
  static const String _keyCalibCough    = 'calib_cough_offset';
  static const String _keyCalibSneeze   = 'calib_sneeze_offset';
  static const String _keyCalibSnore    = 'calib_snore_offset';

  // ── Passive Monitoring log (Day 8) ──
  static const String _keyPassiveLogs   = 'passive_monitoring_log';
  static const String _keyTodaySteps    = 'today_steps';
  static const int    _maxPassiveDays   = 30;

  // ── Live Monitoring (Day 8 / Day 9) ──
  static const String _keyLiveEvents         = 'live_events_log';
  static const String _keyLiveDailyCough     = 'live_daily_cough';
  static const String _keyLiveDailySneeze    = 'live_daily_sneeze';
  static const String _keyLiveDailySnore     = 'live_daily_snore';
  static const String _keyLiveDailyDate      = 'live_daily_date';
  static const String _keyLiveMonitoringOn   = 'live_monitoring_enabled';
  static const String _keyLastUpdated        = 'live_last_updated';
  static const int    _maxLiveEvents         = 200;

  // ── Day 9: Reactive live-count notifier ─────────────────────────
  static final ValueNotifier<Map<String, dynamic>> liveCountsNotifier =
      ValueNotifier<Map<String, dynamic>>({'cough': 0, 'sneeze': 0, 'snore': 0, 'lastUpdated': ''});

  // ─────────────────────────────────────────────────────────────
  // DAY 10: PROFILE FIELDS
  // ─────────────────────────────────────────────────────────────
  static const String _keyUserAge           = 'user_age';
  static const String _keyNotificationTime  = 'notification_time'; // "HH:mm"

  // ── Day 10: Multi-condition flags ──────────────────────────
  // Stored as individual booleans (a user can have multiple conditions)
  static const String _keyCondAsthma        = 'cond_asthma';
  static const String _keyCondFrequentCold  = 'cond_frequent_cold';
  static const String _keyCondSleepIssues   = 'cond_sleep_issues';

  // ── Day 10: 7-day daily snapshot log (for pattern detection) ──
  static const String _keyDailySnapshots    = 'daily_snapshots';
  static const int    _maxSnapshots         = 30;

  // ── Day 11: Daily summary history ──
  static const String _keyDailySummaries    = 'daily_summaries';
  static const int    _maxSummaries         = 30;

  // ─────────────────────────────────────────
  // FLAT-KEY SAVE (called by DeviceTestScreen._finish)
  // ─────────────────────────────────────────
  static Future<void> saveDetectionResult({
    required int coughCount,
    required int sneezeCount,
    required int snoreCount,
    required String eyeColor,
    required double brightnessLevel,
    required bool faceDetected,
    required String faceEmbedding,
  }) async {
    await LocalStorage.prefs.setInt(_keyCoughCount,   coughCount);
    await LocalStorage.prefs.setInt(_keySneeze,       sneezeCount);
    await LocalStorage.prefs.setInt(_keySnore,        snoreCount);
    await LocalStorage.prefs.setString(_keyEyeColor,  eyeColor);
    await LocalStorage.prefs.setDouble(_keyBrightness, brightnessLevel);
    await LocalStorage.prefs.setBool(_keyFaceDetected, faceDetected);
    await LocalStorage.prefs.setString(_keyFaceEmbedding, faceEmbedding);
    await LocalStorage.prefs.setBool(_keyDeviceTestDone, true);
  }

  // ─────────────────────────────────────────
  // SESSION JSON STORE (Day 5)
  // ─────────────────────────────────────────

  /// Append a full session to the local JSON log.
  static Future<void> saveSession(SessionResult session) async {
    final raw = LocalStorage.prefs.getString(_keySessionLogs) ?? '[]';
    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      list = [];
    }

    list.add(session.toJson());

    if (list.length > _maxSessions) {
      list = list.sublist(list.length - _maxSessions);
    }

    await LocalStorage.prefs.setString(_keySessionLogs, jsonEncode(list));
  }

  /// Load all stored sessions (most recent first).
  static List<SessionResult> getSessions() {
    final raw = LocalStorage.prefs.getString(_keySessionLogs) ?? '[]';
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => SessionResult.fromJson(e as Map<String, dynamic>))
          .toList()
          .reversed
          .toList();
    } catch (e) {
      return [];
    }
  }

  // ─────────────────────────────────────────
  // CALIBRATION THRESHOLD OFFSETS (Day 5)
  // ─────────────────────────────────────────

  static double get coughOffset  => LocalStorage.prefs.getDouble(_keyCalibCough)   ?? 0.0;
  static double get sneezeOffset => LocalStorage.prefs.getDouble(_keyCalibSneeze)  ?? 0.0;
  static double get snoreOffset  => LocalStorage.prefs.getDouble(_keyCalibSnore)   ?? 0.0;

  static Future<void> raiseCoughThreshold()  async =>
      await LocalStorage.prefs.setDouble(_keyCalibCough,  (coughOffset + 0.03).clamp(-0.15, 0.15));
  static Future<void> raiseSneezeThreshold() async =>
      await LocalStorage.prefs.setDouble(_keyCalibSneeze, (sneezeOffset + 0.03).clamp(-0.15, 0.15));
  static Future<void> raiseSnoreThreshold()  async =>
      await LocalStorage.prefs.setDouble(_keyCalibSnore,  (snoreOffset + 0.03).clamp(-0.15, 0.15));

  static Future<void> lowerCoughThreshold()  async =>
      await LocalStorage.prefs.setDouble(_keyCalibCough,  (coughOffset - 0.03).clamp(-0.15, 0.15));
  static Future<void> lowerSneezeThreshold() async =>
      await LocalStorage.prefs.setDouble(_keyCalibSneeze, (sneezeOffset - 0.03).clamp(-0.15, 0.15));
  static Future<void> lowerSnoreThreshold()  async =>
      await LocalStorage.prefs.setDouble(_keyCalibSnore,  (snoreOffset - 0.03).clamp(-0.15, 0.15));

  static Future<void> resetCalibration() async {
    await LocalStorage.prefs.setDouble(_keyCalibCough,   0.0);
    await LocalStorage.prefs.setDouble(_keyCalibSneeze,  0.0);
    await LocalStorage.prefs.setDouble(_keyCalibSnore,   0.0);
  }

  // ─────────────────────────────────────
  // FLAT-KEY GETTERS (legacy, unchanged)
  // ─────────────────────────────────────
  static int    get coughCount      => LocalStorage.prefs.getInt(_keyCoughCount)       ?? 0;
  static int    get sneezeCount     => LocalStorage.prefs.getInt(_keySneeze)           ?? 0;
  static int    get snoreCount      => LocalStorage.prefs.getInt(_keySnore)            ?? 0;
  static String get eyeColor        => LocalStorage.prefs.getString(_keyEyeColor)      ?? '';
  static double get brightnessLevel => LocalStorage.prefs.getDouble(_keyBrightness)   ?? 0.0;
  static bool   get faceDetected    => LocalStorage.prefs.getBool(_keyFaceDetected)    ?? false;
  static bool   get deviceTestDone  => LocalStorage.prefs.getBool(_keyDeviceTestDone)  ?? false;
  static String get faceEmbedding   => LocalStorage.prefs.getString(_keyFaceEmbedding) ?? '';

  static int    get todaySteps      => LocalStorage.prefs.getInt(_keyTodaySteps)       ?? 0;
  static Future<void> setTodaySteps(int steps) =>
      LocalStorage.prefs.setInt(_keyTodaySteps, steps);

  // ── Live Monitoring toggle preference ──
  static bool get liveMonitoringEnabled =>
      LocalStorage.prefs.getBool(_keyLiveMonitoringOn) ?? false;
  static Future<void> setLiveMonitoringEnabled(bool val) =>
      LocalStorage.prefs.setBool(_keyLiveMonitoringOn, val);

  // ── Last updated timestamp ────────────────────────────────────────
  static String get lastUpdated =>
      LocalStorage.prefs.getString(_keyLastUpdated) ?? '';

  // ── Initialize notifier from persisted state (call at app start) ──
  static void initLiveCountsNotifier() {
    liveCountsNotifier.value = _currentLiveCounts();
  }

  // ─────────────────────────────────────────────────────────────
  // DAY 10: PROFILE FIELDS
  // ─────────────────────────────────────────────────────────────

  static int    get userAge            => LocalStorage.prefs.getInt(_keyUserAge)            ?? 0;
  static Future<void> setUserAge(int age) =>
      LocalStorage.prefs.setInt(_keyUserAge, age);

  static String get notificationTime   => LocalStorage.prefs.getString(_keyNotificationTime) ?? '08:00';
  static Future<void> setNotificationTime(String time) =>
      LocalStorage.prefs.setString(_keyNotificationTime, time);

  // ─────────────────────────────────────────────────────────────
  // DAY 10: MULTI-CONDITION FLAGS
  // ─────────────────────────────────────────────────────────────

  static bool get condAsthma       => LocalStorage.prefs.getBool(_keyCondAsthma)       ?? false;
  static bool get condFrequentCold => LocalStorage.prefs.getBool(_keyCondFrequentCold)  ?? false;
  static bool get condSleepIssues  => LocalStorage.prefs.getBool(_keyCondSleepIssues)   ?? false;

  static Future<void> setCondAsthma(bool val)       => LocalStorage.prefs.setBool(_keyCondAsthma, val);
  static Future<void> setCondFrequentCold(bool val) => LocalStorage.prefs.setBool(_keyCondFrequentCold, val);
  static Future<void> setCondSleepIssues(bool val)  => LocalStorage.prefs.setBool(_keyCondSleepIssues, val);

  /// Convenience: returns true if user has no conditions selected
  static bool get condNone => !condAsthma && !condFrequentCold && !condSleepIssues;

  /// Convenience: set all conditions at once from a set of strings
  static Future<void> setConditions({
    required bool asthma,
    required bool frequentCold,
    required bool sleepIssues,
  }) async {
    await setCondAsthma(asthma);
    await setCondFrequentCold(frequentCold);
    await setCondSleepIssues(sleepIssues);
  }

  // ─────────────────────────────────────────────────────────────
  // DAY 10: 7-DAY DAILY SNAPSHOTS (for pattern detection)
  // ─────────────────────────────────────────────────────────────

  /// Save or update today's daily health snapshot.
  static Future<void> saveDailySnapshot(DailySnapshot snapshot) async {
    final raw = LocalStorage.prefs.getString(_keyDailySnapshots) ?? '[]';
    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      list = [];
    }

    // Remove any existing entry for the same date
    list.removeWhere((e) =>
        (e as Map<String, dynamic>)['date_key'] == snapshot.dateKey);

    list.add(snapshot.toJson());

    // Keep only the most recent N snapshots
    if (list.length > _maxSnapshots) {
      list = list.sublist(list.length - _maxSnapshots);
    }

    await LocalStorage.prefs.setString(_keyDailySnapshots, jsonEncode(list));
  }

  /// Get last [days] daily snapshots, sorted oldest→newest.
  static List<DailySnapshot> getDailySnapshots({int days = 7}) {
    final raw = LocalStorage.prefs.getString(_keyDailySnapshots) ?? '[]';
    try {
      final now = DateTime.now();
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => DailySnapshot.fromJson(e as Map<String, dynamic>))
          .where((s) {
            try {
              final parts = s.dateKey.split('-');
              final date = DateTime(
                int.parse(parts[0]),
                int.parse(parts[1]),
                int.parse(parts[2]),
              );
              return now.difference(date).inDays < days;
            } catch (_) {
              return false;
            }
          })
          .toList()
        ..sort((a, b) => a.dateKey.compareTo(b.dateKey));
    } catch (_) {
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────
  // DAY 9: Atomic increment — in-memory + SharedPreferences
  // Called by ContinuousAudioService on EVERY confirmed detection.
  // ─────────────────────────────────────────────────────────────
  static Future<void> incrementEvent(String eventType) async {
    debugPrint('[STORE] Incrementing $eventType...');

    final todayKey   = _dateKey(DateTime.now());
    final storedDate = LocalStorage.prefs.getString(_keyLiveDailyDate) ?? '';
    if (storedDate != todayKey) {
      await LocalStorage.prefs.setString(_keyLiveDailyDate, todayKey);
      await LocalStorage.prefs.setInt(_keyLiveDailyCough,  0);
      await LocalStorage.prefs.setInt(_keyLiveDailySneeze, 0);
      await LocalStorage.prefs.setInt(_keyLiveDailySnore,  0);
      debugPrint('[STORE] New day — daily counts reset');
    }

    switch (eventType) {
      case 'cough':
        final v = (LocalStorage.prefs.getInt(_keyLiveDailyCough) ?? 0) + 1;
        await LocalStorage.prefs.setInt(_keyLiveDailyCough, v);
        debugPrint('[STORE] cough count updated → $v');
        break;
      case 'sneeze':
        final v = (LocalStorage.prefs.getInt(_keyLiveDailySneeze) ?? 0) + 1;
        await LocalStorage.prefs.setInt(_keyLiveDailySneeze, v);
        debugPrint('[STORE] sneeze count updated → $v');
        break;
      case 'snore':
        final v = (LocalStorage.prefs.getInt(_keyLiveDailySnore) ?? 0) + 1;
        await LocalStorage.prefs.setInt(_keyLiveDailySnore, v);
        debugPrint('[STORE] snore count updated → $v');
        break;
    }

    final ts = DateTime.now().toIso8601String();
    await LocalStorage.prefs.setString(_keyLastUpdated, ts);

    liveCountsNotifier.value = _currentLiveCounts();
    debugPrint('[STORE] liveCountsNotifier fired');
  }

  // ── Internal helpers ─────────────────────────────────────────────
  static Map<String, dynamic> _currentLiveCounts() {
    final todayKey   = _dateKey(DateTime.now());
    final storedDate = LocalStorage.prefs.getString(_keyLiveDailyDate) ?? '';
    if (storedDate != todayKey) {
      return {'cough': 0, 'sneeze': 0, 'snore': 0, 'lastUpdated': ''};
    }
    return {
      'cough':       LocalStorage.prefs.getInt(_keyLiveDailyCough)  ?? 0,
      'sneeze':      LocalStorage.prefs.getInt(_keyLiveDailySneeze) ?? 0,
      'snore':       LocalStorage.prefs.getInt(_keyLiveDailySnore)  ?? 0,
      'lastUpdated': LocalStorage.prefs.getString(_keyLastUpdated)  ?? '',
    };
  }

  // ─────────────────────────────────────────────────────────────
  // LIVE EVENTS (Day 8)
  // ─────────────────────────────────────────────────────────────

  static Future<void> saveLiveEvent({
    required String   eventType,
    required DateTime timestamp,
  }) async {
    final raw  = LocalStorage.prefs.getString(_keyLiveEvents) ?? '[]';
    List<dynamic> list;
    try { list = jsonDecode(raw) as List<dynamic>; } catch (_) { list = []; }

    list.add({
      'timestamp':       timestamp.toIso8601String(),
      'event_type':      eventType,
      'count_increment': 1,
    });

    if (list.length > _maxLiveEvents) {
      list = list.sublist(list.length - _maxLiveEvents);
    }
    await LocalStorage.prefs.setString(_keyLiveEvents, jsonEncode(list));

    final todayKey = _dateKey(DateTime.now());
    final storedDate = LocalStorage.prefs.getString(_keyLiveDailyDate) ?? '';
    if (storedDate != todayKey) {
      await LocalStorage.prefs.setString(_keyLiveDailyDate,   todayKey);
      await LocalStorage.prefs.setInt(_keyLiveDailyCough,   0);
      await LocalStorage.prefs.setInt(_keyLiveDailySneeze,  0);
      await LocalStorage.prefs.setInt(_keyLiveDailySnore,   0);
    }

    switch (eventType) {
      case 'cough':
        await LocalStorage.prefs.setInt(
          _keyLiveDailyCough,
          (LocalStorage.prefs.getInt(_keyLiveDailyCough) ?? 0) + 1,
        );
        break;
      case 'sneeze':
        await LocalStorage.prefs.setInt(
          _keyLiveDailySneeze,
          (LocalStorage.prefs.getInt(_keyLiveDailySneeze) ?? 0) + 1,
        );
        break;
      case 'snore':
        await LocalStorage.prefs.setInt(
          _keyLiveDailySnore,
          (LocalStorage.prefs.getInt(_keyLiveDailySnore) ?? 0) + 1,
        );
        break;
    }
  }

  static Map<String, int> getDailyLiveCounts() {
    final storedDate = LocalStorage.prefs.getString(_keyLiveDailyDate) ?? '';
    final todayKey   = _dateKey(DateTime.now());
    if (storedDate != todayKey) {
      return {'cough': 0, 'sneeze': 0, 'snore': 0};
    }
    return {
      'cough':  LocalStorage.prefs.getInt(_keyLiveDailyCough)  ?? 0,
      'sneeze': LocalStorage.prefs.getInt(_keyLiveDailySneeze) ?? 0,
      'snore':  LocalStorage.prefs.getInt(_keyLiveDailySnore)  ?? 0,
    };
  }

  static List<Map<String, dynamic>> getRecentLiveEvents({int limit = 50}) {
    final raw  = LocalStorage.prefs.getString(_keyLiveEvents) ?? '[]';
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .reversed
          .take(limit)
          .map((e) => e as Map<String, dynamic>)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ─────────────────────────────────────
  // PASSIVE MONITORING (Day 8)
  // ─────────────────────────────────────

  static Future<void> savePassiveData(PassiveMonitoringData data) async {
    final raw = LocalStorage.prefs.getString(_keyPassiveLogs) ?? '[]';
    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      list = [];
    }

    list.removeWhere((e) =>
        (e as Map<String, dynamic>)['date_key'] == data.dateKey);

    list.add(data.toJson());

    if (list.length > _maxPassiveDays) {
      list = list.sublist(list.length - _maxPassiveDays);
    }

    await LocalStorage.prefs.setString(_keyPassiveLogs, jsonEncode(list));
  }

  static PassiveMonitoringData? getPassiveDataToday() {
    final todayKey = _dateKey(DateTime.now());
    final list = _getPassiveList();
    for (final entry in list.reversed) {
      final map = entry as Map<String, dynamic>;
      if (map['date_key'] == todayKey) {
        return PassiveMonitoringData.fromJson(map);
      }
    }
    return null;
  }

  static List<PassiveMonitoringData> getPassiveHistory(int days) {
    final now = DateTime.now();
    final list = _getPassiveList();
    return list
        .reversed
        .map((e) => PassiveMonitoringData.fromJson(e as Map<String, dynamic>))
        .where((d) {
          try {
            final parts = d.dateKey.split('-');
            final date = DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            );
            return now.difference(date).inDays < days;
          } catch (_) {
            return false;
          }
        })
        .toList();
  }

  static List<dynamic> _getPassiveList() {
    final raw = LocalStorage.prefs.getString(_keyPassiveLogs) ?? '[]';
    try {
      return jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────
  // DAY 11: DAILY SUMMARY HISTORY
  // ─────────────────────────────────────────────────────────────

  /// Save today's human-readable summary string.
  static Future<void> saveDailySummary(String summary) async {
    final raw = LocalStorage.prefs.getString(_keyDailySummaries) ?? '[]';
    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      list = [];
    }

    final todayKey = _dateKey(DateTime.now());
    // Replace existing entry for today if present
    list.removeWhere((e) =>
        (e as Map<String, dynamic>)['date_key'] == todayKey);
    list.add({'date_key': todayKey, 'summary': summary});

    if (list.length > _maxSummaries) {
      list = list.sublist(list.length - _maxSummaries);
    }
    await LocalStorage.prefs.setString(_keyDailySummaries, jsonEncode(list));
  }

  /// Get last [days] daily summaries, sorted newest first.
  static List<Map<String, String>> getDailySummaries({int days = 7}) {
    final raw = LocalStorage.prefs.getString(_keyDailySummaries) ?? '[]';
    try {
      final now  = DateTime.now();
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Map<String, String>.from(
              (e as Map<String, dynamic>).map(
                (k, v) => MapEntry(k, v.toString()))))
          .where((m) {
            try {
              final parts = m['date_key']!.split('-');
              final date  = DateTime(
                int.parse(parts[0]),
                int.parse(parts[1]),
                int.parse(parts[2]),
              );
              return now.difference(date).inDays < days;
            } catch (_) {
              return false;
            }
          })
          .toList()
          .reversed
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
}
