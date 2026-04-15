import 'dart:async';

/// Coalesces streamed assistant deltas into separate UI and persistence flushes.
class AssistantStreamOutputBuffer {
  final FutureOr<void> Function(String text) _onUiFlush;
  final FutureOr<void> Function(String text) _onPersistFlush;
  final Duration _uiFlushInterval;
  final Duration _persistFlushInterval;
  final StringBuffer _buffer = StringBuffer();

  Timer? _uiTimer;
  Timer? _persistTimer;
  String _lastUiFlushedText = '';
  String _lastPersistedText = '';
  bool _isClosed = false;

  AssistantStreamOutputBuffer({
    required FutureOr<void> Function(String text) onUiFlush,
    required FutureOr<void> Function(String text) onPersistFlush,
    Duration uiFlushInterval = const Duration(milliseconds: 33),
    Duration persistFlushInterval = const Duration(milliseconds: 250),
  })  : _onUiFlush = onUiFlush,
        _onPersistFlush = onPersistFlush,
        _uiFlushInterval = uiFlushInterval,
        _persistFlushInterval = persistFlushInterval;

  /// Appends a new streamed delta and schedules coalesced downstream updates.
  void onDelta(String chunk) {
    if (_isClosed || chunk.isEmpty) {
      return;
    }

    _buffer.write(chunk);
    _scheduleUiFlush();
    _schedulePersistFlush();
  }

  /// Flushes all accumulated text and closes the buffer for further deltas.
  Future<void> finish() async {
    if (_isClosed) {
      return;
    }

    _close();
    await _flushUi(force: true);
    await _flushPersist(force: true);
  }

  /// Flushes the latest partial text before closing the buffer.
  Future<void> cancel() async {
    await finish();
  }

  /// Releases timers without forcing another flush.
  void dispose() {
    if (_isClosed) {
      return;
    }
    _close();
  }

  String get fullText => _buffer.toString();

  void _scheduleUiFlush() {
    if (_uiTimer != null || _isClosed) {
      return;
    }

    _uiTimer = Timer(_uiFlushInterval, () async {
      _uiTimer = null;
      await _flushUi();
    });
  }

  void _schedulePersistFlush() {
    if (_persistTimer != null || _isClosed) {
      return;
    }

    _persistTimer = Timer(_persistFlushInterval, () async {
      _persistTimer = null;
      await _flushPersist();
    });
  }

  Future<void> _flushUi({bool force = false}) async {
    final text = fullText;
    if (!force && text == _lastUiFlushedText) {
      return;
    }
    if (text.isEmpty && !force) {
      return;
    }

    _lastUiFlushedText = text;
    await _onUiFlush(text);
  }

  Future<void> _flushPersist({bool force = false}) async {
    final text = fullText;
    if (!force && text == _lastPersistedText) {
      return;
    }
    if (text.isEmpty && !force) {
      return;
    }

    _lastPersistedText = text;
    await _onPersistFlush(text);
  }

  void _close() {
    if (_isClosed) {
      return;
    }

    _isClosed = true;
    _uiTimer?.cancel();
    _persistTimer?.cancel();
    _uiTimer = null;
    _persistTimer = null;
  }
}
