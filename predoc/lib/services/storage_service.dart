import 'dart:convert';
import '../utils/local_storage.dart';
import '../services/audio_service.dart';

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

  // ─────────────────────────────────────────
  // FLAT-KEY GETTERS (legacy, unchanged)
  // ─────────────────────────────────────────
  static int    get coughCount     => LocalStorage.prefs.getInt(_keyCoughCount)       ?? 0;
  static int    get sneezeCount    => LocalStorage.prefs.getInt(_keySneeze)           ?? 0;
  static int    get snoreCount     => LocalStorage.prefs.getInt(_keySnore)            ?? 0;
  static String get eyeColor       => LocalStorage.prefs.getString(_keyEyeColor)      ?? '';
  static double get brightnessLevel => LocalStorage.prefs.getDouble(_keyBrightness)   ?? 0.0;
  static bool   get faceDetected   => LocalStorage.prefs.getBool(_keyFaceDetected)    ?? false;
  static bool   get deviceTestDone => LocalStorage.prefs.getBool(_keyDeviceTestDone)  ?? false;
  static String get faceEmbedding  => LocalStorage.prefs.getString(_keyFaceEmbedding) ?? '';
}
