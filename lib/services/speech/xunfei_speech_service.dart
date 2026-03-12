import 'package:flutter/services.dart';
import 'speech_service.dart';

class XunfeiSpeechService implements SpeechService {
  static const MethodChannel _channel = MethodChannel('xunfei_speech');
  bool _isListening = false;

  @override
  bool get isListening => _isListening;

  @override
  Future<bool> initialize() async {
    try {
      final result = await _channel.invokeMethod('initialize', {
        'appId': '请替换为你的讯飞AppID',
      });
      return result == true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> startListening({
    required Function(String text) onResult,
    required Function(String message) onError,
  }) async {
    try {
      _isListening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onResult') {
          onResult(call.arguments as String);
        } else if (call.method == 'onError') {
          _isListening = false;
          final args = call.arguments;
          onError(args is String && args.isNotEmpty ? args : '语音识别失败，请重试');
        }
      });
      await _channel.invokeMethod('startListening');
    } catch (e) {
      _isListening = false;
      onError('语音识别启动失败：$e');
    }
  }

  @override
  Future<void> stopListening() async {
    try {
      await _channel.invokeMethod('stopListening');
    } finally {
      _isListening = false;
    }
  }
}
