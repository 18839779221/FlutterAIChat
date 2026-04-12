import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/widgets/markdown/flutter_markdown_impl.dart';
import 'package:flutter/material.dart';

/// Document-style assistant content block.
class AssistantDocBlock extends StatelessWidget {
  final String text;
  final String? label;

  const AssistantDocBlock({
    super.key,
    required this.text,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.md + 1,
        spacing.xxs,
        spacing.md + 1,
        spacing.xxs + 1,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null) ...[
              Text(
                label!,
                style: TextStyle(
                  color: colors.secondaryText,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: spacing.xxs + 1),
              Container(
                height: 1,
                width: 18,
                color: colors.divider.withValues(alpha: 0.48),
              ),
              SizedBox(height: spacing.xs + 1),
            ],
            FlutterMarkdownImpl(data: text),
          ],
        ),
      ),
    );
  }
}
