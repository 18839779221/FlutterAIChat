import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_motion.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Compact segmented control used by settings choices.
class SettingsSegmentedControl<T> extends StatelessWidget {
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  const SettingsSegmentedControl({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final motion = Theme.of(context).extension<AppMotion>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Container(
      padding: EdgeInsets.all(spacing.xxs),
      decoration: BoxDecoration(
        color: colors.assistantSurface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(radius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.entries.map((entry) {
          final selected = entry.key == value;
          return Padding(
            padding: EdgeInsets.only(right: spacing.xxs),
            child: InkWell(
              borderRadius: BorderRadius.circular(radius.pill),
              onTap: () => onChanged(entry.key),
              child: AnimatedContainer(
                duration: motion.quick,
                curve: motion.easeOut,
                padding: EdgeInsets.symmetric(
                  horizontal: spacing.sm,
                  vertical: spacing.xs,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? colors.settingsPanelBackground
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(radius.pill),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: colors.core.elevation.shadowColor
                                .withValues(alpha: 0.05),
                            blurRadius: 12,
                            spreadRadius: -8,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  entry.value,
                  style: TextStyle(
                    color: selected
                        ? colors.primaryText
                        : colors.secondaryText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
