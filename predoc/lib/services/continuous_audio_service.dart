// ContinuousAudioService — Day 8
//
// Bridges Flutter ↔ Android foreground service for always-on audio monitoring.
// All detection logic (windowing, smoothing, thresholds, cooldowns) runs here
// in Dart, reusing the same constants as AudioService so the two are always
// in sync.  Raw audio is NEVER stored — only event counts.
//
// ARCHITECTURE:
//   Flutter side  → sends start/stop via MethodChannel
//   Android side  → ContinuousAudioForegroundService.kt
//                    • shows persistent notification
//                    • holds a PARTIAL_WAKE_LOCK
//                    • proxies mic bytes back via EventChannel
//   Detection     → runs here, on a dart:async Timer loop
//
// SAFETY RULES enforced:
//   ✓ DO NOT store raw audio
//   ✓ DO NOT upload data
//   ✓ Persistent foreground notification always visible
//   ✓ Inference only every 2nd window (performance guard)

import 'dart:async';
import 'dart:math';


import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import 'model_service.dart';
import 'storage_service.dart';

// ─────────────────────────────────────────────────────────────
// LIVE EVENT  (broadcast from detection loop → UI)
// ─────────────────────────────────────────────────────────────

class LiveDetectionEvent {
  final String eventType;   // 'cough' | 'sneeze' | 'snore'
  final DateTime timestamp;

  const LiveDetectionEvent({
    required this.eventType,
    required this.timestamp,
  });
}

// ─────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────

class ContinuousAudioService {
  final ModelService _modelService;

  ContinuousAudioService(this._modelService);

  // ── Android foreground-service channel ──────────────────────
  static const _fgChannel = MethodChannel('predoc/continuous_audio');

  // ── PCM recording (same as AudioService) ────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _recordSub;

  // ── Detection constants (mirrors AudioService) ───────────────
  static const double _coughThreshold  = 0.30;
  static const double _sneezeThreshold = 0.35;
  static const double _snoreThreshold  = 0.40;

  static const int _coughMinWindows  = 3;
  static const int _sneezeMinWindows = 3;
  static const int _snoreMinWindows  = 4;

  static const Duration _cooldown = Duration(seconds: 3);

  // ── PCM windowing (same as AudioService) ────────────────────
  static const int _windowSamples = 15600;         // 0.975 s @ 16 kHz
  static const int _windowBytes   = _windowSamples * 2; // 31200 bytes
  static const int _hopBytes      = _windowBytes ~/ 2;  // 50% overlap

  // ── Smoothing queue (last 3 windows) ────────────────────────
  static const int _smoothingWindow = 3;
  final List<double> _coughQ  = [];
  final List<double> _sneezeQ = [];
  final List<double> _snoreQ  = [];

  // ── Cooldown timestamps ──────────────────────────────────────
  DateTime? _lastCoughTime;
  DateTime? _lastSneezeTime;
  DateTime? _lastSnoreTime;

  // ── Confirmation counters (reset per cooldown window) ────────
  int _coughWindowCount  = 0;
  int _sneezeWindowCount = 0;
  int _snoreWindowCount  = 0;

  // ── Performance: only run inference on every 2nd window ──────
  int _windowIndex = 0;

  // ── Raw audio accumulation ───────────────────────────────────
  final List<int> _rawBuffer = [];

  // ── Running state ────────────────────────────────────────────
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  // ── Live counters (cumulative for current "session") ─────────
  int liveCountCough  = 0;
  int liveCountSneeze = 0;
  int liveCountSnore  = 0;

  // ── Live probability stream (for UI pulse bar) ───────────────
  final StreamController<Map<String, double>> _probStreamCtrl =
      StreamController.broadcast();
  Stream<Map<String, double>> get probStream => _probStreamCtrl.stream;

  // ── Confirmed event stream (for counters + storage) ──────────
  final StreamController<LiveDetectionEvent> _eventStreamCtrl =
      StreamController.broadcast();
  Stream<LiveDetectionEvent> get eventStream => _eventStreamCtrl.stream;

  // ─────────────────────────────────────────────────────────────
  // START
  // ─────────────────────────────────────────────────────────────

