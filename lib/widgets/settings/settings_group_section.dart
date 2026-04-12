import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Grouped settings panel with a lightweight section title.
class SettingsGroupSection extends StatelessWidget {
  final String title;
  final Widget child;

  const SettingsGroupSection({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: spacing.xs, bottom: spacing.xs),
          child: Text(
            title,
            style: TextStyle(
              color: colors.secondaryText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(spacing.md),
          decoration: BoxDecoration(
            color: colors.settingsPanelBackground,
            borderRadius: BorderRadius.circular(radius.lg),
            border: Border.all(color: colors.divider),
          ),
          child: child,
        ),
      ],
    );
  }
}
