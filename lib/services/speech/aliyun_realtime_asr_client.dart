import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../models/speech/speech_input_config.dart';

enum AliyunAsrEventType {
  partial,
  finalResult,
}

class AliyunAsrEvent {
  /// Semantic event type extracted from one provider message.
  final AliyunAsrEventType type;

  /// Human-readable transcript text carried by this event.
  final String text;

  const AliyunAsrEvent({
    required this.type,
    required this.text,
  });

  const AliyunAsrEvent.partial(String text)
      : this(
          type: AliyunAsrEventType.partial,
          text: text,
        );

  const AliyunAsrEvent.finalResult(String text)
      : this(
          type: AliyunAsrEventType.finalResult,
          text: text,
        );
}

/// Narrow transport client used by the higher-level Aliyun speech service.
abstract class AliyunRealtimeAsrClient {
  /// Parsed provider events emitted from the underlying realtime session.
  Stream<AliyunAsrEvent> get events;

  /// Transport- or provider-level errors for the active session.
  Stream<Object> get errors;

  /// Opens the realtime ASR session.
  Future<void> connect();

  /// Sends one encoded audio frame to the provider.
  Future<void> sendAudioFrame(Uint8List frame);

  /// Signals that the caller has finished sending audio for this session.
  Future<void> finish();

  /// Releases any transport resources held by the client.
  Future<void> close();
}

class AliyunRealtimeAsrMessageParser {
  const AliyunRealtimeAsrMessageParser();

  AliyunAsrEvent? parseMessage(Map<String, dynamic> message) {
    final header = message['header'];
    if (header is! Map) {
      return null;
    }
    final event = (header['event'] as String? ?? '').trim();
    if (event != 'result-generated') {
      return null;
    }

    final payload = message['payload'];
    if (payload is! Map) {
      return null;
    }
    final output = payload['output'];
    if (output is! Map) {
      return null;
    }
    final sentence = output['sentence'];
    if (sentence is! Map) {
      return null;
    }

    final text = (sentence['text'] as String? ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
    final isFinal = sentence['sentence_end'] == true;
    return isFinal
        ? AliyunAsrEvent.finalResult(text)
        : AliyunAsrEvent.partial(text);
  }
}

typedef AliyunWebSocketConnector =
    Future<WebSocket> Function(
      String url, {
      Map<String, dynamic>? headers,
    });

class DashScopeAliyunRealtimeAsrClient implements AliyunRealtimeAsrClient {
  final SpeechInputConfig _config;
  final AliyunRealtimeAsrMessageParser _parser;
  final AliyunWebSocketConnector _connector;
  final StreamController<AliyunAsrEvent> _eventController =
      StreamController<AliyunAsrEvent>.broadcast();
  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast();
  final Random _random = Random();

  StreamSubscription<dynamic>? _socketSubscription;
  WebSocket? _socket;
  String? _taskId;
  bool _isClosed = false;

  DashScopeAliyunRealtimeAsrClient({
    required SpeechInputConfig config,
    AliyunRealtimeAsrMessageParser parser =
        const AliyunRealtimeAsrMessageParser(),
    AliyunWebSocketConnector? connector,
  })  : _config = config,
        _parser = parser,
        _connector = connector ?? _defaultConnector;

  @override
  Stream<AliyunAsrEvent> get events => _eventController.stream;

  @override
  Stream<Object> get errors => _errorController.stream;

  @override
  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    await _socketSubscription?.cancel();
    await _socket?.close();
    _socket = null;
    await _eventController.close();
    await _errorController.close();
  }

  @override
  Future<void> connect() async {
    if (_isClosed) {
      throw StateError('aliyun_asr_client_closed');
    }
    if (_socket != null) {
      return;
    }

    final socket = await _connector(
      _config.endpoint,
      headers: {
        'Authorization': 'Bearer ${_config.apiKey}',
      },
    );
    _socket = socket;
    _socketSubscription = socket.listen(
      _handleSocketMessage,
      onError: _errorController.add,
      onDone: () {
        if (!_isClosed) {
          _errorController.add(StateError('aliyun_asr_socket_closed'));
        }
      },
      cancelOnError: false,
    );

    _taskId = _generateTaskId();
    socket.add(
      jsonEncode({
        'header': {
          'action': 'run-task',
          'task_id': _taskId,
          'streaming': 'duplex',
        },
        'payload': {
          'task_group': 'audio',
          'task': 'asr',
          'function': 'recognition',
          'model': 'paraformer-realtime-v2',
          'parameters': {
            'format': 'pcm',
            'sample_rate': _config.sampleRate,
            'language_hints': _config.languageHints,
          },
          'input': {},
        },
      }),
    );
  }

  @override
  Future<void> finish() async {
    final socket = _socket;
    final taskId = _taskId;
    if (socket == null || taskId == null) {
      return;
    }
    socket.add(
      jsonEncode({
        'header': {
          'action': 'finish-task',
          'task_id': taskId,
          'streaming': 'duplex',
        },
        'payload': {
          'input': {},
        },
      }),
    );
  }

  @override
  Future<void> sendAudioFrame(Uint8List frame) async {
    final socket = _socket;
    if (socket == null) {
      throw StateError('aliyun_asr_socket_not_connected');
    }
    socket.add(frame);
  }

  String _generateTaskId() {
    final randomHex = List<String>.generate(
      24,
      (_) => _random.nextInt(16).toRadixString(16),
      growable: false,
    ).join();
    final millis = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return '$millis$randomHex';
  }

  void _handleSocketMessage(dynamic rawMessage) {
    if (rawMessage is! String) {
      return;
    }
    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final header = decoded['header'];
      if (header is Map) {
        final eventName = (header['event'] as String? ?? '').trim();
        if (eventName == 'task-failed') {
          _errorController.add(
            StateError(
              (header['error_message'] as String? ?? 'aliyun_asr_task_failed')
                  .trim(),
            ),
          );
          return;
        }
      }

      final parsed = _parser.parseMessage(decoded);
      if (parsed != null) {
        _eventController.add(parsed);
      }
    } catch (error) {
      _errorController.add(error);
    }
  }

  static Future<WebSocket> _defaultConnector(
    String url, {
    Map<String, dynamic>? headers,
  }) {
    return WebSocket.connect(url, headers: headers);
  }
}