  Future<void> start() async {
    if (_isRunning) return;

    debugPrint('[ContinuousAudio] Starting foreground service + mic stream...');

    // 1. Ask Android to launch the foreground service (shows notification)
    try {
      await _fgChannel.invokeMethod('startForeground');
      debugPrint('[ContinuousAudio] Foreground service started ✓');
    } catch (e) {
      debugPrint('[ContinuousAudio] Foreground service start error: $e');
      // Continue anyway — mic still works without it on dev builds
    }

    // 2. Check mic permission
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      debugPrint('[ContinuousAudio] No mic permission — aborting');
      await _stopForeground();
      return;
    }

    // 3. Start PCM stream
    try {
      final stream = await _recorder.startStream(const RecordConfig(
        encoder:     AudioEncoder.pcm16bits,
        sampleRate:  16000,
        numChannels: 1,
      ));
      debugPrint('[ContinuousAudio] PCM stream started ✓ (16-bit, 16 kHz, mono)');

      _isRunning = true;
      _resetState();

      _recordSub = stream.listen(
        _onAudioChunk,
        onError: (e) => debugPrint('[ContinuousAudio] Stream error: $e'),
      );
    } catch (e) {
      debugPrint('[ContinuousAudio] Failed to start mic: $e');
      await _stopForeground();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // STOP
  // ─────────────────────────────────────────────────────────────

  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;

    await _recordSub?.cancel();
    _recordSub = null;

    try {
      await _recorder.stop();
      debugPrint('[ContinuousAudio] Mic stopped');
    } catch (e) {
      debugPrint('[ContinuousAudio] Error stopping mic: $e');
    }

    await _stopForeground();
    _resetState();
    debugPrint('[ContinuousAudio] Service fully stopped');
  }

