import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_motion.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:ai_chat/widgets/chat_blocks/reasoning_section.dart';
import 'package:ai_chat/widgets/chat_timeline/stable_markdown_block.dart';
import 'package:ai_chat/widgets/markdown/flutter_markdown_impl.dart';
import 'package:flutter/material.dart';

/// Document-style assistant content block.
class AssistantDocBlock extends StatelessWidget {
  final String text;
  final String? label;
  final String? reasoningText;
  final String? markdownCacheKey;
  final bool selectable;
  final ReasoningSectionVariant reasoningVariant;
  final bool reasoningInitiallyExpanded;
  final ValueChanged<bool>? onReasoningExpansionChanged;

  const AssistantDocBlock({
    super.key,
    required this.text,
    this.label,
    this.reasoningText,
    this.markdownCacheKey,
    this.selectable = false,
    this.reasoningVariant = ReasoningSectionVariant.toolUseInline,
    this.reasoningInitiallyExpanded = true,
    this.onReasoningExpansionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final motion = Theme.of(context).extension<AppMotion>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

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
              if (label != null) ...[
                Text(
                  label!,
                  style: AppTypography.uiStyle(
                    color: colors.secondaryText,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: spacing.xxs),
                Container(
                  height: 1,
                  width: 14,
                  color: colors.divider.withValues(alpha: 0.36),
                ),
                SizedBox(height: spacing.xs),
              ],
              if ((reasoningText ?? '').trim().isNotEmpty)
                ReasoningSection(
                  text: reasoningText!,
                  variant: reasoningVariant,
                  initiallyExpanded: reasoningInitiallyExpanded,
                  onExpansionChanged: onReasoningExpansionChanged,
                ),
              StableMarkdownBlock(
                cacheKey: markdownCacheKey ??
                    'doc:${label ?? 'analysis'}:${text.hashCode}',
                child: FlutterMarkdownImpl(
                  data: text,
                  selectable: selectable,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
