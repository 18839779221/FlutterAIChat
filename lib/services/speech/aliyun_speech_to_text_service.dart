import 'dart:async';
import 'dart:typed_data';

import 'aliyun_realtime_asr_client.dart';
import 'speech_to_text_service.dart';

class AliyunSpeechToTextService implements SpeechToTextService {
  final AliyunRealtimeAsrClient _client;
  final StreamController<String> _partialController =
      StreamController<String>.broadcast();
  final StreamController<String> _finalController =
      StreamController<String>.broadcast();
  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast();

  StreamSubscription<AliyunAsrEvent>? _eventSubscription;
  StreamSubscription<Object>? _errorSubscription;
  bool _sessionStarted = false;
  bool _isClosed = false;

  AliyunSpeechToTextService({
    required AliyunRealtimeAsrClient client,
  }) : _client = client;

  @override
  Stream<Object> get errors => _errorController.stream;

  @override
  Stream<String> get finalResults => _finalController.stream;

  @override
  Stream<String> get partialResults => _partialController.stream;

  @override
  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    await _eventSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _client.close();
    await _partialController.close();
    await _finalController.close();
    await _errorController.close();
  }

  @override
  Future<void> finishSession() async {
    if (!_sessionStarted || _isClosed) {
      return;
    }
    await _client.finish();
  }

  @override
  Future<void> sendAudioFrame(Uint8List frame) async {
    if (!_sessionStarted || _isClosed) {
      throw StateError('speech_session_not_started');
    }
    await _client.sendAudioFrame(frame);
  }

  @override
  Future<void> startSession() async {
    if (_isClosed) {
      throw StateError('speech_service_closed');
    }
    if (_sessionStarted) {
      return;
    }

    _eventSubscription = _client.events.listen(_handleEvent);
    _errorSubscription = _client.errors.listen(_errorController.add);
    await _client.connect();
    _sessionStarted = true;
  }

  void _handleEvent(AliyunAsrEvent event) {
    switch (event.type) {
      case AliyunAsrEventType.partial:
        _partialController.add(event.text);
        break;
      case AliyunAsrEventType.finalResult:
        _finalController.add(event.text);
        break;
    }
  }
}
