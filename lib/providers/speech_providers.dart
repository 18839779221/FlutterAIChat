import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/speech/speech_service.dart';
import '../services/speech/xunfei_speech_service.dart';

final speechServiceProvider = Provider<SpeechService>((ref) {
  return XunfeiSpeechService();
});

final isListeningProvider = StateProvider<bool>((ref) => false);

final speechTextProvider = StateProvider<String>((ref) => '');

final speechInitializedProvider = StateProvider<bool>((ref) => false);

final speechErrorProvider = StateProvider<String?>((ref) => null);
