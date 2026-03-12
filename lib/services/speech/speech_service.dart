abstract class SpeechService {
  Future<bool> initialize();
  Future<void> startListening({
    required Function(String text) onResult,
    required Function(String message) onError,
  });
  Future<void> stopListening();
  bool get isListening;
}
