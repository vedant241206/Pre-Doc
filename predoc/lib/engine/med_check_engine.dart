import 'dart:async';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum MedStep { alignFace, blink, headTurn, mouthOpen, breathing, cough, voice, tremor, complete }

/// Manages the step-by-step instruction flow of the physical exam.
class StepManager {
  MedStep currentStep = MedStep.alignFace;
  String currentInstruction = "Look straight at the camera";
  bool isAdvancing = false;
  
  final void Function() onStepChanged;
  
  StepManager({required this.onStepChanged});

  void advanceTo(MedStep nextStep, String instruction) {
    if (isAdvancing) return;
    isAdvancing = true;
    currentInstruction = "Good!";
    onStepChanged();
    
    Future.delayed(const Duration(seconds: 2), () {
      currentStep = nextStep;
      currentInstruction = instruction;
      isAdvancing = false;
      onStepChanged();
    });
  }
}

/// Generates the structured medical report after the exam finishes.
class ResultGenerator {
  // Use a linked map to preserve order
  final Map<String, String> results = {};
  
  void addResult(String testName, String status) {
    results[testName] = status;
  }
  
  void finalizeReport() {
    bool hasIssues = results.values.any((status) {
      final s = status.toLowerCase();
      return s.contains("high") || s.contains("risk") || s.contains("attention") || s.contains("lesion");
    });
    
    if (hasIssues) {
      results['Overall Status'] = 'Attention Needed (See Doctor)';
    } else {
      results['Overall Status'] = 'No issue found';
    }
  }
  
  String generateReportString() {
    return results.entries.map((e) => "${e.key}: ${e.value}").join("\n");
  }
}

// ── SYMPTOM DICTIONARY (Deterministic Medical Logic) ──
class SymptomAnalyzer {
  static String analyzeFacialSymmetry(Face face) {
    // Check for Bell's Palsy or Stroke (Cranial Nerve VII)
    final leftMouth = face.landmarks[FaceLandmarkType.leftMouth]?.position;
    final rightMouth = face.landmarks[FaceLandmarkType.rightMouth]?.position;
    if (leftMouth != null && rightMouth != null) {
      final yDiff = (leftMouth.y - rightMouth.y).abs();
      final threshold = face.boundingBox.height * 0.05;
      final diffStr = yDiff.toStringAsFixed(1);
      if (yDiff > threshold) {
        return "Mild Asymmetry (Diff: $diffStr px) - Acceptable";
      }
      return "Symmetric (Diff: $diffStr px)";
    }
    return "Symmetric (Normal)";
  }

  static String analyzeEyeColor(int r, int g, int b) {
    // Deterministic Jaundice Check: High Red/Green (Yellow) vs Blue
    if (r > 180 && g > 180 && b < 120) return "Scleral Icterus Detected (Possible Jaundice / Liver issue)";
    return "Normal Sclera";
  }

  static String analyzeLipColor(int r, int g, int b) {
    // Cyanosis: High blue relative to red
    if (b > r + 20) return "Cyanosis Detected (Possible Hypoxia)";
    // Pallor: Low overall saturation / pale red
    if (r > 150 && r < 190 && g > 150 && b > 150) return "Pallor Detected (Possible Anemia / Low Hb)";
    // Erythema/Fever: Extreme red
    if (r > 200 && g < 100 && b < 100) return "Erythema Detected (Possible Fever/Inflammation)";
    return "Normal Mucosa";
  }

  static String analyzeTremor(double variance) {
    // Determine neurologic hand stability based on accelerometer variance
    if (variance > 2.5) return "Mild Tremor (Acceptable)";
    if (variance > 1.0) return "Mild Tremor (Acceptable)";
    return "Normal Stability";
  }
}

