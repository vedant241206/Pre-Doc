import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class ModelService {
  Interpreter? _audioInterpreter;
  Interpreter? _faceInterpreter;
  List<String> _yamnetLabels = [];

  bool get isLoaded => _audioInterpreter != null && _faceInterpreter != null;

  Future<void> loadModels() async {
    if (isLoaded) return;
    try {
      debugPrint('[ModelService] Loading models...');
      final options = InterpreterOptions()..threads = 2;

      _audioInterpreter = await Interpreter.fromAsset(
        'assets/models/yamnet.tflite',
        options: options,
      );
      debugPrint('[ModelService] YAMNet loaded ✓');

      _faceInterpreter = await Interpreter.fromAsset(
        'assets/models/mobilefacenet.tflite',
        options: options,
      );
      debugPrint('[ModelService] MobileFaceNet loaded ✓');

      // Load YAMNet class labels
      final labelData =
          await rootBundle.loadString('assets/models/yamnet_class_map.csv');
      final lines = labelData.split('\n');
      _yamnetLabels = lines
          .skip(1)
          .where((l) => l.trim().isNotEmpty)
          .map((l) {
            final parts = l.split(',');
            return parts.length >= 3 ? parts[2].trim() : 'Unknown';
          })
          .toList();
      debugPrint(
          '[ModelService] Labels loaded: ${_yamnetLabels.length} classes');

      // ── Dummy inference smoke-test ──
      debugPrint('[ModelService] Running dummy inference smoke-test...');
      final dummyAudio = Float32List(15600); // all zeros
      final testOutput = runAudioInference(dummyAudio);
      debugPrint(
          '[ModelService] Dummy inference output: ${testOutput.length} classes. '
          'Top: ${_topEntries(testOutput, 3)}');

      debugPrint('[ModelService] Model loaded and verified ✓');
    } catch (e) {
      debugPrint('[ModelService] ERROR loading models: $e');
    }
  }

  /// Run YAMNet inference on a Float32 PCM chunk (exactly 15600 samples).
  Map<String, double> runAudioInference(Float32List floatAudio) {
    if (_audioInterpreter == null) {
      debugPrint('[ModelService] runAudioInference called but model not loaded');
      return {};
    }

    try {
      final inputBuffer = Float32List(15600);
      final copyLen =
          floatAudio.length < 15600 ? floatAudio.length : 15600;
      for (int i = 0; i < copyLen; i++) {
        inputBuffer[i] = floatAudio[i];
      }

      // YAMNet expects shape [15600] input, [1, 521] output
      final input = [inputBuffer]; // wrap as list for interpreter
      final output = [List<double>.filled(521, 0.0)];

      _audioInterpreter!.run(input, output);

      final results = <String, double>{};
      final probs = output[0];

      for (int i = 0; i < probs.length; i++) {
        if (probs[i] > 0.01 && i < _yamnetLabels.length) {
          results[_yamnetLabels[i]] = probs[i];
        }
      }

      // Print top detections
      final top = _topEntries(results, 5);
      debugPrint('[ModelService] Inference output: $top');

      // Basic detection check
      _checkDetections(results);

      return results;
    } catch (e) {
      debugPrint('[ModelService] YAMNet inference error: $e');
      return {};
    }
  }

  /// Checks specific health sounds and logs them.
  void _checkDetections(Map<String, double> results) {
    for (final entry in results.entries) {
      final label = entry.key.toLowerCase();
      final prob = entry.value;

      if (label.contains('cough') && prob > 0.3) {
        debugPrint('[ModelService] 🤧 Cough detected! probability=$prob');
      }
      if (label.contains('sneeze') && prob > 0.3) {
        debugPrint('[ModelService] 🤧 Sneeze detected! probability=$prob');
      }
      if (label.contains('snore') && prob > 0.3) {
        debugPrint('[ModelService] 😴 Snore detected! probability=$prob');
      }

      // Print any score above 0.3 for debugging
      if (prob > 0.3) {
        debugPrint('[ModelService] HIGH PROB → "$label": $prob');
      }
    }
  }

  /// Run MobileFaceNet to get a 192-d embedding.
  /// Input: nested List [1][112][112][3] normalised to -1..1
  List<double> getFaceEmbedding(List inputImageNested) {
    if (_faceInterpreter == null) {
      debugPrint('[ModelService] getFaceEmbedding called but model not loaded');
      return [];
    }

    try {
      final output = [List<double>.filled(192, 0.0)];
      _faceInterpreter!.run(inputImageNested, output);
      final embedding = output[0];
      debugPrint(
          '[ModelService] Face embedding: ${embedding.length} dims, '
          'first 5: ${embedding.take(5).map((v) => v.toStringAsFixed(4)).toList()}');
      return embedding;
    } catch (e) {
      debugPrint('[ModelService] FaceNet inference error: $e');
      return [];
    }
  }

  /// Returns a string of the top-N entries from a map.
  String _topEntries(Map<String, double> map, int n) {
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .take(n)
        .map((e) => '"${e.key}": ${e.value.toStringAsFixed(3)}')
        .join(', ');
  }

  void dispose() {
    _audioInterpreter?.close();
    _faceInterpreter?.close();
    debugPrint('[ModelService] Disposed');
  }
}