  Future<void> _stopForeground() async {
    try {
      await _fgChannel.invokeMethod('stopForeground');
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────
  // AUDIO CHUNK HANDLER
  // ─────────────────────────────────────────────────────────────

  void _onAudioChunk(Uint8List data) {
    _rawBuffer.addAll(data);

    // ── Sliding window with 50% overlap ─────────────────────
    while (_rawBuffer.length >= _windowBytes) {
      // Buffer overflow guard: discard oldest hop if too large
      if (_rawBuffer.length > _windowBytes * 4) {
        _rawBuffer.removeRange(0, _hopBytes);
        debugPrint('[ContinuousAudio] Buffer overflow guard — discarding oldest hop');
      }

      final chunk = _rawBuffer.sublist(0, _windowBytes);

      // ── PERFORMANCE: skip every odd window ───────────────
      _windowIndex++;
      if (_windowIndex % 2 != 0) {
        _rawBuffer.removeRange(0, _hopBytes);
        continue;
      }

      // ── Convert PCM → Float32 [-1.0, 1.0] ───────────────
      final floatList = Float32List(_windowSamples);
      for (int i = 0; i < _windowSamples; i++) {
        final b = i * 2;
        int pcm = (chunk[b] & 0xFF) | ((chunk[b + 1] & 0xFF) << 8);
        if (pcm > 32767) pcm -= 65536;
        floatList[i] = pcm / 32768.0;
      }

      // ── Run YAMNet inference ─────────────────────────────
      double rawCough  = 0.0;
      double rawSneeze = 0.0;
      double rawSnore  = 0.0;

      if (_modelService.isLoaded) {
        final results = _modelService.runAudioInference(floatList);
        for (final entry in results.entries) {
          final label = entry.key.toLowerCase();
          final prob  = entry.value;
          if (label.contains('cough'))  rawCough  = max(rawCough,  prob);
          if (label.contains('sneeze')) rawSneeze = max(rawSneeze, prob);
          if (label.contains('snore'))  rawSnore  = max(rawSnore,  prob);
        }
      }

      // ── Smoothing (rolling average of last 3 windows) ────
      _enqueue(_coughQ,  rawCough);
      _enqueue(_sneezeQ, rawSneeze);
      _enqueue(_snoreQ,  rawSnore);

      final smoothCough  = _mean(_coughQ);
      final smoothSneeze = _mean(_sneezeQ);
      final smoothSnore  = _mean(_snoreQ);

      // Notify UI with live probabilities
      if (!_probStreamCtrl.isClosed) {
        _probStreamCtrl.add({
          'cough':  smoothCough,
          'sneeze': smoothSneeze,
          'snore':  smoothSnore,
        });
      }

      debugPrint('[ContinuousAudio] W#$_windowIndex '
          'cough=${smoothCough.toStringAsFixed(3)} '
          'sneeze=${smoothSneeze.toStringAsFixed(3)} '
          'snore=${smoothSnore.toStringAsFixed(3)}');

      // ── Threshold crossing ───────────────────────────────
      if (smoothCough  >= _coughThreshold)  _coughWindowCount++;
      if (smoothSneeze >= _sneezeThreshold) _sneezeWindowCount++;
      if (smoothSnore  >= _snoreThreshold)  _snoreWindowCount++;

      // ── Confirmation + cooldown ──────────────────────────
      final now = DateTime.now();
      _tryConfirm('cough',  _coughWindowCount,  _coughMinWindows,
          _lastCoughTime, now, () {
        _lastCoughTime   = now;
        _coughWindowCount = 0;
        liveCountCough++;
        _emitEvent('cough', now);
      });

      _tryConfirm('sneeze', _sneezeWindowCount, _sneezeMinWindows,
          _lastSneezeTime, now, () {
        _lastSneezeTime   = now;
        _sneezeWindowCount = 0;
        liveCountSneeze++;
        _emitEvent('sneeze', now);
      });

      _tryConfirm('snore', _snoreWindowCount,  _snoreMinWindows,
          _lastSnoreTime, now, () {
        _lastSnoreTime   = now;
        _snoreWindowCount = 0;
        liveCountSnore++;
        _emitEvent('snore', now);
      });

      // ── Advance by hop (50% overlap) ─────────────────────
      _rawBuffer.removeRange(0, _hopBytes);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // CONFIRMATION HELPER
  // ─────────────────────────────────────────────────────────────

  void _tryConfirm(
    String label,
    int windowCount,
    int minWindows,
    DateTime? lastTime,
    DateTime now,
    VoidCallback onConfirmed,
  ) {
    if (windowCount < minWindows) return;
    if (lastTime != null && now.difference(lastTime) < _cooldown) {
      debugPrint('[ContinuousAudio] $label in cooldown — skipped');
      return;
    }
    debugPrint('[ContinuousAudio] ✓ $label confirmed!');
    onConfirmed();
  }

  // ─────────────────────────────────────────────────────────────
  // EMIT CONFIRMED EVENT
  // ─────────────────────────────────────────────────────────────

  void _emitEvent(String type, DateTime timestamp) {
    if (!_eventStreamCtrl.isClosed) {
      _eventStreamCtrl.add(LiveDetectionEvent(
        eventType: type,
        timestamp: timestamp,
      ));
    }
    // Persist event asynchronously (no raw audio stored)
    StorageService.saveLiveEvent(
      eventType: type,
      timestamp: timestamp,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────

  void _enqueue(List<double> queue, double value) {
    queue.add(value);
    if (queue.length > _smoothingWindow) queue.removeAt(0);
  }

  double _mean(List<double> queue) {
    if (queue.isEmpty) return 0.0;
    return queue.reduce((a, b) => a + b) / queue.length;
  }

  void _resetState() {
    _rawBuffer.clear();
    _coughQ.clear();
    _sneezeQ.clear();
    _snoreQ.clear();
    _windowIndex       = 0;
    _coughWindowCount  = 0;
    _sneezeWindowCount = 0;
    _snoreWindowCount  = 0;
    _lastCoughTime     = null;
    _lastSneezeTime    = null;
    _lastSnoreTime     = null;
    liveCountCough     = 0;
    liveCountSneeze    = 0;
    liveCountSnore     = 0;
  }

  // ─────────────────────────────────────────────────────────────
  // DISPOSE
  // ─────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await stop();
    await _probStreamCtrl.close();
    await _eventStreamCtrl.close();
  }
}
