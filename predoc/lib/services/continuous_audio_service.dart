// ContinuousAudioService — Day 9
//
// STRICT DATA PIPELINE:
//   AudioChunk → YAMNet → Smoothing → Threshold check → Cooldown → Confirmed
//   → StorageService.incrementEvent()  [IMMEDIATE — in-memory + prefs]
//   → StorageService.liveCountsNotifier fires
//   → UI ValueListenableBuilder rebuilds
//
// SAFETY RULES ENFORCED:
//   ✓ DO NOT store raw audio
//   ✓ DO NOT upload data
//   ✓ Confidence check before any increment (Part 6)
//   ✓ 3-second cooldown between same-type events (Part 6)
//   ✓ Persistent foreground notification
//   ✓ Health-condition thresholds respected (Part 5)

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import 'model_service.dart';
import 'storage_service.dart';
import 'user_context_service.dart';

// ─────────────────────────────────────────────────────────────
// LIVE EVENT  (broadcast from detection loop → UI)
// ─────────────────────────────────────────────────────────────

class LiveDetectionEvent {
  final String eventType;   // 'cough' | 'sneeze' | 'snore'
  final DateTime timestamp;
  final double confidence;

  const LiveDetectionEvent({
    required this.eventType,
    required this.timestamp,
    required this.confidence,
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

  // ── PCM recording ────────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _recordSub;

  // ── Detection thresholds (loaded from UserContextService) ────
  double _coughThreshold  = 0.30;
  double _sneezeThreshold = 0.35;
  double _snoreThreshold  = 0.40;

  // ── Confirmation window counts ───────────────────────────────
  static const int _coughMinWindows  = 2;
  static const int _sneezeMinWindows = 2;
  static const int _snoreMinWindows  = 3;

  // ── Cooldown between confirmed events (Part 6) ───────────────
  static const Duration _cooldown = Duration(seconds: 3);

  // ── PCM windowing ────────────────────────────────────────────
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

  // ── Confirmation counters ────────────────────────────────────
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

  // ── Live probability stream (for pulse bar UI) ───────────────
  final StreamController<Map<String, double>> _probStreamCtrl =
      StreamController.broadcast();
  Stream<Map<String, double>> get probStream => _probStreamCtrl.stream;

  // ── Confirmed event stream ────────────────────────────────────
  final StreamController<LiveDetectionEvent> _eventStreamCtrl =
      StreamController.broadcast();
  Stream<LiveDetectionEvent> get eventStream => _eventStreamCtrl.stream;

  // ─────────────────────────────────────────────────────────────
  // START
  // ─────────────────────────────────────────────────────────────

  Future<void> start() async {
    if (_isRunning) return;

    debugPrint('[ContinuousAudio] Starting foreground service + mic stream...');

    // Load health-condition thresholds (Part 5)
    _reloadThresholds();

    // 1. Ask Android to launch the foreground service
    try {
      await _fgChannel.invokeMethod('startForeground');
      debugPrint('[ContinuousAudio] Foreground service started ✓');
    } catch (e) {
      debugPrint('[ContinuousAudio] Foreground service start error: $e');
      // Continue — mic still works without it in dev builds
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
      debugPrint('[ContinuousAudio] Thresholds — '
          'cough=${_coughThreshold.toStringAsFixed(2)} '
          'sneeze=${_sneezeThreshold.toStringAsFixed(2)} '
          'snore=${_snoreThreshold.toStringAsFixed(2)}');

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
  // RELOAD THRESHOLDS (call when health condition changes)
  // ─────────────────────────────────────────────────────────────

  void _reloadThresholds() {
    final profile = UserContextService.getThresholds();
    _coughThreshold  = profile.coughThreshold;
    _sneezeThreshold = profile.sneezeThreshold;
    _snoreThreshold  = profile.snoreThreshold;
    debugPrint('[ContinuousAudio] Thresholds reloaded from UserContextService: '
        'cough=$_coughThreshold sneeze=$_sneezeThreshold snore=$_snoreThreshold');
  }

  /// Call this from the UI when the user changes their health condition.
  void refreshThresholds() {
    _reloadThresholds();
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
      // Buffer overflow guard
      if (_rawBuffer.length > _windowBytes * 4) {
        _rawBuffer.removeRange(0, _hopBytes);
        debugPrint('[AUDIO] Buffer overflow guard — discarding oldest hop');
      }

      final chunk = _rawBuffer.sublist(0, _windowBytes);

      _windowIndex++;

      debugPrint('[AUDIO] Window #$_windowIndex processed (${chunk.length} bytes)');

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
        debugPrint('[MODEL] cough prob: ${rawCough.toStringAsFixed(3)} '
            'sneeze prob: ${rawSneeze.toStringAsFixed(3)} '
            'snore prob: ${rawSnore.toStringAsFixed(3)}');
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

      // ── Threshold crossing ───────────────────────────────
      final coughCross  = smoothCough  >= _coughThreshold;
      final sneezeCross = smoothSneeze >= _sneezeThreshold;
      final snoreCross  = smoothSnore  >= _snoreThreshold;

      if (coughCross) {
        _coughWindowCount++;
      } else {
        _coughWindowCount = 0;
      }
      
      if (sneezeCross) {
        _sneezeWindowCount++;
      } else {
        _sneezeWindowCount = 0;
      }
      
      if (snoreCross) {
        _snoreWindowCount++;
      } else {
        _snoreWindowCount = 0;
      }

      // ── Confirmation + cooldown ──────────────────────────
      final now = DateTime.now();

      // COUGH
      _tryConfirm(
        label:       'cough',
        windowCount: _coughWindowCount,
        minWindows:  _coughMinWindows,
        confidence:  smoothCough,
        lastTime:    _lastCoughTime,
        now:         now,
        onConfirmed: () {
          _lastCoughTime   = now;
          _coughWindowCount = 0;
          _emitAndStore('cough', now, smoothCough);
        },
      );

      // SNEEZE
      _tryConfirm(
        label:       'sneeze',
        windowCount: _sneezeWindowCount,
        minWindows:  _sneezeMinWindows,
        confidence:  smoothSneeze,
        lastTime:    _lastSneezeTime,
        now:         now,
        onConfirmed: () {
          _lastSneezeTime   = now;
          _sneezeWindowCount = 0;
          _emitAndStore('sneeze', now, smoothSneeze);
        },
      );

      // SNORE
      _tryConfirm(
        label:       'snore',
        windowCount: _snoreWindowCount,
        minWindows:  _snoreMinWindows,
        confidence:  smoothSnore,
        lastTime:    _lastSnoreTime,
        now:         now,
        onConfirmed: () {
          _lastSnoreTime   = now;
          _snoreWindowCount = 0;
          _emitAndStore('snore', now, smoothSnore);
        },
      );

      // ── Advance by hop (50% overlap) ─────────────────────
      _rawBuffer.removeRange(0, _hopBytes);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // CONFIRMATION HELPER  (Part 6 — validation rules)
  // ─────────────────────────────────────────────────────────────

  void _tryConfirm({
    required String    label,
    required int       windowCount,
    required int       minWindows,
    required double    confidence,
    required DateTime? lastTime,
    required DateTime  now,
    required VoidCallback onConfirmed,
  }) {
    if (windowCount < minWindows) return;

    // Part 6 rule 2: ignore if cooldown < 3 sec
    if (lastTime != null && now.difference(lastTime) < _cooldown) {
      debugPrint('[ContinuousAudio] $label in cooldown — skipped');
      return;
    }

    // Part 6 rule 1: ignore if confidence below threshold (already guaranteed
    // by windowCount gate, but explicit check here for clarity / safety)
    if (confidence < 0.10) {
      debugPrint('[ContinuousAudio] $label confidence too low ($confidence) — ignored');
      return;
    }

    debugPrint('[DETECT] $label detected! confidence=${confidence.toStringAsFixed(3)}');
    onConfirmed();
  }

  // ─────────────────────────────────────────────────────────────
  // EMIT + STORE  (the STRICT pipeline)
  // ─────────────────────────────────────────────────────────────
  //
  //  1. Emit to eventStream  → UI stream listeners (prob bar, etc.)
  //  2. StorageService.incrementEvent()  → atomic in-memory + prefs
  //  3. StorageService.saveLiveEvent()   → rolling JSON event log
  //
  //  This replaces the old single saveLiveEvent() call which did NOT
  //  update the ValueNotifier and could be missed if stream was unsubbed.
  // ─────────────────────────────────────────────────────────────

  void _emitAndStore(String type, DateTime timestamp, double confidence) {
    // 1. Broadcast to stream (UI pulse bar, etc.)
    if (!_eventStreamCtrl.isClosed) {
      _eventStreamCtrl.add(LiveDetectionEvent(
        eventType:  type,
        timestamp:  timestamp,
        confidence: confidence,
      ));
    }

    // 2. Atomic increment (fires ValueNotifier — primary UI path)
    StorageService.incrementEvent(type).catchError(
      (e) => debugPrint('[ContinuousAudio] incrementEvent error: $e'),
    );

    // 3. Append to rolling JSON event log (for history view)
    StorageService.saveLiveEvent(
      eventType: type,
      timestamp: timestamp,
    ).catchError(
      (e) => debugPrint('[ContinuousAudio] saveLiveEvent error: $e'),
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
