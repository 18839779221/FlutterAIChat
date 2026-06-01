import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

class FileToolResultSurface extends StatelessWidget {
  const FileToolResultSurface({
    super.key,
    required this.toolLabel,
    required this.filePath,
    required this.summary,
    required this.child,
    this.primaryMeta,
    this.secondaryMeta,
    this.footer,
  });

  final String toolLabel;
  final String filePath;
  final String summary;
  final Widget child;
  final String? primaryMeta;
  final String? secondaryMeta;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeSpec.of(context);
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final markdown = colors.markdown;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.toolOutcomeSurface,
        borderRadius: BorderRadius.circular(radius.md + 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.xs,
              vertical: spacing.xxs + 1,
            ),
            decoration: BoxDecoration(
              color: markdown.codeBlockBackground.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(radius.sm),
            ),
            child: Text(
              toolLabel,
              style: AppTypography.uiStyle(
                color: colors.secondaryText,
                fontSize: 10.5,
                height: 1.1,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.28,
              ),
            ),
          ),
          SizedBox(height: spacing.sm),
          Text(
            filePath,
            style: AppTypography.uiStyle(
              color: colors.primaryText,
              fontSize: 15,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
          if ((primaryMeta ?? '').isNotEmpty) ...[
            SizedBox(height: spacing.xs),
            Text(
              primaryMeta!,
              style: AppTypography.uiStyle(
                color: colors.primaryText,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if ((secondaryMeta ?? '').isNotEmpty) ...[
            SizedBox(height: spacing.xxs),
            Text(
              secondaryMeta!,
              style: AppTypography.uiStyle(
                color: colors.secondaryText,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          SizedBox(height: spacing.xs),
          Text(
            summary,
            style: AppTypography.uiStyle(
              color: colors.secondaryText,
              fontSize: 12.5,
              height: 1.42,
            ),
          ),
          SizedBox(height: spacing.sm),
          child,
          if (footer != null) ...[
            SizedBox(height: spacing.sm),
            footer!,
          ],
        ],
      ),
    );
  }
}
