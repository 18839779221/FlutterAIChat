import 'dart:async';
import 'dart:typed_data';

import 'package:ai_chat/controllers/voice_input_controller.dart';
import 'package:ai_chat/models/speech/speech_input_config.dart';
import 'package:ai_chat/models/speech/speech_input_state.dart';
import 'package:ai_chat/services/audio/audio_capture_service.dart';
import 'package:ai_chat/services/speech/speech_to_text_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceInputController', () {
    test('returns configuration error when speech input is unavailable',
        () async {
      final controller = VoiceInputController(
        textController: TextEditingController(text: '已输入'),
        speechInputConfig: null,
        speechToTextService: _FakeSpeechToTextService(),
        audioCaptureService: _FakeAudioCaptureService(permissionGranted: true),
      );

      await controller.pressStart();

      expect(controller.state.phase, SpeechInputPhase.error);
      expect(controller.state.errorMessage, 'speech_input_unavailable');
      expect(controller.textController.text, '已输入');
    });

    test('returns permission error when microphone access is denied', () async {
      final controller = VoiceInputController(
        textController: TextEditingController(),
        speechInputConfig: const SpeechInputConfig(
          enabled: true,
          provider: 'aliyun',
          endpoint: 'wss://speech.example/ws',
          apiKey: 'speech-key',
          sampleRate: 16000,
          languageHints: ['zh', 'en'],
        ),
        speechToTextService: _FakeSpeechToTextService(),
        audioCaptureService: _FakeAudioCaptureService(permissionGranted: false),
      );

      await controller.pressStart();

      expect(controller.state.phase, SpeechInputPhase.error);
      expect(controller.state.errorMessage, 'microphone_permission_denied');
      expect(controller.state.hasPermission, isFalse);
    });

    test('updates active text field at cursor from partial results and keeps final transcript',
        () async {
      final speech = _FakeSpeechToTextService();
      final audio = _FakeAudioCaptureService(permissionGranted: true);
      final textController = TextEditingController(text: '帮我记一下 今天');
      textController.selection = const TextSelection.collapsed(offset: 5);
      final controller = VoiceInputController(
        textController: textController,
        speechInputConfig: const SpeechInputConfig(
          enabled: true,
          provider: 'aliyun',
          endpoint: 'wss://speech.example/ws',
          apiKey: 'speech-key',
          sampleRate: 16000,
          languageHints: ['zh', 'en'],
        ),
        speechToTextService: speech,
        audioCaptureService: audio,
      );

      await controller.pressStart();
      expect(controller.state.phase, SpeechInputPhase.listening);

      audio.emitFrame(Uint8List.fromList(const [1, 2, 3]));
      speech.emitPartial('明天上午');
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.draftText, '明天上午');
      expect(textController.text, '帮我记一下明天上午 今天');
      expect(textController.selection.baseOffset, 9);

      speech.emitFinal('明天上午十点开会');
      await controller.releaseStop();
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, SpeechInputPhase.idle);
      expect(controller.state.draftText, isEmpty);
      expect(textController.text, '帮我记一下明天上午十点开会 今天');
      expect(speech.finishCallCount, 1);
      expect(audio.stopCallCount, 1);
    });

    test('keeps earlier finalized speech when later partials arrive', () async {
      final speech = _FakeSpeechToTextService();
      final audio = _FakeAudioCaptureService(permissionGranted: true);
      final textController = TextEditingController(text: '帮我记一下 今天');
      textController.selection = const TextSelection.collapsed(offset: 5);
      final controller = VoiceInputController(
        textController: textController,
        speechInputConfig: const SpeechInputConfig(
          enabled: true,
          provider: 'aliyun',
          endpoint: 'wss://speech.example/ws',
          apiKey: 'speech-key',
          sampleRate: 16000,
          languageHints: ['zh', 'en'],
        ),
        speechToTextService: speech,
        audioCaptureService: audio,
      );

      await controller.pressStart();

      speech.emitPartial('明天上午十点');
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.draftText, '明天上午十点');

      speech.emitFinal('明天上午十点开会');
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.draftText, '明天上午十点开会');

      speech.emitPartial('然后提醒我带电脑');
      await Future<void>.delayed(Duration.zero);
      expect(
        controller.state.draftText,
        '明天上午十点开会然后提醒我带电脑',
      );

      speech.emitFinal('然后提醒我带电脑');
      await controller.releaseStop();
      await Future<void>.delayed(Duration.zero);

      expect(
        textController.text,
        '帮我记一下明天上午十点开会然后提醒我带电脑 今天',
      );
    });

    test('restores original text when released without final transcript', () async {
      final speech = _FakeSpeechToTextService();
      final audio = _FakeAudioCaptureService(permissionGranted: true);
      final textController = TextEditingController(text: '会前 ');
      textController.selection = const TextSelection.collapsed(offset: 3);
      final controller = VoiceInputController(
        textController: textController,
        speechInputConfig: const SpeechInputConfig(
          enabled: true,
          provider: 'aliyun',
          endpoint: 'wss://speech.example/ws',
          apiKey: 'speech-key',
          sampleRate: 16000,
          languageHints: ['zh', 'en'],
        ),
        speechToTextService: speech,
        audioCaptureService: audio,
      );

      await controller.pressStart();
      speech.emitPartial('提醒大家');
      await Future<void>.delayed(Duration.zero);
      expect(textController.text, '会前 提醒大家');

      await controller.releaseStop();
      await Future<void>.delayed(Duration.zero);

      expect(textController.text, '会前 ');
      expect(controller.state.draftText, isEmpty);
    });

    test('close disposes speech and audio resources once', () async {
      final speech = _FakeSpeechToTextService();
      final audio = _FakeAudioCaptureService(permissionGranted: true);
      final controller = VoiceInputController(
        textController: TextEditingController(),
        speechInputConfig: const SpeechInputConfig(
          enabled: true,
          provider: 'aliyun',
          endpoint: 'wss://speech.example/ws',
          apiKey: 'speech-key',
          sampleRate: 16000,
          languageHints: ['zh', 'en'],
        ),
        speechToTextService: speech,
        audioCaptureService: audio,
      );

      controller.dispose();
      await controller.close();
      await controller.close();

      expect(speech.closeCallCount, 1);
      expect(audio.disposeCallCount, 1);
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

class _FakeAudioCaptureService implements AudioCaptureService {
  final bool permissionGranted;
  final StreamController<Uint8List> _frameController =
      StreamController<Uint8List>.broadcast();

  int startCallCount = 0;
  int stopCallCount = 0;
  int disposeCallCount = 0;

  _FakeAudioCaptureService({
    required this.permissionGranted,
  });

  @override
  Stream<Uint8List> get audioFrames => _frameController.stream;

  @override
  Future<void> dispose() async {
    disposeCallCount += 1;
    await _frameController.close();
  }

  void emitFrame(Uint8List frame) {
    _frameController.add(frame);
  }

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> start({required int sampleRate}) async {
    startCallCount += 1;
  }

  @override
  Future<void> stop() async {
    stopCallCount += 1;
  }
}
