import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:ai_chat/widgets/markdown/flutter_markdown_impl.dart';
import 'package:flutter/material.dart';

/// High-priority final answer block shown after intermediate analysis.
class FinalResponseBlock extends StatelessWidget {
  final String title;
  final String text;

  const FinalResponseBlock({
    super.key,
    required this.title,
    required this.text,
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
            if (title.trim().isNotEmpty && title != '最终回答') ...[
              Text(
                title,
                style: AppTypography.uiStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14.8,
                  fontWeight: FontWeight.w500,
                  height: 1.14,
                ),
              ),
              SizedBox(height: spacing.xxs + 1),
            ],
            FlutterMarkdownImpl(data: text),
          ],
        ),
      ),
    );
  }
}
