import 'package:ai_chat/models/debug/streaming_trace_snapshot.dart';

/// Builds a user-facing current-turn timeline from low-level trace entries.
class StreamingTurnTimelineBuilder {
  static const int _minStandaloneToolStreamDurationMs = 20;
  static const Duration _maxPreviewToTruthMergeGap =
      Duration(milliseconds: 120);

  const StreamingTurnTimelineBuilder();

  StreamingTurnTimeline build(
    StreamingTraceSnapshot snapshot, {
    DateTime? now,
  }) {
    final resolvedNow = now ?? DateTime.now();
    final entries = [...snapshot.entries]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final turnStart = _resolveTurnStart(snapshot, entries);
    final finalAnswerStart = _resolveFinalAnswerStart(entries);
    final finalAnswerPreview = _resolveLatestPreviewText(entries);
    final modelPhases = _resolveModelPhases(entries, resolvedNow);
    final toolSpans = _resolveToolSpans(entries, resolvedNow);
    final completedEnd = snapshot.takeoverAt;
    final timelineEnd = completedEnd ?? resolvedNow;

    final segments = <StreamingTurnTimelineSegment>[];
    var cursor = turnStart;
    String? previousToolName;

    for (final span in toolSpans) {
      if (span.startedAt.isAfter(cursor)) {
        segments.add(
          _buildGapSegment(
            id: 'gap_${segments.length}',
            startedAt: cursor,
            endedAt: span.startedAt,
            previousToolName: previousToolName,
            isFirstGap: segments.isEmpty,
          ),
        );
      }
      segments.add(
        _buildToolSegment(
          index: segments.length,
          span: span,
          modelPhase: _matchToolModelPhase(
            modelPhases: modelPhases,
            span: span,
          ),
        ),
      );
      cursor = span.endedAt;
      previousToolName = span.toolName;
    }

    if (finalAnswerStart != null) {
      if (finalAnswerStart.isAfter(cursor)) {
        segments.add(
          _buildGapSegment(
            id: 'gap_${segments.length}',
            startedAt: cursor,
            endedAt: finalAnswerStart,
            previousToolName: previousToolName,
            isFirstGap: segments.isEmpty,
          ),
        );
      }
      final answerEnd = completedEnd ?? resolvedNow;
      final effectiveFinalAnswerStart =
          finalAnswerStart.isAfter(cursor) ? finalAnswerStart : cursor;
      final finalAnswerModelPhase = _matchFinalAnswerModelPhase(
        modelPhases: modelPhases,
        startedAt: effectiveFinalAnswerStart,
        endedAt: answerEnd,
      );
      segments.add(
        StreamingTurnTimelineSegment(
          id: 'final_${segments.length}',
          type: StreamingTurnTimelineSegmentType.finalAnswer,
          title: '回复生成中',
          detail: _buildFinalAnswerDetail(finalAnswerPreview),
          startedAt: effectiveFinalAnswerStart,
          endedAt: answerEnd,
          durationMs:
              answerEnd.difference(effectiveFinalAnswerStart).inMilliseconds,
          modelFirstChunkDelayMs: finalAnswerModelPhase?.firstChunkDelayMs,
          modelStreamingDurationMs: finalAnswerModelPhase?.streamingDurationMs,
          isOngoing: completedEnd == null,
        ),
      );
      cursor = answerEnd;
    } else if (timelineEnd.isAfter(cursor)) {
      segments.add(
        _buildGapSegment(
          id: 'gap_${segments.length}',
          startedAt: cursor,
          endedAt: timelineEnd,
          previousToolName: previousToolName,
          isFirstGap: segments.isEmpty,
          ongoing: true,
        ),
      );
    }

    if (segments.isEmpty) {
      segments.add(
        _buildGapSegment(
          id: 'gap_0',
          startedAt: turnStart,
          endedAt: timelineEnd,
          previousToolName: null,
          isFirstGap: true,
          ongoing: completedEnd == null,
        ),
      );
    }

    final totalElapsedMs = timelineEnd.difference(turnStart).inMilliseconds;
    final currentSegment = segments.last;
    final currentStatusTitle = snapshot.status == StreamingTraceLifecycleStatus.completed
        ? '已完成'
        : currentSegment.title;
    final currentStatusDetail = snapshot.status == StreamingTraceLifecycleStatus.completed
        ? 'final answer 已完整显示'
        : currentSegment.detail;

    return StreamingTurnTimeline(
      traceId: snapshot.traceId,
      turnId: snapshot.turnId,
      status: snapshot.status,
      totalElapsedMs: totalElapsedMs,
      currentStatusTitle: currentStatusTitle,
      currentStatusDetail: currentStatusDetail,
      segments: List.unmodifiable(segments.where((segment) => segment.durationMs >= 0)),
    );
  }

