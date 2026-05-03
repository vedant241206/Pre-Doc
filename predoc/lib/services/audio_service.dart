import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'model_service.dart';

// ─────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────

/// Log entry for a single 0.96-second YAMNet inference window.
class AudioWindowLog {
  final DateTime timestamp;
  final int windowIndex;
  final double coughProb;
  final double sneezeProb;
  final double snoreProb;
  final String detectedClass;
  final bool passedThreshold;

  const AudioWindowLog({
    required this.timestamp,
    required this.windowIndex,
    required this.coughProb,
    required this.sneezeProb,
    required this.snoreProb,
    required this.detectedClass,
    required this.passedThreshold,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'window_index': windowIndex,
        'cough_prob': coughProb,
        'sneeze_prob': sneezeProb,
        'snore_prob': snoreProb,
        'detected_class': detectedClass,
        'passed_threshold': passedThreshold,
      };
}

/// Final result returned after a full 10-second detection session.
class AudioDetectionResult {
  final int coughCount;
  final int sneezeCount;
  final int snoreCount;
  final List<double> waveformSamples;
  final String dominantLabel;

  // ── Day 5 additions ──
  /// Per-window structured logs for calibration / raw log view.
  final List<AudioWindowLog> windowLogs;

  /// Smoothed probabilities from the very last window (for live UI).
  final double lastCoughProb;
  final double lastSneezeProb;
  final double lastSnoreProb;

  const AudioDetectionResult({
    required this.coughCount,
    required this.sneezeCount,
    required this.snoreCount,
    required this.waveformSamples,
    required this.dominantLabel,
    this.windowLogs = const [],
    this.lastCoughProb = 0.0,
    this.lastSneezeProb = 0.0,
    this.lastSnoreProb = 0.0,
  });
}

// ─────────────────────────────────────────────────────────────
// AUDIO SERVICE
// ─────────────────────────────────────────────────────────────

class AudioService {
  final ModelService _modelService;
  final AudioRecorder _recorder = AudioRecorder();

  // ── Detection thresholds (Day 5 spec) ──
  static const double _coughThreshold  = 0.30;
  static const double _sneezeThreshold = 0.35;
  static const double _snoreThreshold  = 0.40;

  // ── PCM constants ──
  // YAMNet window = 15600 float32 samples = 31200 raw bytes  (~0.975 s @ 16 kHz)
  // 50% overlap  → advance by 7800 samples = 15600 raw bytes each step
  static const int _windowSamples  = 15600;
  static const int _windowBytes    = _windowSamples * 2; // 31200
  static const int _hopBytes       = _windowBytes ~/ 2;  // 15600

  // ── Smoothing: rolling queue of last 3 window probs ──
  static const int _smoothingWindow = 3;
  final List<double> _coughProbQueue  = [];
  final List<double> _sneezeProbQueue = [];
  final List<double> _snoreProbQueue  = [];

  // ── Per-session cooldown timestamps ──
  DateTime? _lastCoughTime;
  DateTime? _lastSneezeTime;
  DateTime? _lastSnoreTime;

  // ── Persistent cumulative counts (across sessions) ──
  int coughCount  = 0;
  int sneezeCount = 0;
  int snoreCount  = 0;

  // ── Live-UI callbacks ──
  /// Called every audio chunk with a [0.0 – 1.0] amplitude for waveform bar UI.
  Function(double amplitude)? onAmplitudeUpdate;

  /// Called after every smoothed window inference with raw smoothed probs.
  Function(double coughProb, double sneezeProb, double snoreProb)? onWindowProbs;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  StreamSubscription<Uint8List>? _recordSub;

  AudioService(this._modelService);

