import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import 'package:camera/camera.dart';
import '../services/audio_service.dart';
import '../services/camera_service.dart';
import '../services/model_service.dart';
import '../services/storage_service.dart';
import '../services/insight_service.dart';
import '../utils/local_storage.dart';

// ─────────────────────────────────────────────────────────────
// DEVICE TEST SCREEN
// ─────────────────────────────────────────────────────────────

class DeviceTestScreen extends StatefulWidget {
  const DeviceTestScreen({super.key});

  @override
  State<DeviceTestScreen> createState() => _DeviceTestScreenState();
}

enum _TestPhase { idle, micTest, micDone, cameraTest, cameraDone, allDone }

class _DeviceTestScreenState extends State<DeviceTestScreen>
    with TickerProviderStateMixin {
  // ── Services ──
  final ModelService _modelService = ModelService();
  late AudioService _audioService;
  late CameraService _cameraService;
  final InsightService _insightService = const InsightService();

  // ── State ──
  _TestPhase _phase = _TestPhase.idle;
  int _countdown = 10;

  AudioDetectionResult _audioResult = const AudioDetectionResult(
    coughCount: 0,
    sneezeCount: 0,
    snoreCount: 0,
    waveformSamples: [],
    dominantLabel: 'No strong signal',
  );
  CameraResult? _cameraResult;
  InsightResult? _insightResult;

  // ── Live probabilities (updated per YAMNet window) ──
  double _liveCough = 0.0;
  double _liveSneeze = 0.0;
  double _liveSnore = 0.0;

  // ── Live amplitude for waveform ──
  final List<double> _waveformBars = List.filled(30, 0.1);
  int _waveformIndex = 0;

  // ── Session timing ──
  DateTime? _sessionStart;

  // ── Calibration panel state ──
  bool _showRawLogs = false;
  bool _showCalibPanel = false;

  // ── Progress animation ──
  late AnimationController _progressController;
  late Animation<double> _progressAnim;

  // ── Pulse animation for mic button ──
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // ── Camera scan animation ──
  late AnimationController _scanController;
  late Animation<double> _scanAnim;

  // ── Camera streaming ──
  StreamSubscription<CameraResult>? _cameraStream;

  @override
  void initState() {
    super.initState();

    _audioService = AudioService(_modelService);
    _cameraService = CameraService(_modelService);

    // Load ML models in background (non-blocking)
    _initModels();

    // Progress bar animation
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _progressAnim = Tween<double>(begin: 0.5, end: 0.5).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
    );

    // Pulse for mic button
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Camera scan line animation
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _scanAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.easeInOut),
    );

    // Wire amplitude callback for live waveform UI
    _audioService.onAmplitudeUpdate = (amp) {
      if (!mounted) return;
      setState(() {
        _waveformBars[_waveformIndex % _waveformBars.length] = amp;
        _waveformIndex++;
      });
    };

    // Wire per-window probability callback for live prob bars
    _audioService.onWindowProbs = (cough, sneeze, snore) {
      if (!mounted) return;
      setState(() {
        _liveCough = cough;
        _liveSneeze = sneeze;
        _liveSnore = snore;
      });
    };
  }

  /// Load TFLite models in background and log result.
  Future<void> _initModels() async {
    await _modelService.loadModels();
    if (mounted) setState(() {}); // Rebuild once models are ready
  }

  @override
  void dispose() {
    _progressController.dispose();
    _pulseController.dispose();
    _scanController.dispose();
    _cameraStream?.cancel();
    _audioService.stop();
    _cameraService.dispose();
    _modelService.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // MIC TEST
  // ─────────────────────────────────────────────
  Future<void> _startMicTest() async {
    _sessionStart = DateTime.now();
    setState(() {
      _phase = _TestPhase.micTest;
      _countdown = 10;
      _liveCough = 0.0;
      _liveSneeze = 0.0;
      _liveSnore = 0.0;
      _waveformBars.fillRange(0, _waveformBars.length, 0.1);
      _waveformIndex = 0;
    });

    final result = await _audioService.runDetection(
      coughOffset: StorageService.coughOffset,
      sneezeOffset: StorageService.sneezeOffset,
      snoreOffset: StorageService.snoreOffset,
      onProgress: (sec) {
        if (mounted) setState(() => _countdown = sec);
      },
    );

    if (!mounted) return;
    setState(() {
      _audioResult = result;
      _phase = _TestPhase.micDone;
    });
  }

  // ─────────────────────────────────────────────
  // CAMERA TEST
  // ─────────────────────────────────────────────
  Future<void> _startCameraTest() async {
    setState(() {
      _phase = _TestPhase.cameraTest;
      _cameraResult = null;
    });

    try {
      await _cameraService.initializeCamera();

      if (!mounted) return;
      setState(() {});

      _cameraStream = _cameraService.startLiveAnalysis().listen(
        (result) {
          if (result.faceDetected) {
            // Face confirmed — stop stream and mark done
            if (mounted) {
              setState(() {
                _cameraResult = result;
                _phase = _TestPhase.cameraDone;
              });
              _cameraStream?.cancel();
              _cameraService.stopLiveAnalysis();
            }
          } else {
            if (mounted) setState(() => _cameraResult = result);
          }
        },
        onError: (e) {
          debugPrint('[DeviceTest] Camera stream error: $e');
        },
      );
    } catch (e) {
      debugPrint('[DeviceTest] Camera init failed: $e');
      if (mounted) {
        setState(() => _phase = _TestPhase.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────
  // FINISH — save + navigate
  // ─────────────────────────────────────────────
  Future<void> _finish() async {
    final sessionEnd = DateTime.now();

    // ── Flat-key save (legacy) ──
    await StorageService.saveDetectionResult(
      coughCount: _audioResult.coughCount,
      sneezeCount: _audioResult.sneezeCount,
      snoreCount: _audioResult.snoreCount,
      eyeColor: _cameraResult?.eyeColor ?? 'unknown',
      brightnessLevel: _cameraResult?.brightness ?? 0.0,
      faceDetected: _cameraResult?.faceDetected ?? false,
      faceEmbedding: _cameraResult?.userFaceEmbedding.join(',') ?? '',
    );

    // ── Session JSON save (Day 5) ──
    final session = SessionResult(
      sessionStart:
          _sessionStart?.toIso8601String() ?? sessionEnd.toIso8601String(),
      sessionEnd: sessionEnd.toIso8601String(),
      coughCount: _audioResult.coughCount,
      sneezeCount: _audioResult.sneezeCount,
      snoreCount: _audioResult.snoreCount,
      faceDetected: _cameraResult?.faceDetected ?? false,
      brightnessValue: _cameraResult?.brightness ?? 0.0,
      lowLight: (_cameraResult?.brightness ?? 100.0) < 50.0,
      windows: _audioResult.windowLogs,
    );
    await StorageService.saveSession(session);

    // ── Compute offline health score ──
    final insight = _insightService.compute(
      coughCount: _audioResult.coughCount,
      sneezeCount: _audioResult.sneezeCount,
      snoreCount: _audioResult.snoreCount,
      faceDetected: _cameraResult?.faceDetected ?? false,
      brightness: _cameraResult?.brightness ?? 100.0,
    );

    // Animate progress to 100%
    setState(() {
      _insightResult = insight;
      _progressAnim = Tween<double>(
        begin: _progressController.value == 0 ? 0.5 : _progressAnim.value,
        end: 1.0,
      ).animate(
        CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
      );
      _phase = _TestPhase.allDone;
    });

    _progressController.forward(from: 0);

    // Stay on screen briefly to show health score card
    await Future.delayed(const Duration(milliseconds: 800));
  }

  /// Called after health score is shown — marks test done and goes home
  Future<void> _goHome() async {
    await LocalStorage.setDeviceTestDone();
    if (mounted) context.go('/home');
  }

  Future<void> _skipAll() async {
    await StorageService.saveDetectionResult(
      coughCount: 0,
      sneezeCount: 0,
      snoreCount: 0,
      eyeColor: 'unknown',
      brightnessLevel: 0.0,
      faceDetected: false,
      faceEmbedding: '',
    );

    setState(() {
      _progressAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
      );
      _phase = _TestPhase.allDone;
    });
    _progressController.forward(from: 0);

    await Future.delayed(const Duration(milliseconds: 1400));
    if (mounted) {
      await LocalStorage.setDeviceTestDone();
      if (mounted) context.go('/home');
    }
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildMicSection(),
                    const SizedBox(height: 20),
                    _buildCameraSection(),
                    const SizedBox(height: 24),
                    _buildActionArea(),
                    const SizedBox(height: 16),
                    _buildSkipButton(),
                    // ── Health score + calibration (after allDone) ──
                    if (_phase == _TestPhase.allDone) ...[
                      const SizedBox(height: 20),
                      if (_insightResult != null)
                        _buildHealthScoreCard(_insightResult!),
                      const SizedBox(height: 16),
                      _buildCalibrationPanel(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // TOP BAR WITH PROGRESS
  // ─────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.health_and_safety_rounded,
                      color: AppColors.primary, size: 26),
                  SizedBox(width: 6),
                  Text(
                    'Predoc',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_rounded,
                    color: AppColors.primary, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(50),
            ),
            child: const Text(
              'STEP 3 OF 3',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textMid,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Device Test',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textDark,
                ),
              ),
              AnimatedBuilder(
                animation: _progressAnim,
                builder: (_, __) => Text(
                  '${(_progressAnim.value * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: AnimatedBuilder(
              animation: _progressAnim,
              builder: (_, __) => LinearProgressIndicator(
                value: _progressAnim.value,
                minHeight: 8,
                backgroundColor: AppColors.divider,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // MIC TEST CARD
  // ─────────────────────────────────────────────
  Widget _buildMicSection() {
    final micDone = _phase == _TestPhase.micDone ||
        _phase == _TestPhase.cameraTest ||
        _phase == _TestPhase.cameraDone ||
        _phase == _TestPhase.allDone;

    return _SectionCard(
      icon: Icons.mic_rounded,
      iconBg: const Color(0xFFEDE9FE),
      iconColor: AppColors.primary,
      title: 'Mic Test',
      badge: micDone ? 'Done ✓' : null,
      badgeColor: AppColors.accentGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _instructionText(
            micDone
                ? 'Recording complete!'
                : _phase == _TestPhase.micTest
                    ? 'Listening… try a fake cough 🤧'
                    : 'Try doing a fake cough',
            micDone ? AppColors.accentGreen : AppColors.textMuted,
          ),
          const SizedBox(height: 16),

          // Waveform / live probs / countdown / result
          if (_phase == _TestPhase.micTest) ...[
            _buildWaveform(),
            const SizedBox(height: 12),
            _buildLiveProbBars(),
            const SizedBox(height: 10),
            Center(
              child: Text(
                '$_countdown sec',
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                ),
              ),
            ),
          ] else if (micDone && _phase != _TestPhase.idle) ...[
            _buildDetectionResult(),
          ] else ...[
            Center(
              child: _MicButton(
                pulseAnim: _pulseAnim,
                onTap: _startMicTest,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWaveform() {
    return SizedBox(
      height: 64,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(_waveformBars.length, (i) {
          final amp = _waveformBars[i].clamp(0.05, 1.0);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: 6,
            height: 64 * amp,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.7 + amp * 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }

  /// Live probability bars — shown during mic test for each YAMNet window.
  Widget _buildLiveProbBars() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _ProbBar(
              label: 'Cough',
              prob: _liveCough,
              threshold: 0.30 + StorageService.coughOffset,
              color: const Color(0xFFEF4444)),
          const SizedBox(height: 6),
          _ProbBar(
              label: 'Sneeze',
              prob: _liveSneeze,
              threshold: 0.35 + StorageService.sneezeOffset,
              color: const Color(0xFFF59E0B)),
          const SizedBox(height: 6),
          _ProbBar(
              label: 'Snore',
              prob: _liveSnore,
              threshold: 0.40 + StorageService.snoreOffset,
              color: const Color(0xFF8B5CF6)),
        ],
      ),
    );
  }

  Widget _buildDetectionResult() {
    final hasResult = _phase == _TestPhase.micDone ||
        _phase == _TestPhase.cameraTest ||
        _phase == _TestPhase.cameraDone ||
        _phase == _TestPhase.allDone;
    if (!hasResult) return const SizedBox.shrink();

    return Column(
      children: [
        // Result label
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _audioResult.dominantLabel.contains('No strong')
                ? const Color(0xFFFEF3C7)
                : AppColors.primaryLight,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Text(
                _audioResult.dominantLabel.contains('No strong') ? '🔇' : '🎙️',
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _audioResult.dominantLabel,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _audioResult.dominantLabel.contains('No strong')
                        ? const Color(0xFFB45309)
                        : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Count chips
        Row(
          children: [
            _CountChip(
                icon: '🤧', label: 'Cough', count: _audioResult.coughCount),
            const SizedBox(width: 8),
            _CountChip(
                icon: '🤧', label: 'Sneeze', count: _audioResult.sneezeCount),
            const SizedBox(width: 8),
            _CountChip(
                icon: '😴', label: 'Snore', count: _audioResult.snoreCount),
          ],
        ),
        const SizedBox(height: 10),
        // Smoothed prob bars (final values)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Detection Probabilities (last window)',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              _ProbBar(
                  label: 'Cough',
                  prob: _audioResult.lastCoughProb,
                  threshold: 0.30 + StorageService.coughOffset,
                  color: const Color(0xFFEF4444)),
              const SizedBox(height: 4),
              _ProbBar(
                  label: 'Sneeze',
                  prob: _audioResult.lastSneezeProb,
                  threshold: 0.35 + StorageService.sneezeOffset,
                  color: const Color(0xFFF59E0B)),
              const SizedBox(height: 4),
              _ProbBar(
                  label: 'Snore',
                  prob: _audioResult.lastSnoreProb,
                  threshold: 0.40 + StorageService.snoreOffset,
                  color: const Color(0xFF8B5CF6)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${_audioResult.windowLogs.length} windows analysed',
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // CAMERA TEST CARD
  // ─────────────────────────────────────────────
  Widget _buildCameraSection() {
    final cameraDone =
        _phase == _TestPhase.cameraDone || _phase == _TestPhase.allDone;
    final cameraActive = _phase == _TestPhase.cameraTest;
    final cameraEnabled = _phase == _TestPhase.micDone;

    return _SectionCard(
      icon: Icons.camera_alt_rounded,
      iconBg: const Color(0xFFFEF3C7),
      iconColor: const Color(0xFFB45309),
      title: 'Camera Test',
      badge: cameraDone ? 'Done ✓' : null,
      badgeColor: AppColors.accentGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _instructionText(
            cameraDone
                ? 'Camera analysis complete!'
                : cameraActive
                    ? 'Scanning your face…'
                    : 'Face detection + brightness check',
            cameraDone ? AppColors.accentGreen : AppColors.textMuted,
          ),
          const SizedBox(height: 16),
          if (cameraActive) ...[
            _buildCameraPreview(),
          ] else if (cameraDone && _cameraResult != null) ...[
            _buildCameraResult(),
          ] else ...[
            _CameraPlaceholder(
              enabled: cameraEnabled,
              onTap: cameraEnabled ? _startCameraTest : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    final ctrl = _cameraService.cameraController;

    if (ctrl == null || !ctrl.value.isInitialized) {
      return Center(
        child: Container(
          width: 260,
          height: 260,
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A2E),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 12),
                Text('Starting camera…',
                    style: TextStyle(
                        fontFamily: 'Nunito',
                        color: Colors.white70,
                        fontSize: 13)),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: Container(
        width: 260,
        height: 260,
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          shape: BoxShape.circle,
        ),
        clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: CameraPreview(ctrl)),
          // Scan line
          AnimatedBuilder(
            animation: _scanAnim,
            builder: (_, __) => Positioned(
              top: _scanAnim.value * 160,
              left: 0,
              right: 0,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Colors.transparent,
                    AppColors.primary.withValues(alpha: 0.8),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ),
          // Status label
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Text(
              _cameraResult?.faceDetected == true
                  ? 'Capturing identity…'
                  : 'Looking for face…',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                shadows: [Shadow(blurRadius: 4.0, color: Colors.black)],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// Camera result — Day 7 UI: Face / Light / Stability / Quality
  Widget _buildCameraResult() {
    final r = _cameraResult!;

    Color lightColor;
    IconData lightIcon;
    switch (r.lightStatus) {
      case 'LOW':
        lightColor = AppColors.accentRed;
        lightIcon = Icons.brightness_3_rounded;
        break;
      case 'BRIGHT':
        lightColor = const Color(0xFFF59E0B);
        lightIcon = Icons.wb_sunny_rounded;
        break;
      default: // 'OK'
        lightColor = AppColors.accentGreen;
        lightIcon = Icons.light_mode_rounded;
    }

    final qualityPct = (r.qualityScore * 100).toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Face ──
        _ResultRow(
          icon: r.faceDetected
              ? Icons.face_rounded
              : Icons.face_retouching_off_rounded,
          iconColor:
              r.faceDetected ? AppColors.accentGreen : AppColors.accentRed,
          label: 'Face: ${r.faceDetected ? '✅ Detected' : '❌ Not found'}',
          color: r.faceDetected ? AppColors.accentGreen : AppColors.accentRed,
          sublabel:
              r.faceDetected ? 'Camera quality confirmed' : 'Centre your face',
        ),
        const SizedBox(height: 8),
        // ── Light Status ──
        _ResultRow(
          icon: lightIcon,
          iconColor: lightColor,
          label:
              'Light: ${r.lightStatus}  (${r.brightness.toStringAsFixed(0)})',
          color: lightColor,
          sublabel: r.lightStatus == 'LOW'
              ? 'Too dark — move to better lighting'
              : r.lightStatus == 'BRIGHT'
                  ? 'Very bright — slight overexposure'
                  : 'Good lighting ✓',
        ),
        const SizedBox(height: 8),
        // ── Stability ──
        _ResultRow(
          icon: r.stable
              ? Icons.center_focus_strong_rounded
              : Icons.motion_photos_on_rounded,
          iconColor: r.stable ? AppColors.accentGreen : const Color(0xFFF59E0B),
          label: r.stable ? 'Stability: Stable ✓' : 'Stability: Move less',
          color: r.stable ? AppColors.accentGreen : const Color(0xFFF59E0B),
          sublabel:
              r.stable ? 'Face position consistent' : 'Hold your head still',
        ),
        const SizedBox(height: 10),
        // ── Quality Score ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Quality Score',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  ),
                  Text(
                    '$qualityPct%',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: r.qualityScore >= 0.7
                          ? AppColors.accentGreen
                          : r.qualityScore >= 0.4
                              ? const Color(0xFFF59E0B)
                              : AppColors.accentRed,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: LinearProgressIndicator(
                  value: r.qualityScore,
                  minHeight: 8,
                  backgroundColor: AppColors.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    r.qualityScore >= 0.7
                        ? AppColors.accentGreen
                        : r.qualityScore >= 0.4
                            ? const Color(0xFFF59E0B)
                            : AppColors.accentRed,
                  ),
                ),
              ),
            ],
          ),
        ),
        // ── Guidance (if any issue) ──
        if (!r.faceDetected || r.lightStatus != 'OK') ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: Color(0xFFB45309), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.guidance,
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────
  // ACTION AREA  (Finish / navigating label)
  // ─────────────────────────────────────────────
  Widget _buildActionArea() {
    if (_phase == _TestPhase.allDone) {
      return Column(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: AppColors.accentGreen, size: 54),
          const SizedBox(height: 10),
          const Text(
            'All tests complete! 🎉',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'See your health score below',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 13,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _goHome,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.primaryDark,
                borderRadius: BorderRadius.circular(50),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Go to Home',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 10),
                  Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 20),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final canFinish = _phase == _TestPhase.cameraDone;

    return AnimatedOpacity(
      opacity: canFinish ? 1.0 : 0.35,
      duration: const Duration(milliseconds: 300),
      child: GestureDetector(
        onTap: canFinish ? _finish : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(50),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Finish & Continue',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
              SizedBox(width: 10),
              Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkipButton() {
    if (_phase == _TestPhase.allDone || _phase == _TestPhase.micTest) {
      return const SizedBox.shrink();
    }
    return Center(
      child: GestureDetector(
        onTap: _skipAll,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Skip for now →',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // HEALTH SCORE CARD  (shown after allDone)
  // ─────────────────────────────────────────────
  Widget _buildHealthScoreCard(InsightResult insight) {
    Color scoreColor;
    Color scoreBg;
    switch (insight.color) {
      case HealthColor.green:
        scoreColor = const Color(0xFF16A34A);
        scoreBg = const Color(0xFFDCFCE7);
        break;
      case HealthColor.yellow:
        scoreColor = const Color(0xFFD97706);
        scoreBg = const Color(0xFFFEF3C7);
        break;
      case HealthColor.red:
        scoreColor = const Color(0xFFDC2626);
        scoreBg = const Color(0xFFFEE2E2);
        break;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scoreBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child:
                    Icon(Icons.favorite_rounded, color: scoreColor, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Health Score',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      'Offline · On-device',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // Big score bubble
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: scoreBg,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${insight.score}',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: scoreColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Color label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: scoreBg,
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text(
              insight.colorLabel.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: scoreColor,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Load breakdown
          _LoadBar(
              label: 'Cough',
              value: insight.coughLoad,
              color: const Color(0xFFEF4444)),
          const SizedBox(height: 6),
          _LoadBar(
              label: 'Sneeze',
              value: insight.sneezeLoad,
              color: const Color(0xFFF59E0B)),
          const SizedBox(height: 6),
          _LoadBar(
              label: 'Snore',
              value: insight.snoreLoad,
              color: const Color(0xFF8B5CF6)),
          const SizedBox(height: 14),
          const Divider(color: AppColors.divider),
          const SizedBox(height: 10),
          // Insight messages
          ...insight.messages.map((msg) => _InsightTile(msg: msg)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // CALIBRATION PANEL
  // ─────────────────────────────────────────────
  Widget _buildCalibrationPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.tune_rounded,
                    color: AppColors.textMuted, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Calibration Tools',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── View Raw Logs toggle ──
          GestureDetector(
            onTap: () => setState(() => _showRawLogs = !_showRawLogs),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.list_alt_rounded,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'View Raw Logs',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  Icon(
                    _showRawLogs
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),

          if (_showRawLogs) ...[
            const SizedBox(height: 10),
            _buildRawLogsTable(),
          ],

          const SizedBox(height: 10),

          // ── Tune Detection toggle ──
          GestureDetector(
            onTap: () => setState(() => _showCalibPanel = !_showCalibPanel),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.settings_rounded,
                      color: AppColors.textMuted, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Improve Detection Tuning',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  Icon(
                    _showCalibPanel
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),

          if (_showCalibPanel) ...[
            const SizedBox(height: 12),
            _buildThresholdTuner(),
          ],
        ],
      ),
    );
  }

  Widget _buildRawLogsTable() {
    final logs = _audioResult.windowLogs;
    if (logs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'No window logs yet — run a mic test first.',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 13,
            color: AppColors.textMuted,
          ),
        ),
      );
    }

    // Show last 5 logs (most recent first)
    final recent = logs.reversed.take(5).toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          // Table header
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(flex: 1, child: _TableHeader('W#')),
                Expanded(flex: 2, child: _TableHeader('Cough')),
                Expanded(flex: 2, child: _TableHeader('Sneeze')),
                Expanded(flex: 2, child: _TableHeader('Snore')),
                Expanded(flex: 2, child: _TableHeader('Pass?')),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          ...recent.map(
            (log) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                children: [
                  Expanded(
                      flex: 1,
                      child: Text('${log.windowIndex}', style: _tableStyle())),
                  Expanded(
                      flex: 2,
                      child: Text(log.coughProb.toStringAsFixed(3),
                          style: _tableStyle(
                              bold: log.coughProb >= 0.30,
                              color: log.coughProb >= 0.30
                                  ? const Color(0xFFEF4444)
                                  : null))),
                  Expanded(
                      flex: 2,
                      child: Text(log.sneezeProb.toStringAsFixed(3),
                          style: _tableStyle(
                              bold: log.sneezeProb >= 0.35,
                              color: log.sneezeProb >= 0.35
                                  ? const Color(0xFFF59E0B)
                                  : null))),
                  Expanded(
                      flex: 2,
                      child: Text(log.snoreProb.toStringAsFixed(3),
                          style: _tableStyle(
                              bold: log.snoreProb >= 0.40,
                              color: log.snoreProb >= 0.40
                                  ? const Color(0xFF8B5CF6)
                                  : null))),
                  Expanded(
                      flex: 2,
                      child: Text(log.passedThreshold ? '✓' : '—',
                          style: _tableStyle(
                              bold: log.passedThreshold,
                              color: log.passedThreshold
                                  ? AppColors.accentGreen
                                  : AppColors.textMuted))),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 2),
            child: Text(
              'Showing last ${recent.length} of ${logs.length} windows',
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 10,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _tableStyle({bool bold = false, Color? color}) => TextStyle(
        fontFamily: 'Nunito',
        fontSize: 12,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        color: color ?? AppColors.textDark,
      );

  Widget _buildThresholdTuner() {
    return StatefulBuilder(
      builder: (context, setLocal) {
        final co = StorageService.coughOffset;
        final so = StorageService.sneezeOffset;
        final no = StorageService.snoreOffset;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Adjust thresholds to reduce false positives (↑) or missed events (↓)',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            _ThresholdRow(
              label: 'Cough',
              base: 0.30,
              offset: co,
              color: const Color(0xFFEF4444),
              onRaise: () async {
                await StorageService.raiseCoughThreshold();
                setLocal(() {});
              },
              onLower: () async {
                await StorageService.lowerCoughThreshold();
                setLocal(() {});
              },
            ),
            const SizedBox(height: 8),
            _ThresholdRow(
              label: 'Sneeze',
              base: 0.35,
              offset: so,
              color: const Color(0xFFF59E0B),
              onRaise: () async {
                await StorageService.raiseSneezeThreshold();
                setLocal(() {});
              },
              onLower: () async {
                await StorageService.lowerSneezeThreshold();
                setLocal(() {});
              },
            ),
            const SizedBox(height: 8),
            _ThresholdRow(
              label: 'Snore',
              base: 0.40,
              offset: no,
              color: const Color(0xFF8B5CF6),
              onRaise: () async {
                await StorageService.raiseSnoreThreshold();
                setLocal(() {});
              },
              onLower: () async {
                await StorageService.lowerSnoreThreshold();
                setLocal(() {});
              },
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () async {
                await StorageService.resetCalibration();
                setLocal(() {});
              },
              child: const Text(
                'Reset to defaults',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _instructionText(String text, Color color) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Nunito',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PROBABILITY BAR
// ─────────────────────────────────────────────────────────────

class _ProbBar extends StatelessWidget {
  final String label;
  final double prob;
  final double threshold;
  final Color color;

  const _ProbBar({
    required this.label,
    required this.prob,
    required this.threshold,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final crossed = prob >= threshold;
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              // Background track
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              // Threshold marker
              FractionallySizedBox(
                widthFactor: threshold.clamp(0.0, 1.0),
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                          color: color.withValues(alpha: 0.6), width: 1.5),
                    ),
                  ),
                ),
              ),
              // Fill bar
              AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 200),
                widthFactor: prob.clamp(0.0, 1.0),
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: crossed ? color : color.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            prob.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 11,
              fontWeight: crossed ? FontWeight.w800 : FontWeight.w600,
              color: crossed ? color : AppColors.textMuted,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          crossed ? Icons.circle : Icons.circle_outlined,
          size: 8,
          color: crossed ? color : AppColors.divider,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// LOAD BAR (for health score breakdown)
// ─────────────────────────────────────────────────────────────

class _LoadBar extends StatelessWidget {
  final String label;
  final double value; // 0.0–1.0
  final Color color;

  const _LoadBar(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${(value * 100).round()}%',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// INSIGHT TILE
// ─────────────────────────────────────────────────────────────

class _InsightTile extends StatelessWidget {
  final InsightMessage msg;
  const _InsightTile({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(msg.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.title,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  msg.body,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// THRESHOLD ROW (calibration panel)
// ─────────────────────────────────────────────────────────────

class _ThresholdRow extends StatelessWidget {
  final String label;
  final double base;
  final double offset;
  final Color color;
  final VoidCallback onRaise;
  final VoidCallback onLower;

  const _ThresholdRow({
    required this.label,
    required this.base,
    required this.offset,
    required this.color,
    required this.onRaise,
    required this.onLower,
  });

  @override
  Widget build(BuildContext context) {
    final effective = (base + offset).clamp(0.05, 0.95);
    final offsetStr = offset >= 0
        ? '+${offset.toStringAsFixed(2)}'
        : offset.toStringAsFixed(2);

    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        // Lower threshold button
        GestureDetector(
          onTap: onLower,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.remove_rounded, color: color, size: 16),
          ),
        ),
        const SizedBox(width: 8),
        // Effective value display
        Expanded(
          child: Column(
            children: [
              Text(
                effective.toStringAsFixed(2),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              Text(
                'offset $offsetStr',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 10,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Raise threshold button
        GestureDetector(
          onTap: onRaise,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.add_rounded, color: color, size: 16),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TABLE HEADER
// ─────────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  final String text;
  const _TableHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: AppColors.textMuted,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SECTION CARD (unchanged from Day 4)
// ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String? badge;
  final Color? badgeColor;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.child,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor ?? AppColors.accentGreen,
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MIC BUTTON (unchanged from Day 4)
// ─────────────────────────────────────────────────────────────

class _MicButton extends StatelessWidget {
  final Animation<double> pulseAnim;
  final VoidCallback onTap;

  const _MicButton({required this.pulseAnim, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: pulseAnim,
        builder: (_, child) => Transform.scale(
          scale: pulseAnim.value,
          child: child,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.12),
              ),
            ),
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child:
                  const Icon(Icons.mic_rounded, color: Colors.white, size: 36),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CAMERA PLACEHOLDER (unchanged from Day 4)
// ─────────────────────────────────────────────────────────────

class _CameraPlaceholder extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;

  const _CameraPlaceholder({required this.enabled, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.45,
        duration: const Duration(milliseconds: 300),
        child: Container(
          height: 140,
          decoration: BoxDecoration(
            color: enabled ? AppColors.primaryLight : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: enabled ? AppColors.primary : AppColors.divider,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.camera_alt_rounded,
                size: 42,
                color: enabled ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(height: 10),
              Text(
                enabled
                    ? 'Tap to start camera test'
                    : 'Complete mic test first',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: enabled ? AppColors.primary : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// RESULT ROW (unchanged from Day 4)
// ─────────────────────────────────────────────────────────────

class _ResultRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color color;
  final String? sublabel;

  const _ResultRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.color,
    this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                if (sublabel != null)
                  Text(
                    sublabel!,
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// COUNT CHIP (unchanged from Day 4)
// ─────────────────────────────────────────────────────────────

class _CountChip extends StatelessWidget {
  final String icon;
  final String label;
  final int count;

  const _CountChip(
      {required this.icon, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: count > 0 ? AppColors.primaryLight : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: count > 0 ? AppColors.primary : AppColors.textMuted,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
