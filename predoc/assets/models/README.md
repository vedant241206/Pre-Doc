# YAMNet TFLite Model Directory

## Setup Instructions for Real Offline Audio Detection

Place the following files in this directory:

### 1. yamnet.tflite
- Download from: https://tfhub.dev/google/lite-model/yamnet/classification/tflite/1
- File to download: `lite-model_yamnet_classification_tflite_1.tflite`
- Rename to: `yamnet.tflite`

### 2. yamnet_class_map.csv
- Download from: https://raw.githubusercontent.com/tensorflow/models/master/research/audioset/yamnet/yamnet_class_map.csv
- Contains 521 audio class labels

## Integration

Once files are placed here, update `model_service.dart`:

```dart
import 'package:tflite_flutter/tflite_flutter.dart';

// Replace stub with:
_interpreter = await Interpreter.fromAsset('models/yamnet.tflite');
```

And update `audio_service.dart` to feed raw PCM audio chunks to the model.

## Thresholds Used

| Sound   | Threshold | YAMNet Class Index |
|---------|-----------|-------------------|
| Cough   | > 0.30    | ~74               |
| Sneeze  | > 0.35    | ~76               |
| Snore   | > 0.40    | ~73               |

Minimum 3 frames (chunks) required to count as an event.
Cooldown: 3 seconds between events.
