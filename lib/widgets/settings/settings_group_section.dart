import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Shared grouped section for settings management and editing pages.
class SettingsGroupSection extends StatelessWidget {
  final String title;
  final Widget child;
  final String? summary;

  const SettingsGroupSection({
    super.key,
    required this.title,
    required this.child,
    this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: spacing.xs, bottom: spacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if ((summary ?? '').trim().isNotEmpty) ...[
                SizedBox(height: spacing.xxs),
                Text(
                  summary!.trim(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                        height: 1.4,
                      ),
                ),
              ],
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(spacing.md),
          decoration: BoxDecoration(
            color: colors.settingsPanelBackground.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(radius.lg),
            boxShadow: [
              BoxShadow(
                color: colors.core.elevation.shadowColor.withValues(alpha: 0.05),
                blurRadius: 18,
                spreadRadius: -10,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ],
    );
  }
}
