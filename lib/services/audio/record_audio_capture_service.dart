import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'audio_capture_service.dart';

class RecordAudioCaptureService implements AudioCaptureService {
  final AudioRecorder _recorder;
  final StreamController<Uint8List> _audioFramesController =
      StreamController<Uint8List>.broadcast();

  StreamSubscription<Uint8List>? _recordingSubscription;

  RecordAudioCaptureService({
    AudioRecorder? recorder,
  }) : _recorder = recorder ?? AudioRecorder();

  @override
  Stream<Uint8List> get audioFrames => _audioFramesController.stream;

  @override
  Future<void> dispose() async {
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;
    await _recorder.dispose();
    await _audioFramesController.close();
  }

  @override
  Future<bool> requestPermission() {
    return _recorder.hasPermission();
  }

  @override
  Future<void> start({required int sampleRate}) async {
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;

    final stream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        numChannels: 1,
        sampleRate: sampleRate,
      ),
    );
    _recordingSubscription = stream.listen(_audioFramesController.add);
  }

  @override
  Future<void> stop() async {
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;
    await _recorder.stop();
  }
}
