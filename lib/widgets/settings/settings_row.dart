import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Standard row layout for settings pages.
class SettingsRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget trailing;
  final EdgeInsetsGeometry? padding;

  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.trailing,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Padding(
      padding: padding ??
          EdgeInsets.symmetric(vertical: spacing.xs, horizontal: spacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.primaryText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: spacing.xxs),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: colors.secondaryText,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: spacing.md),
          Flexible(child: trailing),
        ],
      ),
    );
  }
}
