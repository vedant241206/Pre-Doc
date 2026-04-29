// AppServices — Day 8
//
// Module-level singletons shared across all screens.
// Both HomeScreen and SettingsScreen import from here to ensure
// they talk to the SAME ContinuousAudioService instance.

import 'services/model_service.dart';
import 'services/continuous_audio_service.dart';

/// Shared ModelService — loads YAMNet once, reused everywhere.
final ModelService appModelService = ModelService();

/// Shared ContinuousAudioService — single mic stream, single event bus.
final ContinuousAudioService appContinuousAudio =
    ContinuousAudioService(appModelService);
