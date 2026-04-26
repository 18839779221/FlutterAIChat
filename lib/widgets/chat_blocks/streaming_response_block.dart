import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:ai_chat/widgets/chat_blocks/reasoning_section.dart';
import 'package:flutter/material.dart';

/// Lightweight text block used while the assistant is still streaming content.
class StreamingResponseBlock extends StatelessWidget {
  final String text;
  final String? reasoningText;

  const StreamingResponseBlock({
    super.key,
    required this.text,
    this.reasoningText,
  });

  @override
  Widget build(BuildContext context) {
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
            if ((reasoningText ?? '').trim().isNotEmpty)
              ReasoningSection(
                text: reasoningText!,
                variant: ReasoningSectionVariant.finalAnswerCollapsible,
                initiallyExpanded: true,
              ),
            SelectableText(
              text,
              style: AppTypography.documentStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13.2,
                height: 1.48,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
