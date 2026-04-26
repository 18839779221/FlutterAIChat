import 'package:ai_chat/theme/app_colors.dart';
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

  const AssistantDocBlock({
    super.key,
    required this.text,
    this.label,
    this.reasoningText,
    this.markdownCacheKey,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Padding(
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
                variant: ReasoningSectionVariant.toolUseInline,
              ),
            StableMarkdownBlock(
              cacheKey:
                  markdownCacheKey ?? 'doc:${label ?? 'analysis'}:${text.hashCode}',
              child: FlutterMarkdownImpl(data: text),
            ),
          ],
        ),
      ),
    );
  }
}
