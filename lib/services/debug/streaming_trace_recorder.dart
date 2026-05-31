import 'package:ai_chat/models/debug/streaming_trace_snapshot.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stable runtime trace id for one whole chat turn.
String streamingTraceIdForTurn(Object turnId) => 'turn_${turnId}_stream';

/// Aggregates one runtime-only streaming trace snapshot for the active reply.
class StreamingTraceRecorder extends StateNotifier<StreamingTraceSnapshot?> {
  StreamingTraceRecorder() : super(null);

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
    final startedAt = current?.traceId == traceId ? current!.startedAt : timestamp;
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
    state = current.copyWith(
      status: StreamingTraceLifecycleStatus.completed,
      takeoverAt: takeoverAt ?? current.takeoverAt,
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
}
