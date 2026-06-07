import 'package:ai_chat/models/debug/streaming_trace_snapshot.dart';
import 'package:ai_chat/providers/streaming_trace_providers.dart';
import 'package:ai_chat/theme/app_motion.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:ai_chat/widgets/chat_blocks/reasoning_section.dart';
import 'package:ai_chat/widgets/chat_timeline/stable_markdown_block.dart';
import 'package:ai_chat/widgets/markdown/flutter_markdown_impl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Final answer block used for both streaming preview and persisted state.
///
/// A single widget renders both phases so the timeline performs no widget-type
/// swap when truth takeover lands; only the text data updates. The streaming
/// phase shows a breathing cursor overlay and a collapsible reasoning section
/// that defaults to expanded, while the completed phase collapses reasoning by
/// default and renders the optional document title.
class FinalResponseBlock extends ConsumerStatefulWidget {
  final String title;

  /// Markdown source text. Always rendered through [FlutterMarkdownImpl] so
  /// streaming and completed states share the same parser and layout.
  final String text;
  final String? reasoningText;

  /// Stable cache key shared with the persisted state when the block describes
  /// the same logical answer; lets [StableMarkdownBlock] keep the subtree
  /// alive across the streaming→completed transition.
  final String? markdownCacheKey;
  final ValueChanged<bool>? onReasoningExpansionChanged;

  /// True while SSE deltas are still arriving. Drives cursor visibility and
  /// reasoning default expansion; never changes which widget renders the body.
  final bool isStreaming;

  /// Optional streaming trace correlation, only used while [isStreaming].
  final String? streamTraceId;
  final String? streamTurnId;

  const FinalResponseBlock({
    super.key,
    required this.title,
    required this.text,
    this.reasoningText,
    this.markdownCacheKey,
    this.onReasoningExpansionChanged,
    this.isStreaming = false,
    this.streamTraceId,
    this.streamTurnId,
  });

  @override
  ConsumerState<FinalResponseBlock> createState() => _FinalResponseBlockState();
}

class _FinalResponseBlockState extends ConsumerState<FinalResponseBlock> {
  bool _hasReportedFirstVisible = false;
  String _lastReportedText = '';

  @override
  void initState() {
    super.initState();
    if (widget.isStreaming) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _reportVisibilityStages();
      });
    }
  }

  @override
  void didUpdateWidget(covariant FinalResponseBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isStreaming) {
      return;
    }
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
          'source': 'final_response_text',
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
          'source': 'final_response_text',
          'textLength': widget.text.length,
          'previewText': widget.text,
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final motion = Theme.of(context).extension<AppMotion>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    final hasReasoning = (widget.reasoningText ?? '').trim().isNotEmpty;
    final showTitle = widget.title.trim().isNotEmpty && widget.title != '最终回答';

    // Streaming and completed phases render the exact same Markdown subtree
    // so takeover is a pure text update with no visual transition. The
    // active-turn status bar already conveys "is streaming" elsewhere, so
    // no inline cursor is needed here.
    final stableMarkdown = StableMarkdownBlock(
      cacheKey: widget.markdownCacheKey ??
          'final:${widget.title.trim()}:${widget.text.hashCode}',
      child: FlutterMarkdownImpl(data: widget.text),
    );

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
              if (showTitle) ...[
                Text(
                  widget.title,
                  style: AppTypography.uiStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14.8,
                    fontWeight: FontWeight.w500,
                    height: 1.14,
                  ),
                ),
                SizedBox(height: spacing.xxs + 1),
              ],
              if (hasReasoning)
                ReasoningSection(
                  text: widget.reasoningText!,
                  variant: ReasoningSectionVariant.finalAnswerCollapsible,
                  initiallyExpanded: widget.isStreaming,
                  onExpansionChanged: widget.onReasoningExpansionChanged,
                ),
              stableMarkdown,
            ],
          ),
        ),
      ),
    );
  }
}
