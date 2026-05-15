import 'dart:typed_data';

/// Abstracts microphone permission and realtime audio frame capture.
abstract class AudioCaptureService {
  /// Encoded audio frames emitted while the microphone capture is active.
  Stream<Uint8List> get audioFrames;

  /// Requests microphone access for the current runtime platform.
  Future<bool> requestPermission();

  /// Starts capturing audio frames using the requested sample rate.
  Future<void> start({required int sampleRate});

  /// Stops audio capture for the current session.
  Future<void> stop();

  /// Releases any recorder resources held by the implementation.
  Future<void> dispose();
}
