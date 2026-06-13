import 'dart:async';
import 'dart:typed_data';

import 'package:ai_chat/controllers/composer_document_controller.dart';
import 'package:ai_chat/controllers/composer_text_editing_controller.dart';
import 'package:ai_chat/controllers/composer_voice_sync_controller.dart';
import 'package:ai_chat/controllers/voice_input_controller.dart';
import 'package:ai_chat/models/composer/composer_node.dart';
import 'package:ai_chat/models/speech/speech_input_config.dart';
import 'package:ai_chat/services/audio/audio_capture_service.dart';
import 'package:ai_chat/services/speech/speech_to_text_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ComposerVoiceSyncController', () {
    test('keeps persisted plain text stable while voice draft is active',
        () async {
      final voiceHarness = _VoiceHarness.create();
      final textController = ComposerTextEditingController()
        ..text = '帮我安排一下今天'
        ..selection = const TextSelection.collapsed(offset: 6);
      final composerController = ComposerDocumentController()
        ..setPlainText(textController.text);
      final syncController = ComposerVoiceSyncController(
        composerController: composerController,
        textController: textController,
        voiceController: voiceHarness.controller,
      );

      await voiceHarness.controller.pressStart();
      syncController.syncFromVoiceState();

      voiceHarness.speech.emitPartial('明天下午三点');
      await Future<void>.delayed(Duration.zero);
      syncController.syncFromVoiceState();

      expect(composerController.plainText, '帮我安排一下今天');
      expect(
        composerController.nodes.whereType<SpeechComposerNode>().single.visibleText,
        '明天下午三点',
      );
    });

    test('commits final speech transcript into plain text after session ends',
        () async {
      final voiceHarness = _VoiceHarness.create();
      final textController = ComposerTextEditingController()
        ..text = '帮我安排一下今天'
        ..selection = const TextSelection.collapsed(offset: 6);
      final composerController = ComposerDocumentController()
        ..setPlainText(textController.text);
      final syncController = ComposerVoiceSyncController(
        composerController: composerController,
        textController: textController,
        voiceController: voiceHarness.controller,
      );

      await voiceHarness.controller.pressStart();
      syncController.syncFromVoiceState();

      voiceHarness.speech.emitPartial('明天下午三点');
      await Future<void>.delayed(Duration.zero);
      syncController.syncFromVoiceState();

      voiceHarness.speech.emitFinal('明天下午三点开会');
      await voiceHarness.controller.releaseStop();
      await Future<void>.delayed(Duration.zero);
      syncController.syncFromVoiceState();

      expect(composerController.nodes.whereType<SpeechComposerNode>(), isEmpty);
      expect(composerController.plainText, '帮我安排一下明天下午三点开会今天');
    });
  });
}

class _VoiceHarness {
  final VoiceInputController controller;
  final _FakeSpeechToTextService speech;
  final _FakeAudioCaptureService audio;

  _VoiceHarness._({
    required this.controller,
    required this.speech,
    required this.audio,
  });

  factory _VoiceHarness.create() {
    final speech = _FakeSpeechToTextService();
    final audio = _FakeAudioCaptureService();
    final controller = VoiceInputController(
      textController: ComposerTextEditingController(),
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
    return _VoiceHarness._(
      controller: controller,
      speech: speech,
      audio: audio,
    );
  }
}

class _FakeSpeechToTextService implements SpeechToTextService {
  final StreamController<String> _partialController =
      StreamController<String>.broadcast();
  final StreamController<String> _finalController =
      StreamController<String>.broadcast();
  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast();

  @override
  Stream<Object> get errors => _errorController.stream;

  @override
  Stream<String> get finalResults => _finalController.stream;

  @override
  Stream<String> get partialResults => _partialController.stream;

  @override
  Future<void> close() async {
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
  Future<void> finishSession() async {}

  @override
  Future<void> sendAudioFrame(Uint8List frame) async {}

  @override
  Future<void> startSession() async {}
}

class _FakeAudioCaptureService implements AudioCaptureService {
  @override
  Stream<Uint8List> get audioFrames => const Stream<Uint8List>.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> start({required int sampleRate}) async {}

  @override
  Future<void> stop() async {}
}
