import 'package:ai_chat/models/debug/streaming_trace_snapshot.dart';
import 'package:ai_chat/providers/streaming_trace_providers.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_motion.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:ai_chat/widgets/animations/streaming_cursor.dart';
import 'package:ai_chat/widgets/chat_blocks/reasoning_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lightweight text block used while the assistant is still streaming content.
class StreamingResponseBlock extends ConsumerStatefulWidget {
  final String text;
  final String? reasoningText;
  final String? streamTraceId;
  final String? streamTurnId;

  const StreamingResponseBlock({
    super.key,
    required this.text,
    this.reasoningText,
    this.streamTraceId,
    this.streamTurnId,
  });

  @override
  ConsumerState<StreamingResponseBlock> createState() =>
      _StreamingResponseBlockState();
}

class _StreamingResponseBlockState extends ConsumerState<StreamingResponseBlock> {
  bool _hasReportedFirstVisible = false;
  String _lastReportedText = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportVisibilityStages();
    });
  }

  @override
  void didUpdateWidget(covariant StreamingResponseBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.streamTraceId != widget.streamTraceId ||
        oldWidget.streamTurnId != widget.streamTurnId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _reportVisibilityStages();
      });
    }
  }

  void _reportVisibilityStages() {
    if (!mounted) {
      return;
    }
    final traceId = widget.streamTraceId?.trim();
    final turnId = widget.streamTurnId?.trim();
    final text = widget.text.trim();
    if (traceId == null ||
        traceId.isEmpty ||
        turnId == null ||
        turnId.isEmpty ||
        text.isEmpty) {
      return;
    }
    final recorder = ref.read(streamingTraceRecorderProvider.notifier);
    final now = DateTime.now();
    if (!_hasReportedFirstVisible) {
      _hasReportedFirstVisible = true;
      _lastReportedText = widget.text;
      recorder.recordStage(
        traceId: traceId,
        turnId: turnId,
        stage: StreamingTraceStage.uiFirstVisible,
        timestamp: now,
        details: {
          'textLength': widget.text.length,
          'previewText': widget.text,
        },
      );
      return;
    }
    if (_lastReportedText != widget.text) {
      _lastReportedText = widget.text;
      recorder.recordStage(
        traceId: traceId,
        turnId: turnId,
        stage: StreamingTraceStage.uiUpdated,
        timestamp: now,
        details: {
          'textLength': widget.text.length,
          'previewText': widget.text,
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final motion = Theme.of(context).extension<AppMotion>()!;

    return AnimatedOpacity(
      duration: motion.quick,
      curve: motion.easeOut,
      opacity: 1,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.md - 1,
          0,
          spacing.md - 1,
          spacing.xxs,
        ),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((widget.reasoningText ?? '').trim().isNotEmpty)
                ReasoningSection(
                  text: widget.reasoningText!,
                  variant: ReasoningSectionVariant.finalAnswerCollapsible,
                  initiallyExpanded: true,
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SelectableText(
                      widget.text,
                      style: AppTypography.documentStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 13.2,
                        height: 1.48,
                      ),
                    ),
                  ),
                  StreamingCursor(
                    isVisible: true,
                    color: colors.workflowRunning,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
