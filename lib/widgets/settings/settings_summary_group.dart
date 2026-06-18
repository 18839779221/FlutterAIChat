import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_spec.dart';

/// Shared overview group used by the settings landing page.
class SettingsSummaryGroup extends StatelessWidget {
  const SettingsSummaryGroup({
    super.key,
    required this.title,
    required this.summary,
    required this.children,
    this.actionLabel,
    this.onActionPressed,
  });

  final String title;
  final String summary;
  final List<Widget> children;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.settingsPanelBackground.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(radius.lg),
        boxShadow: [
          BoxShadow(
            color: colors.core.elevation.shadowColor.withValues(alpha: 0.05),
            blurRadius: 18,
            spreadRadius: -8,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.lg,
          spacing.md,
          spacing.lg,
          spacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: colors.primaryText,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      SizedBox(height: spacing.xxs),
                      Text(
                        summary,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.secondaryText,
                              height: 1.45,
                            ),
                      ),
                    ],
                  ),
                ),
                if ((actionLabel ?? '').trim().isNotEmpty)
                  _SettingsSummaryAction(
                    label: actionLabel!.trim(),
                    onPressed: onActionPressed,
                  ),
              ],
            ),
            SizedBox(height: spacing.md),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SettingsSummaryAction extends StatefulWidget {
  const _SettingsSummaryAction({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  State<_SettingsSummaryAction> createState() => _SettingsSummaryActionState();
}

class _SettingsSummaryActionState extends State<_SettingsSummaryAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final motion = Theme.of(context).extension<AppMotion>()!;

    return AnimatedScale(
      scale: _pressed ? 0.98 : 1,
      duration: motion.instant,
      curve: motion.easeOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius.pill),
          onTap: widget.onPressed,
          onHighlightChanged: (value) {
            if (_pressed != value) {
              setState(() {
                _pressed = value;
              });
            }
          },
          child: AnimatedContainer(
            duration: motion.quick,
            curve: motion.easeOut,
            padding: EdgeInsets.symmetric(
              horizontal: spacing.sm,
              vertical: spacing.xs,
            ),
            decoration: BoxDecoration(
              color: colors.assistantSurface.withValues(
                alpha: _pressed ? 0.98 : 0.9,
              ),
              borderRadius: BorderRadius.circular(radius.pill),
            ),
            child: Text(
              widget.label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