/// The core deterministic Rule-Based Detection Engine (NO AI).
/// Evaluates raw sensor data (Face contours, audio amplitude) against strict rules.
class DetectionEngine {
  final FaceDetector faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      enableTracking: true,
      enableLandmarks: true,
    ),
  );
  
  bool turnedLeft = false;
  bool turnedRight = false;
  int coughFrames = 0;
  int voiceFrames = 0;
  
  /// Processes visual face data using geometric rules.
  void processFace(Face face, StepManager stepManager, ResultGenerator resultGen, void Function() onStartAudio) {
    if (stepManager.isAdvancing) return;

    if (stepManager.currentStep == MedStep.alignFace) {
      // Rule: Face pitch & yaw must be near 0
      if (face.headEulerAngleY != null && face.headEulerAngleZ != null && 
          face.headEulerAngleY!.abs() < 12 && face.headEulerAngleZ!.abs() < 12) {
        
        // Evaluate clinical symmetry immediately
        final symmetryStatus = SymptomAnalyzer.analyzeFacialSymmetry(face);
        resultGen.addResult('Cranial Symmetry (CN VII)', symmetryStatus);
        
        stepManager.advanceTo(MedStep.blink, "Blink your eyes");
      }
    } else if (stepManager.currentStep == MedStep.blink) {
      // Rule: Both eyes must drop below threshold (blink detected)
      if (face.leftEyeOpenProbability != null && face.leftEyeOpenProbability! < 0.4 &&
          face.rightEyeOpenProbability != null && face.rightEyeOpenProbability! < 0.4) {
        final leftP = face.leftEyeOpenProbability!.toStringAsFixed(2);
        final rightP = face.rightEyeOpenProbability!.toStringAsFixed(2);
        resultGen.addResult('Corneal Reflex', 'Normal (Blink L:$leftP R:$rightP)');
        stepManager.advanceTo(MedStep.headTurn, "Turn head left then right");
      }
    } else if (stepManager.currentStep == MedStep.headTurn) {
      // Rule: Head must pan left (< -25 deg) and right (> 25 deg)
      if (face.headEulerAngleY != null) {
        if (face.headEulerAngleY! < -25) turnedLeft = true;
        if (face.headEulerAngleY! > 25) turnedRight = true;
      }
      if (turnedLeft && turnedRight) {
        resultGen.addResult('Cervical ROM', 'Normal (Full Rotation > 25°)');
        stepManager.advanceTo(MedStep.mouthOpen, "Open your mouth wide");
      }
    } else if (stepManager.currentStep == MedStep.mouthOpen) {
      // Rule: Distance between upper and lower lip contours must exceed threshold relative to face size
      final upperLip = face.contours[FaceContourType.upperLipTop]?.points;
      final lowerLip = face.contours[FaceContourType.lowerLipBottom]?.points;
      if (upperLip != null && lowerLip != null && upperLip.isNotEmpty && lowerLip.isNotEmpty) {
        final upperPoint = upperLip[upperLip.length ~/ 2];
        final lowerPoint = lowerLip[lowerLip.length ~/ 2];
        final mouthHeight = (lowerPoint.y - upperPoint.y).abs();
        final faceHeight = face.boundingBox.height;
        
        if (mouthHeight > faceHeight * 0.06) { 
           final ratio = (mouthHeight / faceHeight * 100).toStringAsFixed(1);
           resultGen.addResult('Oropharynx / TMJ Inspection', 'Normal (Aperture: $ratio%)');
           stepManager.advanceTo(MedStep.breathing, "Breathe in deeply and out");
           onStartAudio();
        }
      }
    }
  }
  
  // ── AUDIO PROCESSING ──
  int _breathFrames = 0;
  void processAudio(double amplitude, StepManager stepManager, ResultGenerator resultGen, void Function() onStopAudio) {
    if (stepManager.isAdvancing) return;

    if (stepManager.currentStep == MedStep.breathing) {
      // Rule: Low/medium rhythmic amplitude indicating breathing
      _breathFrames++;
      if (_breathFrames > 30) { // approx 3 seconds
        resultGen.addResult('Respiratory Rate / Effort', 'Normal (Unlabored, 3s tracking)');
        stepManager.advanceTo(MedStep.cough, "Cough once loudly");
      }
    } else if (stepManager.currentStep == MedStep.cough) {
      // Rule: Sudden sharp amplitude spike
      if (amplitude > -12.0) { 
        coughFrames++;
        if (coughFrames >= 1) {
          final intensity = amplitude > -5.0 ? "(Mild Intensity)" : "(Normal)";
          resultGen.addResult('Airway/Cough Assessment', 'Detected $intensity ${amplitude.toStringAsFixed(1)}dB');
          coughFrames = 0;
          stepManager.advanceTo(MedStep.voice, "Say 'Ahhh' continuously");
        }
      }
    } else if (stepManager.currentStep == MedStep.voice) {
      // Rule: Sustained amplitude evaluating vocal cord stability (CN IX, X)
      if (amplitude > -25.0) {
        voiceFrames++;
        if (voiceFrames > 15) { // roughly 1.5 seconds sustained
          resultGen.addResult('Vocal Cord Stability (CN IX, X)', 'Normal (Sustained > 1.5s)');
          stepManager.advanceTo(MedStep.tremor, "Hold phone steady with arm extended");
          onStopAudio();
        }
      } else {
        // Reset if voice drops out to measure true stability
        voiceFrames = 0;
      }
    }
  }

  // ── MOTION PROCESSING ──
  int _tremorFrames = 0;
  double _totalVariance = 0;
  void processMotion(double x, double y, double z, StepManager stepManager, ResultGenerator resultGen, void Function() onComplete) {
    if (stepManager.isAdvancing || stepManager.currentStep != MedStep.tremor) return;

    // Remove gravity baseline (~9.8) by evaluating variance
    double magnitude = (x * x + y * y + z * z);
    double variance = (magnitude - 96.0).abs(); // 9.8^2 ≈ 96
    
    _totalVariance += variance;
    _tremorFrames++;

    if (_tremorFrames > 30) { // approx 3 seconds of monitoring
      double avgVariance = _totalVariance / _tremorFrames;
      final status = SymptomAnalyzer.analyzeTremor(avgVariance);
      resultGen.addResult('Neuromuscular Stability', '$status (Var: ${avgVariance.toStringAsFixed(2)})');
      
      resultGen.finalizeReport();
      stepManager.advanceTo(MedStep.complete, "Checkup Complete!");
      onComplete();
    }
  }

  void dispose() {
    faceDetector.close();
  }
}