  // ─────────────────────────────────────────────
  // MAIN DETECTION RUN  (10-second session)
  // ─────────────────────────────────────────────
  Future<AudioDetectionResult> runDetection({
    void Function(int secondsLeft)? onProgress,
    double coughOffset = 0.0,
    double sneezeOffset = 0.0,
    double snoreOffset = 0.0,
  }) async {
    _isRecording = true;

    // ── Reset smoothing queues for fresh session ──
    _coughProbQueue.clear();
    _sneezeProbQueue.clear();
    _snoreProbQueue.clear();

    final List<double>  waveformSamples = [];
    final List<AudioWindowLog> windowLogs = [];

    // Per-session window crossing counters (distinct from cumulative counts)
    int sessionCoughWindows  = 0;
    int sessionSneezeWindows = 0;
    int sessionSnoreWindows  = 0;
    int windowIndex          = 0;

    double lastCoughProb  = 0.0;
    double lastSneezeProb = 0.0;
    double lastSnoreProb  = 0.0;

    // ── Check microphone permission ──
    final hasPerm = await _recorder.hasPermission();
    debugPrint('[AudioService] Has mic permission: $hasPerm');

    if (hasPerm) {
      try {
        // Stream raw PCM 16-bit, 16 kHz, mono
        final stream = await _recorder.startStream(const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ));
        debugPrint('[AudioService] Recording started ✓ (PCM 16-bit, 16 kHz, mono)');

        final List<int> rawAudioBuffer = [];

        _recordSub = stream.listen(
          (Uint8List data) {
            debugPrint('[AudioService] Audio chunk: ${data.length} bytes');
            rawAudioBuffer.addAll(data);

            // ── Amplitude for waveform UI ──
            if (data.length >= 2) {
              int sum = 0;
              for (int i = 0; i + 1 < data.length; i += 2) {
                int sample = (data[i] & 0xFF) | ((data[i + 1] & 0xFF) << 8);
                if (sample > 32767) sample -= 65536;
                sum += sample.abs();
              }
              final numSamples = data.length ~/ 2;
              final avg = sum / numSamples;
              final amp = (avg / 32768.0).clamp(0.05, 1.0);
              waveformSamples.add(amp);
              onAmplitudeUpdate?.call(amp);
            }

            // ─────────────────────────────────────────────
            // SLIDING WINDOW WITH 50% OVERLAP
            // Process every time buffer has ≥ 1 full window.
            // Advance by hop (half window) each step.
            // ─────────────────────────────────────────────
            while (rawAudioBuffer.length >= _windowBytes) {
              // Safety cap: if buffer grows too large, discard oldest hop
              if (rawAudioBuffer.length > _windowBytes * 3) {
                rawAudioBuffer.removeRange(0, _hopBytes);
                debugPrint('[AudioService] Buffer overflow guard — discarded oldest hop');
              }

              // Extract one full window (31200 bytes = 15600 samples)
              final chunk = rawAudioBuffer.sublist(0, _windowBytes);

              // Convert 16-bit PCM → Float32 [-1.0, 1.0] (normalised)
              final floatList = Float32List(_windowSamples);
              for (int i = 0; i < _windowSamples; i++) {
                final byteIndex = i * 2;
                int pcm16 = (chunk[byteIndex] & 0xFF) |
                    ((chunk[byteIndex + 1] & 0xFF) << 8);
                if (pcm16 > 32767) pcm16 -= 65536;
                floatList[i] = pcm16 / 32768.0;
              }

              // ── Run YAMNet inference ──
              double rawCough  = 0.0;
              double rawSneeze = 0.0;
              double rawSnore  = 0.0;
              String topClass  = 'Unknown';

              if (_modelService.isLoaded) {
                debugPrint('[AudioService] Window $windowIndex — running inference...');
                final results = _modelService.runAudioInference(floatList);

                // Extract cough / sneeze / snore probs + top class
                double topProb = 0.0;
                for (final entry in results.entries) {
                  final label = entry.key.toLowerCase();
                  final prob  = entry.value;

                  if (label.contains('cough'))  rawCough  = max(rawCough,  prob);
                  if (label.contains('sneeze')) rawSneeze = max(rawSneeze, prob);
                  if (label.contains('snore'))  rawSnore  = max(rawSnore,  prob);

                  if (prob > topProb) {
                    topProb  = prob;
                    topClass = entry.key;
                  }
                }
              } else {
                debugPrint('[AudioService] Window $windowIndex — model not loaded, skipping');
              }

              // ─────────────────────────────────────────────
              // MOVING-AVERAGE SMOOTHING (last 3 windows)
              // ─────────────────────────────────────────────
              _enqueue(_coughProbQueue,  rawCough);
              _enqueue(_sneezeProbQueue, rawSneeze);
              _enqueue(_snoreProbQueue,  rawSnore);

              final smoothCough  = _mean(_coughProbQueue);
              final smoothSneeze = _mean(_sneezeProbQueue);
              final smoothSnore  = _mean(_snoreProbQueue);

              lastCoughProb  = smoothCough;
              lastSneezeProb = smoothSneeze;
              lastSnoreProb  = smoothSnore;

              // Notify UI with live probs
              onWindowProbs?.call(smoothCough, smoothSneeze, smoothSnore);

              // ── Threshold crossing check (using smoothed values) ──
              final effectiveCoughThreshold  = (_coughThreshold  + coughOffset).clamp(0.05, 0.95);
              final effectiveSneezeThreshold = (_sneezeThreshold + sneezeOffset).clamp(0.05, 0.95);
              final effectiveSnoreThreshold  = (_snoreThreshold  + snoreOffset).clamp(0.05, 0.95);

              final coughCross  = smoothCough  >= effectiveCoughThreshold;
              final sneezeCross = smoothSneeze >= effectiveSneezeThreshold;
              final snoreCross  = smoothSnore  >= effectiveSnoreThreshold;
              final anyPass     = coughCross || sneezeCross || snoreCross;

              // Determine detected class label for the log
              String detectedClass = topClass;
              if (coughCross) {
                detectedClass = 'Cough';
              } else if (sneezeCross) {
                detectedClass = 'Sneeze';
              } else if (snoreCross) {
                detectedClass = 'Snore';
              }

              debugPrint('[AudioService] Window $windowIndex | '
                  'cough=${smoothCough.toStringAsFixed(3)} '
                  'sneeze=${smoothSneeze.toStringAsFixed(3)} '
                  'snore=${smoothSnore.toStringAsFixed(3)} '
                  'top="$topClass" pass=$anyPass');

              // ── Store window log ──
              windowLogs.add(AudioWindowLog(
                timestamp:       DateTime.now(),
                windowIndex:     windowIndex,
                coughProb:       smoothCough,
                sneezeProb:      smoothSneeze,
                snoreProb:       smoothSnore,
                detectedClass:   detectedClass,
                passedThreshold: anyPass,
              ));

              // ── Count crossings per session (Dynamic Live Counting) ──
              final now = DateTime.now();
              if (coughCross) {
                sessionCoughWindows++;
                if (sessionCoughWindows >= 2) {
                  if (_lastCoughTime == null || now.difference(_lastCoughTime!) > const Duration(seconds: 2)) {
                    coughCount++;
                    _lastCoughTime = now;
                    sessionCoughWindows = 0; // reset to require a break
                  }
                }
              } else {
                sessionCoughWindows = 0;
              }

              if (sneezeCross) {
                sessionSneezeWindows++;
                if (sessionSneezeWindows >= 2) {
                  if (_lastSneezeTime == null || now.difference(_lastSneezeTime!) > const Duration(seconds: 2)) {
                    sneezeCount++;
                    _lastSneezeTime = now;
                    sessionSneezeWindows = 0;
                  }
                }
              } else {
                sessionSneezeWindows = 0;
              }

              if (snoreCross) {
                sessionSnoreWindows++;
                if (sessionSnoreWindows >= 3) {
                  if (_lastSnoreTime == null || now.difference(_lastSnoreTime!) > const Duration(seconds: 2)) {
                    snoreCount++;
                    _lastSnoreTime = now;
                    sessionSnoreWindows = 0;
                  }
                }
              } else {
                sessionSnoreWindows = 0;
              }

              windowIndex++;

              // ── 50% overlap: advance by hop (half window) ──
              rawAudioBuffer.removeRange(0, _hopBytes);
            }
          },
          onError: (e) {
            debugPrint('[AudioService] Stream error: $e');
          },
        );

        // ── Count down 10 seconds ──
        for (int i = 10; i > 0; i--) {
          if (!_isRecording) break;
          onProgress?.call(i);
          await Future.delayed(const Duration(seconds: 1));
        }
      } catch (e) {
        debugPrint('[AudioService] Failed to start recording: $e');
      }
    } else {
      debugPrint('[AudioService] No mic permission — skipping recording');
      await Future.delayed(const Duration(seconds: 2));
    }

