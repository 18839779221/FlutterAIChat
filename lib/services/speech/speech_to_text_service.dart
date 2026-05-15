import 'dart:typed_data';

/// Provider-agnostic contract for realtime speech-to-text sessions.
abstract class SpeechToTextService {
  /// Partial recognition updates emitted while the user is still speaking.
  Stream<String> get partialResults;

  /// Final recognition results emitted after the session is finalized.
  Stream<String> get finalResults;

  /// Provider or transport errors surfaced during one active session.
  Stream<Object> get errors;

  /// Starts one realtime recognition session.
  Future<void> startSession();

  /// Sends one encoded audio frame to the active recognition session.
  Future<void> sendAudioFrame(Uint8List frame);

  /// Signals that no more audio frames will be sent for the current session.
  Future<void> finishSession();

  /// Releases any session or transport resources held by this service.
  Future<void> close();
}
