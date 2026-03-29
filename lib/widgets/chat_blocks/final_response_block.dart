import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
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
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.structuredSurface,
        borderRadius: BorderRadius.circular(radius.md),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.primaryText,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: spacing.xs),
          FlutterMarkdownImpl(data: text),
        ],
      ),
    );
  }
}
