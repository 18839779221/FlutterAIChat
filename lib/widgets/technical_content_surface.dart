import 'package:flutter/material.dart';

import '../theme/app_theme_spec.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Shared surface used by code, command, and file-preview content blocks.
class TechnicalContentSurface extends StatelessWidget {
  final Widget child;
  final Widget? header;
  final EdgeInsetsGeometry? contentPadding;
  final Color? backgroundColor;
  final Color? headerBackgroundColor;

  const TechnicalContentSurface({
    super.key,
    required this.child,
    this.header,
    this.contentPadding,
    this.backgroundColor,
    this.headerBackgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.assistantSurface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(radius.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                spacing.sm,
                spacing.xxs + 1,
                spacing.sm,
                spacing.xxs + 1,
              ),
              decoration: BoxDecoration(
                color: headerBackgroundColor ??
                    colors.toolWorkflowSurface.withValues(alpha: 0.32),
                border: Border(
                  bottom: BorderSide(
                    color: colors.divider.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                ),
              ),
              child: header,
            ),
          Padding(
            padding: contentPadding ?? EdgeInsets.all(spacing.sm),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Lightweight technical-content label used in shared headers.
class TechnicalContentLabel extends StatelessWidget {
  final String text;

  const TechnicalContentLabel({
    super.key,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;

    return Text(
      text,
      style: AppTypography.uiStyle(
        color: colors.secondaryText,
        fontSize: 10.5,
        height: 1.1,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.18,
      ),
    );
  }
}
