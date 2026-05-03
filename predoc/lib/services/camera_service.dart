import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'model_service.dart';

// ─────────────────────────────────────────────────────────────
// CAMERA RESULT
// ─────────────────────────────────────────────────────────────

class CameraResult {
  final bool   faceDetected;
  final double brightness;      // 0–255, Y-channel average of face ROI
  final String eyeColor;        // kept for backward-compat; always 'normal'
  final String brightnessLabel; // 'Low lighting' | 'Good' | 'Bright'
  final String lightStatus;     // 'LOW' | 'OK' | 'BRIGHT'  (Day 7)
  final String guidance;
  final bool   stable;          // face movement < 5 px
  final double qualityScore;    // 0.0 – 1.0  (Day 7)
  final List<double> userFaceEmbedding; // always empty in Day 7

  const CameraResult({
    required this.faceDetected,
    required this.brightness,
    this.eyeColor = 'normal',
    required this.brightnessLabel,
    required this.lightStatus,
    required this.guidance,
    required this.stable,
    required this.qualityScore,
    this.userFaceEmbedding = const [],
  });
}

// ─────────────────────────────────────────────────────────────
// CAMERA SERVICE
// ─────────────────────────────────────────────────────────────

class CameraService {
  // ModelService kept in constructor for API compatibility, but not used in
  // frame processing (Day 7 removes face embedding extraction).
  final ModelService _modelService; // ignore: unused_field
  CameraController? cameraController;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: false,
      enableLandmarks: false,
    ),
  );

  bool _isProcessingFrame = false;
  bool _isInitialized = false;
  StreamController<CameraResult>? _resultStreamCtrl;

  // ── Stability tracking ──
  Offset? _prevFaceCenter;

  CameraService(this._modelService);

  bool get isInitialized => _isInitialized;

  // ─────────────────────────────────────────────
  // INITIALIZE CAMERA
  // ─────────────────────────────────────────────
  Future<void> initializeCamera() async {
    try {
      debugPrint('[CameraService] Fetching available cameras...');
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        debugPrint('[CameraService] ERROR: No cameras found on device');
        return;
      }

      debugPrint('[CameraService] Found ${cameras.length} camera(s)');

      CameraDescription selectedCamera;
      try {
        selectedCamera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
        );
        debugPrint('[CameraService] Using front camera');
      } catch (_) {
        selectedCamera = cameras.first;
        debugPrint('[CameraService] No front camera — using first available');
      }

      if (cameraController != null) {
        debugPrint('[CameraService] Disposing previous controller...');
        await cameraController!.dispose();
        cameraController = null;
        _isInitialized = false;
      }

      cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      debugPrint('[CameraService] Initializing camera controller...');
      await cameraController!.initialize();
      _isInitialized = true;
      _prevFaceCenter = null;
      debugPrint('[CameraService] Camera initialized ✓');
    } catch (e) {
      debugPrint('[CameraService] ERROR initializing camera: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  // ─────────────────────────────────────────────
  // START LIVE ANALYSIS
  // ─────────────────────────────────────────────
  Stream<CameraResult> startLiveAnalysis() {
    _resultStreamCtrl = StreamController<CameraResult>.broadcast();

    if (cameraController == null || !cameraController!.value.isInitialized) {
      debugPrint('[CameraService] startLiveAnalysis: controller not ready');
      _resultStreamCtrl!.close();
      return _resultStreamCtrl!.stream;
    }

    debugPrint('[CameraService] Camera started — beginning live analysis');

    cameraController!.startImageStream((CameraImage image) async {
      if (_isProcessingFrame) return;
      _isProcessingFrame = true;
      try {
        await _processFrame(image);
      } catch (e) {
        debugPrint('[CameraService] Frame processing error: $e');
      } finally {
        _isProcessingFrame = false;
      }
    });

    return _resultStreamCtrl!.stream;
  }

  void stopLiveAnalysis() {
    try {
      if (cameraController != null &&
          cameraController!.value.isInitialized &&
          cameraController!.value.isStreamingImages) {
        cameraController!.stopImageStream();
        debugPrint('[CameraService] Image stream stopped');
      }
    } catch (e) {
      debugPrint('[CameraService] Error stopping image stream: $e');
    }
    _resultStreamCtrl?.close();
    _resultStreamCtrl = null;
  }

  // ─────────────────────────────────────────────
  // PROCESS SINGLE FRAME
  // ─────────────────────────────────────────────
  Future<void> _processFrame(CameraImage image) async {
    // ── Build InputImage for MLKit ──
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final format =
        InputImageFormatValue.fromRawValue(image.format.raw) ??
            InputImageFormat.nv21;

    final camera = cameraController!.description;
    final sensorOrientation = camera.sensorOrientation;
    
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      final orientations = {
        DeviceOrientation.portraitUp: 0,
        DeviceOrientation.landscapeLeft: 90,
        DeviceOrientation.portraitDown: 180,
        DeviceOrientation.landscapeRight: 270,
      };
      var rotationCompensation = orientations[cameraController!.value.deviceOrientation];
      if (rotationCompensation != null) {
        if (camera.lensDirection == CameraLensDirection.front) {
          rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
        } else {
          rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
        }
        rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
      }
    }
    rotation ??= InputImageRotation.rotation270deg;

    final inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: imageSize,
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );

    // ── A. MLKit Face Detection ──
    final faces = await _faceDetector.processImage(inputImage);
    final faceDetected = faces.isNotEmpty;

    // ── B. Brightness — face ROI only (Y-plane of YUV420) ──
    double brightness = 100.0; // fallback if no face / non-YUV
    if (faceDetected && image.format.group == ImageFormatGroup.yuv420) {
      final face = faces.first;
      final box = face.boundingBox;
      final yPlane = image.planes[0];
      final yBytes = yPlane.bytes;
      final bytesPerRow = yPlane.bytesPerRow;
      final imgW = image.width;
      final imgH = image.height;

      // Clamp ROI to image bounds
      final x0 = max(0, box.left.toInt());
      final y0 = max(0, box.top.toInt());
      final x1 = min(imgW - 1, box.right.toInt());
      final y1 = min(imgH - 1, box.bottom.toInt());

      int sum = 0;
      int count = 0;

      // Sample every 4th pixel for speed
      for (int row = y0; row <= y1; row += 4) {
        for (int col = x0; col <= x1; col += 4) {
          final idx = row * bytesPerRow + col;
          if (idx < yBytes.length) {
            sum += yBytes[idx] & 0xFF;
            count++;
          }
        }
      }
      if (count > 0) brightness = sum / count.toDouble();
    } else if (!faceDetected && image.format.group == ImageFormatGroup.yuv420) {
      // Whole-frame brightness when no face (to still guide user with light info)
      final yPlane = image.planes[0].bytes;
      int sum = 0;
      for (int i = 0; i < yPlane.length; i += 10) {
        sum += yPlane[i] & 0xFF;
      }
      brightness = sum / (yPlane.length / 10.0);
    }

    // ── C. Light Classification (Day 7 thresholds) ──
    String lightStatus;
    String brightnessLabel;
    if (brightness < 50.0) {
      lightStatus = 'LOW';
      brightnessLabel = 'Low lighting';
    } else if (brightness <= 120.0) {
      lightStatus = 'OK';
      brightnessLabel = 'Good';
    } else {
      lightStatus = 'BRIGHT';
      brightnessLabel = 'Bright';
    }

    // ── D. Stability — face center movement ──
    bool stable = true;
    if (faceDetected) {
      final face = faces.first;
      final box = face.boundingBox;
      final currentCenter = Offset(
        box.left + box.width / 2,
        box.top + box.height / 2,
      );

      if (_prevFaceCenter != null) {
        final dx = currentCenter.dx - _prevFaceCenter!.dx;
        final dy = currentCenter.dy - _prevFaceCenter!.dy;
        final movement = sqrt(dx * dx + dy * dy);
        stable = movement < 5.0;
        debugPrint('[CameraService] Face movement: ${movement.toStringAsFixed(1)}px stable=$stable');
      }
      _prevFaceCenter = currentCenter;
    } else {
      _prevFaceCenter = null;
      stable = false;
    }

    // ── E. Quality Score ──
    double qualityScore = 0.0;
    if (faceDetected)        qualityScore += 0.4;
    if (lightStatus == 'OK') qualityScore += 0.3;
    if (stable)              qualityScore += 0.3;

    // ── F. Guidance text ──
    String guidance;
    if (!faceDetected) {
      guidance = 'Centre your face in the camera.';
    } else if (lightStatus == 'LOW') {
      guidance = 'Too dark — move to a brighter area.';
    } else if (!stable) {
      guidance = 'Hold still for a stable reading.';
    } else {
      guidance = 'Good — hold position! ✓';
    }

    debugPrint('[CameraService] face=$faceDetected brightness=${brightness.toStringAsFixed(1)} '
        'lightStatus=$lightStatus stable=$stable qualityScore=${qualityScore.toStringAsFixed(2)}');

    _resultStreamCtrl?.add(CameraResult(
      faceDetected:    faceDetected,
      brightness:      brightness,
      eyeColor:        'normal',
      brightnessLabel: brightnessLabel,
      lightStatus:     lightStatus,
      guidance:        guidance,
      stable:          stable,
      qualityScore:    qualityScore,
    ));
  }

  // ─────────────────────────────────────────────
  // DISPOSE
  // ─────────────────────────────────────────────
  void dispose() {
    stopLiveAnalysis();
    cameraController?.dispose();
    cameraController = null;
    _isInitialized = false;
    _prevFaceCenter = null;
    _faceDetector.close();
    debugPrint('[CameraService] Disposed');
  }
}
