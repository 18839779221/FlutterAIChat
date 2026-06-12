import 'package:ai_chat/models/debug/streaming_trace_snapshot.dart';
import 'package:ai_chat/services/debug/streaming_turn_timeline_builder.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Lightweight runtime-only overlay for inspecting the streaming timeline.
class StreamingTraceOverlayCard extends StatelessWidget {
  static const _timelineBuilder = StreamingTurnTimelineBuilder();

  const StreamingTraceOverlayCard({
    super.key,
    required this.snapshot,
  });

  final StreamingTraceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final mediaQuery = MediaQuery.of(context);
    final isPhone = !kIsWeb && mediaQuery.size.shortestSide < 600;
    final maxTimelineHeight = isPhone ? 440.0 : 220.0;
    final timeline = _timelineBuilder.build(snapshot);
    final maxDurationMs = timeline.segments.fold<int>(
      1,
      (current, segment) => segment.durationMs > current
          ? segment.durationMs
          : current,
    );

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.assistantSurface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(radius.lg),
          border: Border.all(
            color: colors.divider.withValues(alpha: 0.65),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Streaming Timeline',
                style: AppTypography.uiStyle(
                  color: colors.primaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              SizedBox(height: spacing.xxs),
              Text(
                '本轮已耗时 ${_formatDuration(timeline.totalElapsedMs)}',
                style: AppTypography.uiStyle(
                  color: colors.secondaryText,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              SizedBox(height: spacing.xxs),
              Text(
                '${timeline.currentStatusTitle} · ${timeline.currentStatusDetail}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.uiStyle(
                  color: colors.primaryText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.28,
                ),
              ),
              SizedBox(height: spacing.sm),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: maxTimelineHeight,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var index = 0; index < timeline.segments.length; index += 1)
                        Padding(
                          padding: EdgeInsets.only(bottom: spacing.sm),
                          child: _TimelineSegmentRow(
                            segment: timeline.segments[index],
                            maxDurationMs: maxDurationMs,
                            isLast: index == timeline.segments.length - 1,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // TEMP DEBUG: 原始 entries 时间戳转储，用于定位时钟倒挂来源，定位后删除
              _DebugEntriesDump(snapshot: snapshot),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int durationMs) {
    if (durationMs >= 10000) {
      return '${(durationMs / 1000).toStringAsFixed(1)}s';
    }
    if (durationMs >= 1000) {
      return '${(durationMs / 1000).toStringAsFixed(1)}s';
    }
    return '${durationMs}ms';
  }
}

class _TimelineSegmentRow extends StatelessWidget {
  const _TimelineSegmentRow({
    required this.segment,
    required this.maxDurationMs,
    required this.isLast,
  });

  final StreamingTurnTimelineSegment segment;
  final int maxDurationMs;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final widthFactor = (segment.durationMs / maxDurationMs).clamp(0.18, 1.0);
    final accent = _accentColor(colors, segment.type, segment.isOngoing);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.22),
                    blurRadius: 8,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
            ),
            if (!isLast)
              Container(
                width: 1.5,
                height: 38,
                margin: EdgeInsets.only(top: spacing.xxs),
                color: colors.divider.withValues(alpha: 0.8),
              ),
          ],
        ),
        SizedBox(width: spacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      segment.title,
                      style: AppTypography.uiStyle(
                        color: colors.primaryText,
                        fontSize: 12.2,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                  SizedBox(width: spacing.xs),
                  Text(
                    _formatDuration(segment.durationMs),
                    style: AppTypography.codeStyle(
                      color: colors.secondaryText,
                      fontSize: 10.8,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
              SizedBox(height: spacing.xxs),
              Text(
                _buildSegmentDetail(segment),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.uiStyle(
                  color: colors.secondaryText,
                  fontSize: 11.2,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
              SizedBox(height: spacing.xs),
              FractionallySizedBox(
                widthFactor: widthFactor,
                child: Container(
                  height: 7,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: segment.isOngoing ? 0.92 : 0.76),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(int durationMs) {
    if (durationMs >= 1000) {
      return '${(durationMs / 1000).toStringAsFixed(1)}s';
    }
    return '${durationMs}ms';
  }

  String _buildSegmentDetail(StreamingTurnTimelineSegment segment) {
    final metrics = <String>[];
    final firstChunkDelayMs = segment.modelFirstChunkDelayMs;
    if (firstChunkDelayMs != null) {
      metrics.add('首包 ${ _formatDuration(firstChunkDelayMs) }');
    }
    final streamingDurationMs = segment.modelStreamingDurationMs;
    if (streamingDurationMs != null) {
      metrics.add('流式 ${ _formatDuration(streamingDurationMs) }');
    }
    if (metrics.isEmpty) {
      return segment.detail;
    }
    return '${segment.detail} · ${metrics.join(' / ')}';
  }

  Color _accentColor(
    AppThemeSpec colors,
    StreamingTurnTimelineSegmentType type,
    bool isOngoing,
  ) {
    switch (type) {
      case StreamingTurnTimelineSegmentType.waitingModel:
        return colors.workflowWarning.withValues(alpha: isOngoing ? 0.92 : 0.82);
      case StreamingTurnTimelineSegmentType.toolCall:
        return colors.workflowRunning.withValues(alpha: isOngoing ? 0.96 : 0.84);
      case StreamingTurnTimelineSegmentType.stepWait:
        return colors.semantic.interaction.focus
            .withValues(alpha: isOngoing ? 0.94 : 0.82);
      case StreamingTurnTimelineSegmentType.finalAnswer:
        return colors.workflowSuccess.withValues(alpha: isOngoing ? 0.94 : 0.84);
    }
  }
}

// TEMP DEBUG: 用无歧义的 epoch 毫秒 + isUtc 转储结构性阶段，定位时间戳异常来源。
// 同步打到 Logger 便于从 logcat 复制文本。定位后整体删除。
class _DebugEntriesDump extends StatelessWidget {
  const _DebugEntriesDump({required this.snapshot});

  final StreamingTraceSnapshot snapshot;

  // 每 token 的高频噪声阶段，转储时跳过，只看结构性阶段。
  static const _noisyStages = <StreamingTraceStage>{
    StreamingTraceStage.streamEventReceived,
    StreamingTraceStage.previewEventConsumed,
    StreamingTraceStage.previewStateCommitted,
    StreamingTraceStage.timelineProjectionBuilt,
    StreamingTraceStage.uiUpdated,
  };

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final now = DateTime.now();
    final startedAt = snapshot.startedAt;
    final startEpoch = startedAt.millisecondsSinceEpoch;

    String stamp(DateTime dt) =>
        'epoch=${dt.millisecondsSinceEpoch} utc=${dt.isUtc} ${dt.toIso8601String()}';

    final header = <String>[
      'now    ${stamp(now)}',
      'started ${stamp(startedAt)}',
      'takeover ${snapshot.takeoverAt == null ? '-' : stamp(snapshot.takeoverAt!)}',
      'status=${snapshot.status.name} '
          'nowMinusStarted=${now.millisecondsSinceEpoch - startEpoch}ms '
          'entries=${snapshot.entries.length}',
    ];

    final structural = <String>[];
    for (var i = 0; i < snapshot.entries.length; i += 1) {
      final entry = snapshot.entries[i];
      if (_noisyStages.contains(entry.stage)) {
        continue;
      }
      final deltaMs = entry.timestamp.millisecondsSinceEpoch - startEpoch;
      final details = entry.details;
      final tags = <String>[
        if (details['requestId'] != null) 'req=${details['requestId']}',
        if (details['phase'] != null) 'phase=${details['phase']}',
        if (details['toolName'] != null) 'tool=${details['toolName']}',
      ].join(' ');
      structural.add(
        '$i ${entry.stage.name} Δ=${deltaMs}ms '
        'epoch=${entry.timestamp.millisecondsSinceEpoch} '
        'utc=${entry.timestamp.isUtc}${tags.isEmpty ? '' : '  $tags'}',
      );
    }

    final lines = [...header, ...structural];
    Logger.trace(
      'StreamingTraceOverlayCard',
      'timeline-dump',
      data: {'lines': lines},
    );

    return Padding(
      padding: EdgeInsets.only(top: spacing.sm),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(spacing.xs),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Text(
                line,
                style: AppTypography.codeStyle(
                  color: colors.secondaryText,
                  fontSize: 9,
                  height: 1.3,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
