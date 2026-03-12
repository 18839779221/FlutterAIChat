import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/speech_providers.dart';

class SpeechController {
  final Ref ref;
  bool _isStarting = false;
  bool _pendingStopAfterStart = false;
  bool _isStoppingByUser = false;

  SpeechController(this.ref);

  Future<bool> initialize() async {
    if (ref.read(speechInitializedProvider)) {
      return true;
    }
    final service = ref.read(speechServiceProvider);
    final initialized = await service.initialize();
    ref.read(speechInitializedProvider.notifier).state = initialized;
    if (!initialized) {
      ref.read(speechErrorProvider.notifier).state = '麦克风或语音服务初始化失败';
    }
    return initialized;
  }

  Future<bool> startListening() async {
    if (ref.read(isListeningProvider) || _isStarting) {
      return true;
    }

    ref.read(speechErrorProvider.notifier).state = null;
    final initialized = await initialize();
    if (!initialized) {
      return false;
    }

    final service = ref.read(speechServiceProvider);
    _isStarting = true;
    _pendingStopAfterStart = false;
    ref.read(isListeningProvider.notifier).state = true;
    ref.read(speechTextProvider.notifier).state = '';

    try {
      await service.startListening(
        onResult: (text) {
          if (text.trim().isNotEmpty) {
            ref.read(speechTextProvider.notifier).state = text;
          }
        },
        onError: (message) {
          if (_isStoppingByUser || !ref.read(isListeningProvider)) {
            return;
          }
          ref.read(speechErrorProvider.notifier).state = message;
          ref.read(isListeningProvider.notifier).state = false;
        },
      );
      return true;
    } catch (e) {
      ref.read(speechErrorProvider.notifier).state = '语音识别启动失败：$e';
      ref.read(isListeningProvider.notifier).state = false;
      return false;
    } finally {
      _isStarting = false;
      if (_pendingStopAfterStart) {
        _isStoppingByUser = true;
        try {
          await service.stopListening();
        } finally {
          _isStoppingByUser = false;
          _pendingStopAfterStart = false;
          ref.read(isListeningProvider.notifier).state = false;
        }
      }
    }
  }

  Future<void> stopListening() async {
    if (!ref.read(isListeningProvider) && !_isStarting) {
      return;
    }
    if (_isStarting) {
      _pendingStopAfterStart = true;
    }

    final service = ref.read(speechServiceProvider);
    _isStoppingByUser = true;
    try {
      await service.stopListening();
    } finally {
      _isStoppingByUser = false;
      ref.read(isListeningProvider.notifier).state = false;
    }
  }

  void clearError() {
    ref.read(speechErrorProvider.notifier).state = null;
  }
}

final speechControllerProvider = Provider<SpeechController>((ref) {
  return SpeechController(ref);
});
