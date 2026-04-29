import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../utils/local_storage.dart';
import '../services/audio_service.dart';
import '../services/passive_monitoring_service.dart';


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
  // UI widgets listen to this and rebuild instantly on every detection.
  static final ValueNotifier<Map<String, dynamic>> liveCountsNotifier =
      ValueNotifier<Map<String, dynamic>>({'cough': 0, 'sneeze': 0, 'snore': 0, 'lastUpdated': ''});

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
  /// Keeps a rolling window of [_maxSessions] most recent sessions.
  static Future<void> saveSession(SessionResult session) async {
    final raw = LocalStorage.prefs.getString(_keySessionLogs) ?? '[]';
    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      list = [];
    }

    list.add(session.toJson());

    // Keep only the most recent N sessions
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

  /// Get current calibration offset for each class.
  /// Default is 0.0 (no adjustment from base threshold).
  static double get coughOffset  => LocalStorage.prefs.getDouble(_keyCalibCough)   ?? 0.0;
  static double get sneezeOffset => LocalStorage.prefs.getDouble(_keyCalibSneeze)  ?? 0.0;
  static double get snoreOffset  => LocalStorage.prefs.getDouble(_keyCalibSnore)   ?? 0.0;

  /// Increase threshold by one step (reduces false positives).
  static Future<void> raiseCoughThreshold()  async =>
      await LocalStorage.prefs.setDouble(_keyCalibCough,  (coughOffset + 0.03).clamp(-0.15, 0.15));
  static Future<void> raiseSneezeThreshold() async =>
      await LocalStorage.prefs.setDouble(_keyCalibSneeze, (sneezeOffset + 0.03).clamp(-0.15, 0.15));
  static Future<void> raiseSnoreThreshold()  async =>
      await LocalStorage.prefs.setDouble(_keyCalibSnore,  (snoreOffset + 0.03).clamp(-0.15, 0.15));

  /// Decrease threshold by one step (reduces missed events).
  static Future<void> lowerCoughThreshold()  async =>
      await LocalStorage.prefs.setDouble(_keyCalibCough,  (coughOffset - 0.03).clamp(-0.15, 0.15));
  static Future<void> lowerSneezeThreshold() async =>
      await LocalStorage.prefs.setDouble(_keyCalibSneeze, (sneezeOffset - 0.03).clamp(-0.15, 0.15));
  static Future<void> lowerSnoreThreshold()  async =>
      await LocalStorage.prefs.setDouble(_keyCalibSnore,  (snoreOffset - 0.03).clamp(-0.15, 0.15));

  /// Reset all calibration offsets to zero.
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

  // Step count (updated externally — e.g., from a future step counter)
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

  // ── Day 9: Atomic increment — in-memory + SharedPreferences ─────
  // Called by ContinuousAudioService on EVERY confirmed detection.
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
  // Stores only: { timestamp, event_type, count_increment }
  // Raw audio is NEVER stored.
  // ─────────────────────────────────────────────────────────────

  /// Append a single confirmed live detection event and update daily totals.
  static Future<void> saveLiveEvent({
    required String   eventType,    // 'cough' | 'sneeze' | 'snore'
    required DateTime timestamp,
  }) async {
    // 1. Append to rolling event log
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

    // 2. Update / reset daily totals
    final todayKey = _dateKey(DateTime.now());
    final storedDate = LocalStorage.prefs.getString(_keyLiveDailyDate) ?? '';
    if (storedDate != todayKey) {
      // New day — reset counts
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

  /// Get today's cumulative live detection counts.
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

  /// Get recent live events (most recent first).
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

  /// Save today's passive monitoring snapshot.
  /// Keeps a rolling log of [_maxPassiveDays] days.
  static Future<void> savePassiveData(PassiveMonitoringData data) async {
    final raw = LocalStorage.prefs.getString(_keyPassiveLogs) ?? '[]';
    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      list = [];
    }

    // Remove any existing entry for the same date
    list.removeWhere((e) =>
        (e as Map<String, dynamic>)['date_key'] == data.dateKey);

    list.add(data.toJson());

    // Keep only the most recent N days
    if (list.length > _maxPassiveDays) {
      list = list.sublist(list.length - _maxPassiveDays);
    }

    await LocalStorage.prefs.setString(_keyPassiveLogs, jsonEncode(list));
  }

  /// Get today's passive monitoring data (or null if not yet recorded).
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

  /// Get passive monitoring history for last [days] days (most recent first).
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

  static String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
}
