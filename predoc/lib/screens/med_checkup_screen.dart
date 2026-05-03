import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../theme/app_theme.dart';
import 'ask_ai_screen.dart';
import '../engine/med_check_engine.dart';

class MedCheckupScreen extends StatefulWidget {
  const MedCheckupScreen({super.key});
  @override
  State<MedCheckupScreen> createState() => _MedCheckupScreenState();
}

class _MedCheckupScreenState extends State<MedCheckupScreen> with WidgetsBindingObserver {
  // ── ARCHITECTURE COMPONENTS ──
  CameraController? _cameraCtrl;
  late DetectionEngine _detectionEngine;
  late StepManager _stepManager;
  late ResultGenerator _resultGenerator;
  
  final AudioRecorder _audioRecorder = AudioRecorder();
  Timer? _audioTimer;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  bool _isProcessingImage = false;
  bool _hasStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize backend engine components
    _detectionEngine = DetectionEngine();
    _resultGenerator = ResultGenerator();
    _stepManager = StepManager(
      onStepChanged: () {
        if (mounted) setState(() {});
        if (_stepManager.currentStep == MedStep.complete) {
          _cameraCtrl?.stopImageStream();
        }
      }
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraCtrl?.dispose();
    _detectionEngine.dispose();
    _audioTimer?.cancel();
    _audioRecorder.dispose();
    _accelSubscription?.cancel();
    super.dispose();
  }

