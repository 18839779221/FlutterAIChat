import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../technical_content_surface.dart';

class FileToolResultSurface extends StatelessWidget {
  const FileToolResultSurface({
    super.key,
    required this.filePath,
    required this.statusText,
    required this.child,
    this.footer,
  });

  final String filePath;
  final String statusText;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeSpec.of(context);
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.toolOutcomeSurface.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(radius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TechnicalContentSurface(
            backgroundColor: colors.assistantSurface.withValues(alpha: 0.0),
            headerBackgroundColor:
                colors.toolWorkflowSurface.withValues(alpha: 0.18),
            contentPadding: EdgeInsets.zero,
            header: Row(
              children: [
                Text(
                  statusText,
                  style: AppTypography.uiStyle(
                    color: colors.secondaryText,
                    fontSize: 11.5,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: spacing.xs),
                Expanded(
                  child: Text(
                    filePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.uiStyle(
                      color: colors.primaryText,
                      fontSize: 11.5,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            child: const SizedBox.shrink(),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.xs,
              spacing.xxs,
              spacing.xs,
              spacing.xs,
            ),
            child: child,
          ),
          if (footer != null) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.xs,
                0,
                spacing.xs,
                spacing.xs,
              ),
              child: footer!,
            ),
          ],
        ],
      ),
    );
  }
}
