import 'package:ai_chat/models/debug/streaming_trace_snapshot.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stable runtime trace id for one whole chat turn.
String streamingTraceIdForTurn(Object turnId) => 'turn_${turnId}_stream';

/// Aggregates one runtime-only streaming trace snapshot for the active reply.
class StreamingTraceRecorder extends StateNotifier<StreamingTraceSnapshot?> {
  StreamingTraceRecorder({
    void Function(
      String message,
      Map<String, dynamic> data,
    )? persistentLogger,
  })  : _persistentLogger = persistentLogger,
        super(null);

  final void Function(
    String message,
    Map<String, dynamic> data,
  )? _persistentLogger;

  /// Returns the active in-memory trace snapshot, if any.
  StreamingTraceSnapshot? get activeSnapshot => state;

  void recordStage({
    required String traceId,
    required String turnId,
    required StreamingTraceStage stage,
    required DateTime timestamp,
    Map<String, dynamic> details = const <String, dynamic>{},
  }) {
    final current = state;
    final startedAt =
        current?.traceId == traceId ? current!.startedAt : timestamp;
    final entries = List<StreamingTraceEntry>.from(
      current?.traceId == traceId
          ? current!.entries
          : const <StreamingTraceEntry>[],
      growable: true,
    );
    if (_shouldSkipDuplicateStage(
      entries: entries,
      stage: stage,
      details: details,
    )) {
      return;
    }
    entries.add(
      StreamingTraceEntry(
        eventId: '$traceId:${entries.length}',
        traceId: traceId,
        stage: stage,
        timestamp: timestamp,
        elapsedMsFromStart: timestamp.difference(startedAt).inMilliseconds,
        title: stage.name,
        details: details,
      ),
    );
    if (_shouldPersistStage(stage)) {
      _emitPersistentTrace(
        'streaming.trace.stage',
        {
          'traceId': traceId,
          'turnId': turnId,
          'stage': stage.name,
          'elapsedMsFromStart': timestamp.difference(startedAt).inMilliseconds,
          ...details,
        },
      );
    }
    state = StreamingTraceSnapshot(
      traceId: traceId,
      turnId: turnId,
      status: StreamingTraceLifecycleStatus.running,
      currentStage: stage,
      summaryText: stage.name,
      startedAt: startedAt,
      firstVisibleAt: current?.firstVisibleAt ??
          (stage == StreamingTraceStage.uiFirstVisible ? timestamp : null),
      takeoverAt: current?.takeoverAt ??
          (stage == StreamingTraceStage.finalTakeover ? timestamp : null),
      entries: List.unmodifiable(entries),
    );
  }

  /// Marks the current trace completed after final takeover.
  void markCompleted({
    required String traceId,
    DateTime? takeoverAt,
  }) {
    final current = state;
    if (current == null || current.traceId != traceId) {
      return;
    }
    final resolvedTakeoverAt = takeoverAt ?? current.takeoverAt;
    _emitPersistentTrace(
      'streaming.trace.lifecycle',
      {
        'traceId': current.traceId,
        'turnId': current.turnId,
        'lifecycleStatus': StreamingTraceLifecycleStatus.completed.name,
        'currentStage': current.currentStage.name,
        'entryCount': current.entries.length,
        if (resolvedTakeoverAt != null)
          'takeoverAt': resolvedTakeoverAt.toIso8601String(),
      },
    );
    state = current.copyWith(
      status: StreamingTraceLifecycleStatus.completed,
      takeoverAt: resolvedTakeoverAt,
    );
  }

  /// Marks the current trace aborted when the running preview is cleared
  /// before a final takeover lands.
  void markAborted({
    required String traceId,
  }) {
    final current = state;
    if (current == null || current.traceId != traceId) {
      return;
    }
    _emitPersistentTrace(
      'streaming.trace.lifecycle',
      {
        'traceId': current.traceId,
        'turnId': current.turnId,
        'lifecycleStatus': StreamingTraceLifecycleStatus.aborted.name,
        'currentStage': current.currentStage.name,
        'entryCount': current.entries.length,
      },
    );
    state = current.copyWith(
      status: StreamingTraceLifecycleStatus.aborted,
    );
  }

  /// Clears any active runtime-only trace snapshot.
  void clear() {
    state = null;
  }

  bool _shouldSkipDuplicateStage({
    required List<StreamingTraceEntry> entries,
    required StreamingTraceStage stage,
    required Map<String, dynamic> details,
  }) {
    if (entries.isEmpty) {
      return false;
    }
    final last = entries.last;
    if (last.stage != stage) {
      return false;
    }
    if (stage != StreamingTraceStage.toolCallStarted &&
        stage != StreamingTraceStage.toolCallStreamStarted) {
      return false;
    }
    final lastToolName = last.details['toolName'];
    final nextToolName = details['toolName'];
    return lastToolName is String &&
        nextToolName is String &&
        lastToolName.trim() == nextToolName.trim();
  }

  bool _shouldPersistStage(StreamingTraceStage stage) {
    switch (stage) {
      case StreamingTraceStage.turnStarted:
      case StreamingTraceStage.modelRequestStarted:
      case StreamingTraceStage.modelFirstChunk:
      case StreamingTraceStage.modelRequestCompleted:
      case StreamingTraceStage.toolCallStreamStarted:
      case StreamingTraceStage.toolCallStreamCompleted:
      case StreamingTraceStage.toolCallStarted:
      case StreamingTraceStage.toolCallCompleted:
      case StreamingTraceStage.toolCallFailed:
      case StreamingTraceStage.uiFirstVisible:
      case StreamingTraceStage.finalTakeover:
        return true;
      case StreamingTraceStage.streamEventReceived:
      case StreamingTraceStage.previewEventConsumed:
      case StreamingTraceStage.previewStateCommitted:
      case StreamingTraceStage.timelineProjectionBuilt:
      case StreamingTraceStage.uiUpdated:
        return false;
    }
  }

  void _emitPersistentTrace(
    String message,
    Map<String, dynamic> data,
  ) {
    final logger = _persistentLogger;
    if (logger != null) {
      logger(message, data);
      return;
    }
    Logger.trace(
      'StreamingTraceRecorder',
      message,
      data: data,
    );
  }
}