  void _resetCheckup() {
    _audioRecorder.stop();
    _audioTimer?.cancel();
    _accelSubscription?.cancel();
    
    setState(() {
      _detectionEngine = DetectionEngine();
      _resultGenerator = ResultGenerator();
      _stepManager = StepManager(
        onStepChanged: () {
          if (mounted) setState(() {});
          if (_stepManager.currentStep == MedStep.complete) {
            _cameraCtrl?.stopImageStream();
          }
        }
      );
    });
    
    _cameraCtrl?.startImageStream(_processCameraImage);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraCtrl == null || !_cameraCtrl!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _cameraCtrl?.stopImageStream();
    } else if (state == AppLifecycleState.resumed) {
      _cameraCtrl?.startImageStream(_processCameraImage);
    }
  }

  Future<void> _initSystem() async {
    // ONE-TIME PERMISSIONS 
    await [
      Permission.camera,
      Permission.microphone,
    ].request();

    final cameras = await availableCameras();
    final frontCam = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front, 
      orElse: () => cameras.first
    );

    _cameraCtrl = CameraController(
      frontCam, 
      ResolutionPreset.low, 
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    
    await _cameraCtrl!.initialize();
    if (!mounted) return;
    setState(() {});
    
    _cameraCtrl!.startImageStream(_processCameraImage);
  }

  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final camera = _cameraCtrl!.description;
    final sensorOrientation = camera.sensorOrientation;
    
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = _orientations[_cameraCtrl!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) {
      return null;
    }

    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  void _processCameraImage(CameraImage image) async {
    if (_isProcessingImage || 
        _stepManager.currentStep == MedStep.complete || 
        _stepManager.currentStep == MedStep.breathing || 
        _stepManager.currentStep == MedStep.cough || 
        _stepManager.currentStep == MedStep.voice || 
        _stepManager.currentStep == MedStep.tremor) {
      return;
    }
        
    _isProcessingImage = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage != null) {
        final faces = await _detectionEngine.faceDetector.processImage(inputImage);
        if (faces.isNotEmpty) {
          // Offload strictly to detection engine
          _detectionEngine.processFace(
            faces.first, 
            _stepManager, 
            _resultGenerator, 
            _startAudioTracking // Callback when visual exam is done
          );
        }
      }
    } catch (e) {
      debugPrint("Face Processing Error: $e");
    } finally {
      _isProcessingImage = false;
    }
  }

  Future<void> _startAudioTracking() async {
    if (await _audioRecorder.hasPermission()) {
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/med_check_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(const RecordConfig(), path: path);

      _audioTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
        if (_stepManager.currentStep == MedStep.complete) {
          _audioTimer?.cancel();
          return;
        }
        final amp = await _audioRecorder.getAmplitude();
        
        // Offload strictly to detection engine
        _detectionEngine.processAudio(
          amp.current, 
          _stepManager, 
          _resultGenerator, 
          () {
            _audioRecorder.stop();
            _audioTimer?.cancel();
            _startMotionTracking();
          }
        );
      });
    }
  }

  void _startMotionTracking() {
    _accelSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      if (_stepManager.currentStep == MedStep.complete) {
        _accelSubscription?.cancel();
        return;
      }
      
      if (mounted) setState(() {});
      
      _detectionEngine.processMotion(
        event.x, event.y, event.z, 
        _stepManager, 
        _resultGenerator, 
        () {
          _accelSubscription?.cancel();
          _cameraCtrl?.stopImageStream();
          if (mounted) setState(() {});
        }
      );
    });
  }

  Color _getStatusColor(String status) {
    if (status.contains("Good") || status.contains("Normal")) return AppColors.good;
    if (status.contains("Attention") || status.contains("High")) return AppColors.risk;
    return AppColors.moderate;
  }

  // ── UI RENDERER ──
  @override
  Widget build(BuildContext context) {
    if (!_hasStarted) {
      return _buildLandingScreen();
    }
    
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Physical Exam', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppColors.paddingH, vertical: 24),
        child: Column(
          children: [
            // Camera Area
            Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryLight,
                  border: Border.all(
                    color: _stepManager.currentStep == MedStep.complete ? AppColors.good : AppColors.primary, 
                    width: 4
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_stepManager.currentStep == MedStep.complete ? AppColors.good : AppColors.primary).withValues(alpha: 0.3),
                      blurRadius: 30,
                      spreadRadius: 8,
                    )
                  ],
                ),
                child: ClipOval(
                  child: _cameraCtrl != null && _cameraCtrl!.value.isInitialized
                      ? SizedBox(
                          width: 260,
                          height: 260,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _cameraCtrl!.value.previewSize?.height ?? 1, // swapped for portrait
                              height: _cameraCtrl!.value.previewSize?.width ?? 1,
                              child: CameraPreview(_cameraCtrl!),
                            ),
                          ),
                        )
                      : const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Instruction Card
            if (_stepManager.currentStep != MedStep.complete)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                decoration: appCardDecoration(),
                child: Column(
                  children: [
                    const Icon(Icons.medical_information_rounded, color: AppColors.primary, size: 32),
                    const SizedBox(height: 12),
                    Text(
                      _stepManager.currentInstruction,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_stepManager.isAdvancing)
                      const Text(
                        "Processing...",
                        style: TextStyle(fontFamily: 'Nunito', color: AppColors.good, fontWeight: FontWeight.w700),
                      )
                    else
                      const Text(
                        "Follow the instruction to proceed",
                        style: TextStyle(fontFamily: 'Nunito', color: AppColors.textMuted, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),

            // Results Area
            if (_stepManager.currentStep == MedStep.complete) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: appCardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Med Check Report",
                      style: TextStyle(fontFamily: 'Nunito', fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textDark),
                    ),
                    const SizedBox(height: 16),
                    ..._resultGenerator.results.entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.key, style: const TextStyle(fontFamily: 'Nunito', fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getStatusColor(e.value).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(50),
                              border: Border.all(color: _getStatusColor(e.value).withValues(alpha: 0.5)),
                            ),
                            child: Text(
                              e.value,
                              style: TextStyle(fontFamily: 'Nunito', fontSize: 13, fontWeight: FontWeight.w800, color: _getStatusColor(e.value)),
                            ),
                          )
                        ],
                      ),
                    )),
                    
                    const Divider(height: 32, color: AppColors.divider),
                    
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.auto_awesome_rounded),
                        label: const Text("Get Suggestions from AI"),
                        onPressed: () {
                          final reportText = _resultGenerator.generateReportString();
                          Navigator.push(context, MaterialPageRoute(builder: (_) => AskAiScreen(
                            initialQuery: "Here is my Med Check Report:\n$reportText\n\nPlease provide some wellness suggestions.",
                          )));
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text("Try Again"),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: AppColors.primary),
                        ),
                        onPressed: _resetCheckup,
                      ),
                    )
                  ],
                ),
              )
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildLandingScreen() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Physical Exam', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.medical_services_rounded, size: 80, color: AppColors.primary),
              const SizedBox(height: 24),
              const Text(
                'AI-Free Med Check',
                style: TextStyle(fontFamily: 'Nunito', fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textDark),
              ),
              const SizedBox(height: 16),
              const Text(
                'A guided, rule-based physical examination using your device sensors. No AI detection is used.\n\nMake sure your face is well-lit.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Nunito', fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textMuted, height: 1.5),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start Checkup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () {
                    setState(() => _hasStarted = true);
                    _initSystem();
                  },
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