  DateTime _resolveTurnStart(
    StreamingTraceSnapshot snapshot,
    List<StreamingTraceEntry> entries,
  ) {
    for (final entry in entries) {
      if (entry.stage == StreamingTraceStage.turnStarted) {
        return entry.timestamp;
      }
    }
    return snapshot.startedAt;
  }

  DateTime? _resolveFinalAnswerStart(List<StreamingTraceEntry> entries) {
    for (final entry in entries) {
      if (entry.stage == StreamingTraceStage.uiFirstVisible ||
          entry.stage == StreamingTraceStage.uiUpdated) {
        return entry.timestamp;
      }
    }
    return null;
  }

  String? _resolveLatestPreviewText(List<StreamingTraceEntry> entries) {
    for (final entry in entries.reversed) {
      final value = entry.details['previewText'];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  StreamingTurnTimelineSegment _buildToolSegment({
    required int index,
    required _ToolSpan span,
    required _ModelRequestPhase? modelPhase,
  }) {
    return StreamingTurnTimelineSegment(
      id: 'tool_${index}_${span.toolName}',
      type: StreamingTurnTimelineSegmentType.toolCall,
      title: '调用 ${span.toolName}',
      detail: '正在调用 ${span.toolName}',
      startedAt: span.startedAt,
      endedAt: span.endedAt,
      durationMs: span.endedAt.difference(span.startedAt).inMilliseconds,
      modelFirstChunkDelayMs: modelPhase?.firstChunkDelayMs,
      modelStreamingDurationMs: modelPhase?.streamingDurationMs,
      isOngoing: span.isOngoing,
    );
  }

  List<_ToolSpan> _resolveToolSpans(
    List<StreamingTraceEntry> entries,
    DateTime now,
  ) {
    final previewSpans = _resolvePreviewToolSpans(entries, now);
    final truthSpans = _resolveTruthToolSpans(entries, now);
    final consumedPreviewSpanIndexes = <int>{};
    final merged = <_ToolSpan>[];

    for (final truthSpan in truthSpans) {
      var previewIndex = -1;
      for (var index = 0; index < previewSpans.length; index += 1) {
        if (consumedPreviewSpanIndexes.contains(index)) {
          continue;
        }
        final previewSpan = previewSpans[index];
        if (previewSpan.toolName != truthSpan.toolName) {
          continue;
        }
        final overlaps = previewSpan.startedAt.isBefore(truthSpan.endedAt) &&
            previewSpan.endedAt.isAfter(
              truthSpan.startedAt.subtract(const Duration(milliseconds: 1)),
            );
        final isNearby = !previewSpan.endedAt.isBefore(
              truthSpan.startedAt.subtract(_maxPreviewToTruthMergeGap),
            ) &&
            !previewSpan.startedAt.isAfter(
              truthSpan.endedAt.add(_maxPreviewToTruthMergeGap),
            );
        if (!overlaps && !isNearby) {
          continue;
        }
        previewIndex = index;
        break;
      }
      if (previewIndex == -1) {
        merged.add(truthSpan);
        continue;
      }
      final previewSpan = previewSpans[previewIndex];
      consumedPreviewSpanIndexes.add(previewIndex);
      final shouldExtendWithPreview =
          previewSpan.durationMs > _minStandaloneToolStreamDurationMs;
      merged.add(
        _ToolSpan(
          toolName: truthSpan.toolName,
          startedAt: shouldExtendWithPreview &&
                  previewSpan.startedAt.isBefore(truthSpan.startedAt)
              ? previewSpan.startedAt
              : truthSpan.startedAt,
          endedAt: truthSpan.endedAt.isAfter(previewSpan.endedAt)
              ? truthSpan.endedAt
              : previewSpan.endedAt,
          isOngoing: truthSpan.isOngoing || previewSpan.isOngoing,
        ),
      );
    }

    for (var index = 0; index < previewSpans.length; index += 1) {
      if (consumedPreviewSpanIndexes.contains(index)) {
        continue;
      }
      final previewSpan = previewSpans[index];
      if (previewSpan.durationMs <= _minStandaloneToolStreamDurationMs) {
        continue;
      }
      merged.add(previewSpan);
    }

    merged.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return merged;
  }

  List<_ModelRequestPhase> _resolveModelPhases(
    List<StreamingTraceEntry> entries,
    DateTime now,
  ) {
    final phases = <_ModelRequestPhase>[];
    _OpenModelRequestPhase? openPhase;

    for (final entry in entries) {
      switch (entry.stage) {
        case StreamingTraceStage.modelRequestStarted:
          final nextPhase = _readModelPhase(entry);
          if (nextPhase == null) {
            continue;
          }
          if (openPhase != null) {
            phases.add(
              openPhase.toClosed(
                completedAt: entry.timestamp,
                firstChunkAt: openPhase.firstChunkAt,
                isOngoing: false,
              ),
            );
          }
          openPhase = _OpenModelRequestPhase(
            phase: nextPhase,
            toolName: _readToolName(entry),
            startedAt: entry.timestamp,
          );
          break;
        case StreamingTraceStage.modelFirstChunk:
          final nextPhase = _readModelPhase(entry);
          if (openPhase == null || nextPhase == null) {
            continue;
          }
          if (openPhase.phase != nextPhase) {
            continue;
          }
          if (nextPhase == _ModelReplyPhase.toolCall) {
            final toolName = _readToolName(entry);
            if (toolName != null &&
                toolName.isNotEmpty &&
                toolName != openPhase.toolName) {
              continue;
            }
          }
          openPhase = openPhase.copyWith(firstChunkAt: entry.timestamp);
          break;
        case StreamingTraceStage.modelRequestCompleted:
          final nextPhase = _readModelPhase(entry);
          if (openPhase == null || nextPhase == null) {
            continue;
          }
          if (openPhase.phase != nextPhase) {
            continue;
          }
          if (nextPhase == _ModelReplyPhase.toolCall) {
            final toolName = _readToolName(entry);
            if (toolName != null &&
                toolName.isNotEmpty &&
                toolName != openPhase.toolName) {
              continue;
            }
          }
          phases.add(
            openPhase.toClosed(
              completedAt: entry.timestamp,
              firstChunkAt: openPhase.firstChunkAt,
              isOngoing: false,
            ),
          );
          openPhase = null;
          break;
        case StreamingTraceStage.turnStarted:
        case StreamingTraceStage.streamEventReceived:
        case StreamingTraceStage.previewEventConsumed:
        case StreamingTraceStage.previewStateCommitted:
        case StreamingTraceStage.timelineProjectionBuilt:
        case StreamingTraceStage.toolCallStreamStarted:
        case StreamingTraceStage.toolCallStreamCompleted:
        case StreamingTraceStage.toolCallStarted:
        case StreamingTraceStage.toolCallCompleted:
        case StreamingTraceStage.toolCallFailed:
        case StreamingTraceStage.uiFirstVisible:
        case StreamingTraceStage.uiUpdated:
        case StreamingTraceStage.finalTakeover:
          break;
      }
    }

    if (openPhase != null) {
      phases.add(
        openPhase.toClosed(
          completedAt: now,
          firstChunkAt: openPhase.firstChunkAt,
          isOngoing: true,
        ),
      );
    }

    return phases;
  }

  List<_ToolSpan> _resolvePreviewToolSpans(
    List<StreamingTraceEntry> entries,
    DateTime now,
  ) {
    final spans = <_ToolSpan>[];
    _OpenToolSpan? openSpan;

    for (final entry in entries) {
      switch (entry.stage) {
        case StreamingTraceStage.toolCallStreamStarted:
          final toolName = _readToolName(entry);
          if (toolName == null) {
            continue;
          }
          if (openSpan != null && openSpan.toolName != toolName) {
            spans.add(
              _ToolSpan(
                toolName: openSpan.toolName,
                startedAt: openSpan.startedAt,
                endedAt: entry.timestamp,
                isOngoing: false,
              ),
            );
          }
          openSpan = _OpenToolSpan(
            toolName: toolName,
            startedAt: entry.timestamp,
          );
          break;
        case StreamingTraceStage.toolCallStreamCompleted:
          final toolName = _readToolName(entry);
          if (openSpan == null) {
            continue;
          }
          if (toolName != null && toolName != openSpan.toolName) {
            continue;
          }
          spans.add(
            _ToolSpan(
              toolName: openSpan.toolName,
              startedAt: openSpan.startedAt,
              endedAt: entry.timestamp,
              isOngoing: false,
            ),
          );
          openSpan = null;
          break;
        case StreamingTraceStage.turnStarted:
        case StreamingTraceStage.modelRequestStarted:
        case StreamingTraceStage.modelFirstChunk:
        case StreamingTraceStage.modelRequestCompleted:
        case StreamingTraceStage.streamEventReceived:
        case StreamingTraceStage.previewEventConsumed:
        case StreamingTraceStage.previewStateCommitted:
        case StreamingTraceStage.timelineProjectionBuilt:
        case StreamingTraceStage.toolCallStarted:
        case StreamingTraceStage.toolCallCompleted:
        case StreamingTraceStage.toolCallFailed:
        case StreamingTraceStage.uiFirstVisible:
        case StreamingTraceStage.uiUpdated:
        case StreamingTraceStage.finalTakeover:
          break;
      }
    }

    if (openSpan != null) {
      spans.add(
        _ToolSpan(
          toolName: openSpan.toolName,
          startedAt: openSpan.startedAt,
          endedAt: now,
          isOngoing: true,
        ),
      );
    }

    return spans;
  }

  List<_ToolSpan> _resolveTruthToolSpans(
    List<StreamingTraceEntry> entries,
    DateTime now,
  ) {
    final spans = <_ToolSpan>[];
    _OpenToolSpan? openSpan;

    for (final entry in entries) {
      switch (entry.stage) {
        case StreamingTraceStage.toolCallStarted:
          final toolName = _readToolName(entry);
          if (toolName == null) {
            continue;
          }
          if (openSpan != null) {
            if (openSpan.toolName == toolName) {
              continue;
            }
            spans.add(
              _ToolSpan(
                toolName: openSpan.toolName,
                startedAt: openSpan.startedAt,
                endedAt: entry.timestamp,
                isOngoing: false,
              ),
            );
          }
          openSpan = _OpenToolSpan(
            toolName: toolName,
            startedAt: entry.timestamp,
          );
          break;
        case StreamingTraceStage.toolCallCompleted:
        case StreamingTraceStage.toolCallFailed:
          final toolName = _readToolName(entry);
          if (openSpan == null) {
            continue;
          }
          if (toolName != null && toolName != openSpan.toolName) {
            continue;
          }
          spans.add(
            _ToolSpan(
              toolName: openSpan.toolName,
              startedAt: openSpan.startedAt,
              endedAt: entry.timestamp,
              isOngoing: false,
            ),
          );
          openSpan = null;
          break;
        case StreamingTraceStage.turnStarted:
        case StreamingTraceStage.modelRequestStarted:
        case StreamingTraceStage.modelFirstChunk:
        case StreamingTraceStage.modelRequestCompleted:
        case StreamingTraceStage.streamEventReceived:
        case StreamingTraceStage.previewEventConsumed:
        case StreamingTraceStage.previewStateCommitted:
        case StreamingTraceStage.timelineProjectionBuilt:
        case StreamingTraceStage.toolCallStreamStarted:
        case StreamingTraceStage.toolCallStreamCompleted:
        case StreamingTraceStage.uiFirstVisible:
        case StreamingTraceStage.uiUpdated:
        case StreamingTraceStage.finalTakeover:
          break;
      }
    }

    if (openSpan != null) {
      spans.add(
        _ToolSpan(
          toolName: openSpan.toolName,
          startedAt: openSpan.startedAt,
          endedAt: now,
          isOngoing: true,
        ),
      );
    }

    return spans;
  }

  _ModelRequestPhase? _matchToolModelPhase({
    required List<_ModelRequestPhase> modelPhases,
    required _ToolSpan span,
  }) {
    for (final phase in modelPhases) {
      if (phase.phase != _ModelReplyPhase.toolCall) {
        continue;
      }
      if (phase.toolName != span.toolName) {
        continue;
      }
      if (_rangesOverlap(
        startedAt: phase.startedAt,
        endedAt: phase.endedAt,
        otherStartedAt: span.startedAt,
        otherEndedAt: span.endedAt,
      )) {
        return phase;
      }
    }
    return null;
  }

  _ModelRequestPhase? _matchFinalAnswerModelPhase({
    required List<_ModelRequestPhase> modelPhases,
    required DateTime startedAt,
    required DateTime endedAt,
  }) {
    for (final phase in modelPhases) {
      if (phase.phase != _ModelReplyPhase.finalAnswer) {
        continue;
      }
      if (_rangesOverlap(
        startedAt: phase.startedAt,
        endedAt: phase.endedAt,
        otherStartedAt: startedAt,
        otherEndedAt: endedAt,
      )) {
        return phase;
      }
    }
    return null;
  }

  StreamingTurnTimelineSegment _buildGapSegment({
    required String id,
    required DateTime startedAt,
    required DateTime endedAt,
    required String? previousToolName,
    required bool isFirstGap,
    bool ongoing = false,
  }) {
    final type = isFirstGap
        ? StreamingTurnTimelineSegmentType.waitingModel
        : StreamingTurnTimelineSegmentType.stepWait;
    final title = isFirstGap ? '等待模型响应' : '步骤间等待';
    final detail = isFirstGap
        ? '等待模型开始下一步'
        : previousToolName == null
            ? '等待模型继续'
            : '已完成 $previousToolName，正在规划下一步';
    return StreamingTurnTimelineSegment(
      id: id,
      type: type,
      title: title,
      detail: detail,
      startedAt: startedAt,
      endedAt: endedAt,
      durationMs: endedAt.difference(startedAt).inMilliseconds,
      isOngoing: ongoing,
    );
  }

  String _buildFinalAnswerDetail(String? previewText) {
    final normalized = previewText?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    if (normalized.isEmpty) {
      return '正在生成回复';
    }
    return '正在生成：${_truncate(normalized, 18)}';
  }

  String _truncate(String value, int maxChars) {
    if (value.length <= maxChars) {
      return value;
    }
    return '${value.substring(0, maxChars)}...';
  }

  String? _readToolName(StreamingTraceEntry entry) {
    final value = entry.details['toolName'];
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  _ModelReplyPhase? _readModelPhase(StreamingTraceEntry entry) {
    final value = entry.details['phase'];
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    switch (trimmed) {
      case 'tool_call':
        return _ModelReplyPhase.toolCall;
      case 'final_answer':
        return _ModelReplyPhase.finalAnswer;
      default:
        return null;
    }
  }

  bool _rangesOverlap({
    required DateTime startedAt,
    required DateTime endedAt,
    required DateTime otherStartedAt,
    required DateTime otherEndedAt,
  }) {
    return startedAt.isBefore(otherEndedAt) &&
        endedAt.isAfter(otherStartedAt.subtract(const Duration(milliseconds: 1)));
  }
}

class _OpenToolSpan {
  const _OpenToolSpan({
    required this.toolName,
    required this.startedAt,
  });

  final String toolName;
  final DateTime startedAt;
}

class _ToolSpan {
  const _ToolSpan({
    required this.toolName,
    required this.startedAt,
    required this.endedAt,
    required this.isOngoing,
  });

  final String toolName;
  final DateTime startedAt;
  final DateTime endedAt;
  final bool isOngoing;

  int get durationMs => endedAt.difference(startedAt).inMilliseconds;
}

enum _ModelReplyPhase {
  toolCall,
  finalAnswer,
}

class _OpenModelRequestPhase {
  const _OpenModelRequestPhase({
    required this.phase,
    required this.toolName,
    required this.startedAt,
    this.firstChunkAt,
  });

  final _ModelReplyPhase phase;
  final String? toolName;
  final DateTime startedAt;
  final DateTime? firstChunkAt;

  _OpenModelRequestPhase copyWith({
    DateTime? firstChunkAt,
  }) {
    return _OpenModelRequestPhase(
      phase: phase,
      toolName: toolName,
      startedAt: startedAt,
      firstChunkAt: firstChunkAt ?? this.firstChunkAt,
    );
  }

  _ModelRequestPhase toClosed({
    required DateTime completedAt,
    required DateTime? firstChunkAt,
    required bool isOngoing,
  }) {
    return _ModelRequestPhase(
      phase: phase,
      toolName: toolName,
      startedAt: startedAt,
      firstChunkAt: firstChunkAt,
      endedAt: completedAt,
      isOngoing: isOngoing,
    );
  }
}

class _ModelRequestPhase {
  const _ModelRequestPhase({
    required this.phase,
    required this.toolName,
    required this.startedAt,
    required this.firstChunkAt,
    required this.endedAt,
    required this.isOngoing,
  });

  final _ModelReplyPhase phase;
  final String? toolName;
  final DateTime startedAt;
  final DateTime? firstChunkAt;
  final DateTime endedAt;
  final bool isOngoing;

  int? get firstChunkDelayMs => firstChunkAt?.difference(startedAt).inMilliseconds;

  int? get streamingDurationMs =>
      firstChunkAt == null ? null : endedAt.difference(firstChunkAt!).inMilliseconds;
}
