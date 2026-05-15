import 'dart:async';
import 'dart:typed_data';

import 'package:ai_chat/services/audio/audio_capture_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioCaptureService contract', () {
    test('fake implementation can grant permission and publish frames',
        () async {
      final service = _FakeAudioCaptureService();
      final frames = <Uint8List>[];

      final subscription = service.audioFrames.listen(frames.add);

      final granted = await service.requestPermission();
      await service.start(sampleRate: 16000);
      service.emitFrame(Uint8List.fromList(const [1, 2, 3, 4]));
      await service.stop();
      await service.dispose();

      expect(granted, isTrue);
      expect(service.startCallCount, 1);
      expect(service.stopCallCount, 1);
      expect(frames, hasLength(1));
      expect(frames.single, Uint8List.fromList(const [1, 2, 3, 4]));

      await subscription.cancel();
    });
  });
}

class _FakeAudioCaptureService implements AudioCaptureService {
  final StreamController<Uint8List> _controller =
      StreamController<Uint8List>.broadcast();

  int startCallCount = 0;
  int stopCallCount = 0;

  @override
  Stream<Uint8List> get audioFrames => _controller.stream;

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  void emitFrame(Uint8List frame) {
    _controller.add(frame);
  }

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> start({required int sampleRate}) async {
    startCallCount += 1;
  }

  @override
  Future<void> stop() async {
    stopCallCount += 1;
  }
}