    await stop();

    // ─────────────────────────────────────────────
    // EVENT CONFIRMATION  (Handled Dynamically Above)
    // ─────────────────────────────────────────────
    debugPrint('[AudioService] Session summary — '
        'coughs=$coughCount '
        'sneezes=$sneezeCount '
        'snores=$snoreCount');

    // ── Build dominant label ──
    String dominantLabel = 'No strong signal';

    if (coughCount > 0 || sneezeCount > 0 || snoreCount > 0) {
      final maxCount = [coughCount, sneezeCount, snoreCount].reduce(max);
      if (maxCount == coughCount) {
        dominantLabel = 'Cough detected 🤧';
      } else if (maxCount == sneezeCount) {
        dominantLabel = 'Sneeze detected 🤧';
      } else {
        dominantLabel = 'Snore pattern detected 😴';
      }
    }

    debugPrint('[AudioService] Detection complete — '
        'coughs=$coughCount sneezes=$sneezeCount snores=$snoreCount '
        'dominant="$dominantLabel" windows=${windowLogs.length}');

    return AudioDetectionResult(
      coughCount:     coughCount,
      sneezeCount:    sneezeCount,
      snoreCount:     snoreCount,
      waveformSamples: waveformSamples,
      dominantLabel:  dominantLabel,
      windowLogs:     windowLogs,
      lastCoughProb:  lastCoughProb,
      lastSneezeProb: lastSneezeProb,
      lastSnoreProb:  lastSnoreProb,
    );
  }

  // ─────────────────────────────────────────────
  // STOP
  // ─────────────────────────────────────────────
  Future<void> stop() async {
    _isRecording = false;
    await _recordSub?.cancel();
    _recordSub = null;
    try {
      await _recorder.stop();
      debugPrint('[AudioService] Recording stopped');
    } catch (e) {
      debugPrint('[AudioService] Error stopping recorder: $e');
    }
  }

  // ─────────────────────────────────────────────
  // RESET
  // ─────────────────────────────────────────────
  void reset() {
    coughCount  = 0;
    sneezeCount = 0;
    snoreCount  = 0;
    _lastCoughTime  = null;
    _lastSneezeTime = null;
    _lastSnoreTime  = null;
    _coughProbQueue.clear();
    _sneezeProbQueue.clear();
    _snoreProbQueue.clear();
  }

  // ─────────────────────────────────────────────
  // HELPERS — smoothing queue
  // ─────────────────────────────────────────────
  void _enqueue(List<double> queue, double value) {
    queue.add(value);
    if (queue.length > _smoothingWindow) queue.removeAt(0);
  }

  double _mean(List<double> queue) {
    if (queue.isEmpty) return 0.0;
    return queue.reduce((a, b) => a + b) / queue.length;
  }
}
