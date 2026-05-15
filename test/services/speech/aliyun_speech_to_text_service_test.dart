import 'dart:async';
import 'dart:typed_data';

import 'package:ai_chat/services/speech/aliyun_realtime_asr_client.dart';
import 'package:ai_chat/services/speech/aliyun_speech_to_text_service.dart';
import 'package:ai_chat/services/speech/speech_to_text_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpeechToTextService contract', () {
    test('start, partial, final, error, and close can be driven end to end',
        () async {
      final service = _FakeSpeechToTextService();
      final partials = <String>[];
      final finals = <String>[];
      final errors = <Object>[];

      final partialSub = service.partialResults.listen(partials.add);
      final finalSub = service.finalResults.listen(finals.add);
      final errorSub = service.errors.listen(errors.add);

      await service.startSession();
      await service.sendAudioFrame(Uint8List.fromList(const [1, 2, 3]));
      service.emitPartial('你好');
      service.emitFinal('你好世界');
      service.emitError(StateError('boom'));
      await service.finishSession();
      await service.close();

      await Future<void>.delayed(Duration.zero);

      expect(service.startCallCount, 1);
      expect(service.sendFrameCount, 1);
      expect(service.finishCallCount, 1);
      expect(service.closeCallCount, 1);
      expect(partials, ['你好']);
      expect(finals, ['你好世界']);
      expect(errors, hasLength(1));

      await partialSub.cancel();
      await finalSub.cancel();
      await errorSub.cancel();
    });

    test('aliyun service relays client partial final and error events', () async {
      final client = _FakeAliyunRealtimeAsrClient();
      final service = AliyunSpeechToTextService(client: client);
      final partials = <String>[];
      final finals = <String>[];
      final errors = <Object>[];

      final partialSub = service.partialResults.listen(partials.add);
      final finalSub = service.finalResults.listen(finals.add);
      final errorSub = service.errors.listen(errors.add);

      await service.startSession();
      await service.sendAudioFrame(Uint8List.fromList(const [4, 5, 6]));
      client.emit(const AliyunAsrEvent.partial('早上'));
      client.emit(const AliyunAsrEvent.partial('早上好'));
      client.emit(const AliyunAsrEvent.finalResult('早上好'));
      client.emitError(StateError('transport'));
      await Future<void>.delayed(Duration.zero);
      await service.finishSession();
      await service.close();

      await Future<void>.delayed(Duration.zero);

      expect(client.connectCallCount, 1);
      expect(client.sendFrameCount, 1);
      expect(client.finishCallCount, 1);
      expect(client.closeCallCount, 1);
      expect(partials, ['早上', '早上好']);
      expect(finals, ['早上好']);
      expect(errors, hasLength(1));

      await partialSub.cancel();
      await finalSub.cancel();
      await errorSub.cancel();
    });
  });
}

class _FakeSpeechToTextService implements SpeechToTextService {
  final StreamController<String> _partialController =
      StreamController<String>.broadcast();
  final StreamController<String> _finalController =
      StreamController<String>.broadcast();
  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast();

  int startCallCount = 0;
  int sendFrameCount = 0;
  int finishCallCount = 0;
  int closeCallCount = 0;

  @override
  Stream<Object> get errors => _errorController.stream;

  @override
  Stream<String> get finalResults => _finalController.stream;

  @override
  Stream<String> get partialResults => _partialController.stream;

  @override
  Future<void> close() async {
    closeCallCount += 1;
    await _partialController.close();
    await _finalController.close();
    await _errorController.close();
  }

  void emitError(Object error) {
    _errorController.add(error);
  }

  void emitFinal(String text) {
    _finalController.add(text);
  }

  void emitPartial(String text) {
    _partialController.add(text);
  }

  @override
  Future<void> finishSession() async {
    finishCallCount += 1;
  }

  @override
  Future<void> sendAudioFrame(Uint8List frame) async {
    sendFrameCount += 1;
  }

  @override
  Future<void> startSession() async {
    startCallCount += 1;
  }
}

class _FakeAliyunRealtimeAsrClient implements AliyunRealtimeAsrClient {
  final StreamController<AliyunAsrEvent> _eventController =
      StreamController<AliyunAsrEvent>.broadcast();
  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast();

  int connectCallCount = 0;
  int sendFrameCount = 0;
  int finishCallCount = 0;
  int closeCallCount = 0;

  @override
  Stream<AliyunAsrEvent> get events => _eventController.stream;

  @override
  Stream<Object> get errors => _errorController.stream;

  @override
  Future<void> close() async {
    closeCallCount += 1;
    await _eventController.close();
    await _errorController.close();
  }

  @override
  Future<void> connect() async {
    connectCallCount += 1;
  }

  void emit(AliyunAsrEvent event) {
    _eventController.add(event);
  }

  void emitError(Object error) {
    _errorController.add(error);
  }

  @override
  Future<void> finish() async {
    finishCallCount += 1;
  }

  @override
  Future<void> sendAudioFrame(Uint8List frame) async {
    sendFrameCount += 1;
  }
}
