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
        StreamingTurnTimelineSegment(
          id: 'tool_${segments.length}_${span.toolName}',
          type: StreamingTurnTimelineSegmentType.toolCall,
          title: '调用 ${span.toolName}',
          detail: '正在调用 ${span.toolName}',
          startedAt: span.startedAt,
          endedAt: span.endedAt,
          durationMs: span.endedAt.difference(span.startedAt).inMilliseconds,
          isOngoing: span.isOngoing,
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
