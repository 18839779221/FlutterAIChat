import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_spec.dart';

enum SettingsValueBadgeTone {
  neutral,
  active,
  success,
  warning,
}

/// Lightweight badge for current values, counts, and compact status labels.
class SettingsValueBadge extends StatelessWidget {
  const SettingsValueBadge({
    super.key,
    required this.label,
    this.tone = SettingsValueBadgeTone.neutral,
  });

  final String label;
  final SettingsValueBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _backgroundColor(colors),
        borderRadius: BorderRadius.circular(radius.pill),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.sm,
          vertical: spacing.xxs + 2,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: _foregroundColor(colors),
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }

  Color _backgroundColor(AppThemeSpec colors) {
    switch (tone) {
      case SettingsValueBadgeTone.neutral:
        return colors.assistantSurface.withValues(alpha: 0.92);
      case SettingsValueBadgeTone.active:
        return colors.workflowRunning.withValues(alpha: 0.12);
      case SettingsValueBadgeTone.success:
        return colors.workflowSuccess.withValues(alpha: 0.12);
      case SettingsValueBadgeTone.warning:
        return colors.workflowWarning.withValues(alpha: 0.14);
    }
  }

  Color _foregroundColor(AppThemeSpec colors) {
    switch (tone) {
      case SettingsValueBadgeTone.neutral:
        return colors.primaryText;
      case SettingsValueBadgeTone.active:
        return colors.workflowRunning;
      case SettingsValueBadgeTone.success:
        return colors.workflowSuccess;
      case SettingsValueBadgeTone.warning:
        return colors.workflowWarning;
    }
  }
}
