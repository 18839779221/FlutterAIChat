import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../models/speech/speech_input_config.dart';
import '../models/speech/speech_input_state.dart';
import '../services/audio/audio_capture_service.dart';
import '../services/speech/speech_to_text_service.dart';

class VoiceInputController extends ChangeNotifier {
  final TextEditingController textController;
  final SpeechInputConfig? _speechInputConfig;
  final SpeechToTextService _speechToTextService;
  final AudioCaptureService _audioCaptureService;

  StreamSubscription<String>? _partialSubscription;
  StreamSubscription<String>? _finalSubscription;
  StreamSubscription<Object>? _errorSubscription;
  StreamSubscription<Uint8List>? _audioFrameSubscription;

  SpeechInputState _state;
  String _pendingFinalText = '';
  final List<String> _finalizedSegments = <String>[];
  TextSelection? _speechInsertionSelection;
  String _speechOriginalText = '';
  bool _isClosed = false;
  bool _resourcesReleased = false;

  VoiceInputController({
    required this.textController,
    required SpeechInputConfig? speechInputConfig,
    required SpeechToTextService speechToTextService,
    required AudioCaptureService audioCaptureService,
  })  : _speechInputConfig = speechInputConfig,
        _speechToTextService = speechToTextService,
        _audioCaptureService = audioCaptureService,
        _state = SpeechInputState(
          isConfigured: speechInputConfig?.isValid ?? false,
        );

  SpeechInputState get state => _state;

  @override
  void notifyListeners() {
    if (!_isClosed && hasListeners) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _isClosed = true;
    super.dispose();
  }

  /// Releases async speech/audio resources owned by this controller.
  Future<void> close() async {
    if (_resourcesReleased) {
      return;
    }
    await _disposeResources();
  }

  Future<void> pressStart() async {
    if (_isClosed) {
      throw StateError('voice_input_controller_closed');
    }
    final config = _speechInputConfig;
    if (config == null || !config.isValid) {
      _state = _state.copyWith(
        phase: SpeechInputPhase.error,
        errorMessage: 'speech_input_unavailable',
        isConfigured: false,
      );
      notifyListeners();
      return;
    }

    _state = _state.copyWith(
      phase: SpeechInputPhase.requestingPermission,
      clearErrorMessage: true,
      clearDraftRange: true,
      draftText: '',
      committedText: '',
      isConfigured: true,
    );
    notifyListeners();
    _pendingFinalText = '';
    _finalizedSegments.clear();
    _speechOriginalText = textController.text;
    _speechInsertionSelection = textController.selection.isValid
        ? textController.selection
        : TextSelection.collapsed(offset: textController.text.length);

    final granted = await _audioCaptureService.requestPermission();
    if (!granted) {
      _state = _state.copyWith(
        phase: SpeechInputPhase.error,
        errorMessage: 'microphone_permission_denied',
        hasPermission: false,
      );
      notifyListeners();
      return;
    }

    _state = _state.copyWith(
      phase: SpeechInputPhase.connecting,
      hasPermission: true,
      clearErrorMessage: true,
    );
    notifyListeners();

    await _partialSubscription?.cancel();
    await _finalSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _audioFrameSubscription?.cancel();

    _partialSubscription = _speechToTextService.partialResults.listen((text) {
      final draftText = _composeDraftText(partialText: text);
      _state = _state.copyWith(
        phase: SpeechInputPhase.listening,
        draftText: draftText,
      );
      _applySpeechTextToComposer(draftText);
      notifyListeners();
    });

    _finalSubscription = _speechToTextService.finalResults.listen((text) {
      final normalized = text.trim();
      if (normalized.isEmpty) {
        return;
      }
      _finalizedSegments.add(normalized);
      _pendingFinalText = _finalizedSegments.join();
      _state = _state.copyWith(
        phase: SpeechInputPhase.listening,
        draftText: _pendingFinalText,
      );
      _applySpeechTextToComposer(_pendingFinalText);
      notifyListeners();
    });

    _errorSubscription = _speechToTextService.errors.listen((_) {
      _state = _state.copyWith(
        phase: SpeechInputPhase.error,
        errorMessage: 'speech_input_failed',
      );
      notifyListeners();
    });

    await _speechToTextService.startSession();
    _audioFrameSubscription = _audioCaptureService.audioFrames.listen((frame) {
      unawaited(_speechToTextService.sendAudioFrame(frame));
    });
    await _audioCaptureService.start(sampleRate: config.sampleRate);
    _state = _state.copyWith(
      phase: SpeechInputPhase.listening,
      clearErrorMessage: true,
    );
    notifyListeners();
  }

  Future<void> releaseStop() async {
    if (_state.phase != SpeechInputPhase.listening &&
        _state.phase != SpeechInputPhase.connecting &&
        _state.phase != SpeechInputPhase.finalizing) {
      return;
    }

    _state = _state.copyWith(phase: SpeechInputPhase.finalizing);
    notifyListeners();
    await _audioCaptureService.stop();
    await _audioFrameSubscription?.cancel();
    _audioFrameSubscription = null;
    await _speechToTextService.finishSession();
    await Future<void>.delayed(Duration.zero);
    _commitFinalTranscript();
  }

  void _commitFinalTranscript() {
    final finalText = _pendingFinalText.trim();
    if (finalText.isEmpty) {
      _restoreOriginalComposerText();
    }

    _pendingFinalText = '';
    _finalizedSegments.clear();
    _speechOriginalText = '';
    _speechInsertionSelection = null;
    _state = _state.copyWith(
      phase: SpeechInputPhase.idle,
      draftText: '',
      committedText: finalText,
      clearDraftRange: true,
      clearErrorMessage: true,
    );
    notifyListeners();
  }

  Future<void> _disposeResources() async {
    if (_resourcesReleased) {
      return;
    }
    _resourcesReleased = true;
    await _audioFrameSubscription?.cancel();
    _audioFrameSubscription = null;
    await _partialSubscription?.cancel();
    _partialSubscription = null;
    await _finalSubscription?.cancel();
    _finalSubscription = null;
    await _errorSubscription?.cancel();
    _errorSubscription = null;
    await _speechToTextService.close();
    await _audioCaptureService.dispose();
  }

  String _composeDraftText({required String partialText}) {
    final normalized = partialText.trim();
    if (_finalizedSegments.isEmpty) {
      return normalized;
    }
    if (normalized.isEmpty) {
      return _finalizedSegments.join();
    }
    return '${_finalizedSegments.join()}$normalized';
  }

  void _applySpeechTextToComposer(String speechText) {
    final selection = _speechInsertionSelection;
    if (selection == null) {
      return;
    }

    final start = selection.start.clamp(0, _speechOriginalText.length);
    final end = selection.end.clamp(0, _speechOriginalText.length);
    final normalizedStart = start <= end ? start : end;
    final normalizedEnd = start <= end ? end : start;
    final nextText =
        _speechOriginalText.replaceRange(normalizedStart, normalizedEnd, speechText);
    final caretOffset = normalizedStart + speechText.length;
    _state = _state.copyWith(
      draftRangeStart: normalizedStart,
      draftRangeEnd: normalizedStart + speechText.length,
    );
    textController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: caretOffset),
    );
  }

  void _restoreOriginalComposerText() {
    final selection = _speechInsertionSelection;
    if (selection == null) {
      textController.text = _speechOriginalText;
      textController.selection = TextSelection.collapsed(
        offset: _speechOriginalText.length,
      );
      return;
    }
    textController.value = TextEditingValue(
      text: _speechOriginalText,
      selection: TextSelection.collapsed(offset: selection.start),
    );
  }
}
