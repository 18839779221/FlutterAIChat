import 'package:speech_to_text/speech_to_text.dart';
import 'speech_service.dart';

class SpeechToTextService implements SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;

  @override
  bool get isListening => _isListening;

  @override
  Future<bool> initialize() async {
    try {
      return await _speech.initialize();
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> startListening({
    required Function(String text) onResult,
    required Function(String message) onError,
  }) async {
    if (!_speech.isAvailable) {
      final initialized = await initialize();
      if (!initialized) {
        onError('语音识别初始化失败，请检查麦克风权限');
        return;
      }
    }

    _isListening = true;
    await _speech
        .listen(
      onResult: (result) => onResult(result.recognizedWords),
      localeId: 'zh_CN',
      listenOptions: SpeechListenOptions(
        cancelOnError: true,
        onDevice: false,
      ),
    )
        .catchError((error) {
      _isListening = false;
      onError('语音识别出错：$error');
    });
  }

  @override
  Future<void> stopListening() async {
    await _speech.stop();
    _isListening = false;
  }
}
