import 'package:ai_chat/utils/logger.dart';

typedef BootstrapStartupLogEmitter =
    void Function({
      required String name,
      required int elapsedMsSinceStart,
      Object? error,
    });

typedef BootstrapStartupNowFactory = DateTime Function();

/// Buffers cold-start timing anchors until the logger is ready, then emits
/// each milestone exactly once with a shared elapsed clock.
class BootstrapStartupProbe {
  BootstrapStartupProbe({
    BootstrapStartupNowFactory? createNow,
    BootstrapStartupLogEmitter? emit,
  })  : _createNow = createNow ?? DateTime.now,
        _emit = emit ?? _defaultEmit;

  final BootstrapStartupNowFactory _createNow;
  final BootstrapStartupLogEmitter _emit;
  DateTime? _startedAt;
  final List<_PendingBootstrapEvent> _pendingEvents = <_PendingBootstrapEvent>[];
  final Set<String> _emittedNames = <String>{};
  bool _loggerAttached = false;

  void attachLogger() {
    if (_loggerAttached) {
      return;
    }
    _loggerAttached = true;
    for (final event in _pendingEvents) {
      _emitEvent(event);
    }
    _pendingEvents.clear();
  }

  void mark(String name) {
    final event = _PendingBootstrapEvent(
      name: name,
      elapsedMsSinceStart: _elapsedMsSinceStart(),
    );
    _record(event);
  }

  void markFailed(Object error) {
    final event = _PendingBootstrapEvent(
      name: 'bootstrap.failed',
      elapsedMsSinceStart: _elapsedMsSinceStart(),
      error: error,
    );
    _record(event);
  }

  int _elapsedMsSinceStart() {
    final now = _createNow();
    final startedAt = _startedAt;
    if (startedAt == null) {
      _startedAt = now;
      return 0;
    }
    return now.difference(startedAt).inMilliseconds;
  }

  void _record(_PendingBootstrapEvent event) {
    if (_emittedNames.contains(event.name)) {
      return;
    }
    _emittedNames.add(event.name);
    if (_loggerAttached) {
      _emitEvent(event);
      return;
    }
    _pendingEvents.add(event);
  }

  void _emitEvent(_PendingBootstrapEvent event) {
    _emit(
      name: event.name,
      elapsedMsSinceStart: event.elapsedMsSinceStart,
      error: event.error,
    );
  }

  static void _defaultEmit({
    required String name,
    required int elapsedMsSinceStart,
    Object? error,
  }) {
    Logger.runtime(
      'BootstrapStartup',
      name,
      data: {
        'elapsedMsSinceStart': elapsedMsSinceStart,
        if (error != null) 'error': error,
      },
      level: error == null ? LogLevel.info : LogLevel.error,
    );
  }
}

class _PendingBootstrapEvent {
  const _PendingBootstrapEvent({
    required this.name,
    required this.elapsedMsSinceStart,
    this.error,
  });

  final String name;
  final int elapsedMsSinceStart;
  final Object? error;
}
