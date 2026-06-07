/// Stable stage names used by the runtime-only streaming trace overlay.
enum StreamingTraceStage {
  turnStarted,
  modelRequestStarted,
  modelFirstChunk,
  modelRequestCompleted,
  streamEventReceived,
  previewEventConsumed,
  previewStateCommitted,
  timelineProjectionBuilt,
  toolCallStreamStarted,
  toolCallStreamCompleted,
  toolCallStarted,
  toolCallCompleted,
  toolCallFailed,
  uiFirstVisible,
  uiUpdated,
  finalTakeover,
}

/// Lifecycle of the current runtime-only streaming trace snapshot.
enum StreamingTraceLifecycleStatus {
  idle,
  running,
  completed,
  aborted,
}

/// One observed milestone in the streaming pipeline.
class StreamingTraceEntry {
  const StreamingTraceEntry({
    required this.eventId,
    required this.traceId,
    required this.stage,
    required this.timestamp,
    required this.elapsedMsFromStart,
    required this.title,
    this.details = const <String, dynamic>{},
  });

  /// Stable id for UI list rendering within the active snapshot.
  final String eventId;

  /// Logical trace id that groups one running streamed reply.
  final String traceId;

  /// Pipeline stage represented by this entry.
  final StreamingTraceStage stage;

  /// Absolute capture time for this stage.
  final DateTime timestamp;

  /// Milliseconds elapsed from the first recorded stage in the same trace.
  final int elapsedMsFromStart;

  /// Human-readable stage label for lightweight UI display.
  final String title;

  /// Small structured payload rendered in the overlay when helpful.
  final Map<String, dynamic> details;
}

/// Runtime-only snapshot consumed by the streaming trace overlay.
class StreamingTraceSnapshot {
  const StreamingTraceSnapshot({
    required this.traceId,
    required this.turnId,
    required this.status,
    required this.currentStage,
    required this.summaryText,
    required this.startedAt,
    this.firstVisibleAt,
    this.takeoverAt,
    this.entries = const <StreamingTraceEntry>[],
  });

  /// Stable trace id for one currently streaming reply.
  final String traceId;

  /// Runtime turn id associated with this trace when available.
  final String turnId;

  /// Current lifecycle status.
  final StreamingTraceLifecycleStatus status;

  /// Latest observed pipeline stage.
  final StreamingTraceStage currentStage;

  /// Lightweight summary shown at the top of the overlay.
  final String summaryText;

  /// Timestamp of the first recorded stage.
  final DateTime startedAt;

  /// First time the UI rendered non-empty visible body text, when reached.
  final DateTime? firstVisibleAt;

  /// Final takeover timestamp when truth replaced preview, when reached.
  final DateTime? takeoverAt;

  /// Ordered list of observed stage entries.
  final List<StreamingTraceEntry> entries;

  StreamingTraceSnapshot copyWith({
    String? traceId,
    String? turnId,
    StreamingTraceLifecycleStatus? status,
    StreamingTraceStage? currentStage,
    String? summaryText,
    DateTime? startedAt,
    DateTime? firstVisibleAt,
    DateTime? takeoverAt,
    List<StreamingTraceEntry>? entries,
  }) {
    return StreamingTraceSnapshot(
      traceId: traceId ?? this.traceId,
      turnId: turnId ?? this.turnId,
      status: status ?? this.status,
      currentStage: currentStage ?? this.currentStage,
      summaryText: summaryText ?? this.summaryText,
      startedAt: startedAt ?? this.startedAt,
      firstVisibleAt: firstVisibleAt ?? this.firstVisibleAt,
      takeoverAt: takeoverAt ?? this.takeoverAt,
      entries: entries ?? this.entries,
    );
  }
}

/// User-facing segment kinds shown in the current-turn timeline overlay.
enum StreamingTurnTimelineSegmentType {
  waitingModel,
  toolCall,
  stepWait,
  finalAnswer,
}

/// One aggregated current-turn timeline segment rendered in the overlay.
class StreamingTurnTimelineSegment {
  const StreamingTurnTimelineSegment({
    required this.id,
    required this.type,
    required this.title,
    required this.detail,
    required this.startedAt,
    required this.endedAt,
    required this.durationMs,
    this.modelFirstChunkDelayMs,
    this.modelStreamingDurationMs,
    this.isOngoing = false,
  });

  /// Stable id for UI list rendering.
  final String id;

  /// User-facing segment category.
  final StreamingTurnTimelineSegmentType type;

  /// Short status label such as `等待模型响应` or `调用 web_search`.
  final String title;

  /// Small contextual detail that helps match the segment with the main UI.
  final String detail;

  /// Inclusive start time of the segment.
  final DateTime startedAt;

  /// Exclusive end time of the segment, or current wall clock when ongoing.
  final DateTime endedAt;

  /// Duration of the segment in milliseconds.
  final int durationMs;

  /// Delay from model request start to first chunk for this segment, when known.
  final int? modelFirstChunkDelayMs;

  /// Duration from first chunk to request completion for this segment, when known.
  final int? modelStreamingDurationMs;

  /// Whether the segment is still active at render time.
  final bool isOngoing;
}

/// Aggregated current-turn timeline shown in the lightweight debug overlay.
class StreamingTurnTimeline {
  const StreamingTurnTimeline({
    required this.traceId,
    required this.turnId,
    required this.status,
    required this.totalElapsedMs,
    required this.currentStatusTitle,
    required this.currentStatusDetail,
    required this.segments,
  });

  /// Stable trace id that backs the aggregated timeline.
  final String traceId;

  /// Chat turn id shown by this timeline.
  final String turnId;

  /// Current lifecycle status of the underlying trace snapshot.
  final StreamingTraceLifecycleStatus status;

  /// Elapsed time from turn start to completed end or current wall clock.
  final int totalElapsedMs;

  /// Current high-level status label displayed in the overlay summary.
  final String currentStatusTitle;

  /// Current high-level detail displayed in the overlay summary.
  final String currentStatusDetail;

  /// Ordered user-facing segments for the current turn.
  final List<StreamingTurnTimelineSegment> segments;
}
