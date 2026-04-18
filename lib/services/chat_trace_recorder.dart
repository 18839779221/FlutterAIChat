import '../models/trace/chat_trace_event.dart';
import '../utils/logger.dart';

/// Records chat trace events and optionally emits structured logs for observability.
class ChatTraceRecorder {
  /// Receives structured trace entries when events are recorded.
  final void Function(Map<String, dynamic> entry)? logger;

  final Map<String, List<ChatTraceEvent>> _eventsByTurn = {};
  int _turnCounter = 0;

  ChatTraceRecorder({this.logger});

  /// Returns a new unique identifier that groups all events related to a single turn.
  String newTurnId() {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    _turnCounter += 1;
    return 'turn_${timestamp}_$_turnCounter';
  }

  /// Records an event for the provided turn, adds it to the internal history, and logs it.
  void record({
    required String turnId,
    required ChatTraceStage stage,
    required ChatTraceStatus status,
    String? summary,
    Map<String, dynamic>? data,
    DateTime? timestamp,
  }) {
    final event = ChatTraceEvent(
      turnId: turnId,
      stage: stage,
      status: status,
      summary: summary,
      data: data,
      timestamp: timestamp,
    );
    _eventsByTurn.putIfAbsent(turnId, () => []).add(event);
    _emitLog(event);
  }

  /// Returns all trace events recorded for the provided turn, in chronological order.
  List<ChatTraceEvent> eventsForTurn(String turnId) {
    final events = _eventsByTurn[turnId];
    if (events == null) {
      return const [];
    }
    return List.unmodifiable(events);
  }

  /// Formats a structured trace entry into a stable single-line log payload.
  String formatLogLine(Map<String, dynamic> entry) {
    final parts = <String>[];
    void addPart(String key, dynamic value) {
      if (value == null) {
        return;
      }
      parts.add('$key=${_formatValue(value)}');
    }

    addPart('turnId', entry['turnId']);
    addPart('stage', entry['stage']);
    addPart('status', entry['status']);
    addPart('timestamp', entry['timestamp']);
    addPart('summary', entry['summary']);

    final data = entry['data'];
    if (data is Map<String, dynamic>) {
      final flattened = <String, dynamic>{};
      _flattenMap(flattened, '', _sanitizeMap(data));
      final sortedKeys = flattened.keys.toList()..sort();
      for (final key in sortedKeys) {
        addPart(key, flattened[key]);
      }
    }

    final line = parts.join(' ');
    if (line.length <= _maxLogLineLength) {
      return line;
    }
    return '${line.substring(0, _maxLogLineLength - 3)}...';
  }

  void _emitLog(ChatTraceEvent event) {
    final entry = <String, dynamic>{
      'turnId': event.turnId,
      'stage': event.stage.name,
      'status': event.status.name,
      'timestamp': event.timestamp.toIso8601String(),
    };
    if (event.summary != null) {
      entry['summary'] = event.summary;
    }
    if (event.data != null) {
      entry['data'] = _sanitizeMap(event.data!);
    }
    final logger = this.logger;
    if (logger != null) {
      logger(entry);
      return;
    }
    final traceData = entry['data'] is Map<String, dynamic>
        ? entry['data'] as Map<String, dynamic>
        : null;
    Logger.trace(
      'ChatTrace',
      '${event.stage.name}.${event.status.name}${event.summary == null ? '' : ' ${event.summary}'}',
      data: {
        'turnId': event.turnId,
        ...?traceData,
      },
    );
  }

  static const _sensitiveKeys = {'apikey', 'authorization', 'api_key'};
  static const _maxPreviewValueLength = 72;
  static const _maxLogLineLength = 300;

  Map<String, dynamic> _sanitizeMap(Map<String, dynamic> source) {
    final sanitized = <String, dynamic>{};
    source.forEach((key, value) {
      sanitized[key] = _sanitizeValue(key, value);
    });
    return sanitized;
  }

  dynamic _sanitizeValue(String key, dynamic value) {
    if (value is Map<String, dynamic>) {
      return _sanitizeMap(value);
    }
    if (value is List) {
      return value.map((item) => _sanitizeValue(key, item)).toList();
    }
    if (_sensitiveKeys.contains(key.toLowerCase())) {
      return 'REDACTED';
    }
    if (value is String) {
      return _truncateValue(value);
    }
    return value;
  }

  void _flattenMap(
    Map<String, dynamic> target,
    String prefix,
    Map<String, dynamic> source,
  ) {
    source.forEach((key, value) {
      final flattenedKey = prefix.isEmpty ? key : '$prefix.$key';
      if (value is Map<String, dynamic>) {
        _flattenMap(target, flattenedKey, value);
        return;
      }
      target[flattenedKey] = value;
    });
  }

  String _formatValue(dynamic value) {
    if (value is List) {
      final joined = value.map(_formatValue).join(',');
      return '[${_truncateValue(joined)}]';
    }
    return _truncateValue(value.toString());
  }

  String _truncateValue(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= _maxPreviewValueLength) {
      return normalized;
    }
    return '${normalized.substring(0, _maxPreviewValueLength - 3)}...';
  }
}
