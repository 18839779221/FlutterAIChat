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
    required this.children,
    this.headerTrailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(spacing.md, 0, spacing.md, spacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFamily: 'SourceSerif4',
                        color: colors.secondaryText,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                        letterSpacing: 0.15,
                      ),
                ),
              ),
              if (headerTrailing != null) headerTrailing!,
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.settingsPanelBackground.withValues(alpha: 0.54),
            borderRadius: BorderRadius.circular(radius.lg + 4),
            border: Border.all(
              color: colors.divider.withValues(alpha: 0.2),
            ),
            boxShadow: [
              BoxShadow(
                color:
                    colors.core.elevation.shadowColor.withValues(alpha: 0.04),
                blurRadius: 18,
                spreadRadius: -10,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: spacing.xxs + 2),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: spacing.md),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: colors.divider.withValues(alpha: 0.34),
                      ),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class SettingsSectionHeaderAction extends StatefulWidget {
  const SettingsSectionHeaderAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  State<SettingsSectionHeaderAction> createState() =>
      _SettingsSectionHeaderActionState();
}

class _SettingsSectionHeaderActionState
    extends State<SettingsSectionHeaderAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final motion = Theme.of(context).extension<AppMotion>()!;

    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
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
            constraints: const BoxConstraints(minHeight: 30, minWidth: 74),
            padding: EdgeInsets.symmetric(
              horizontal: spacing.sm,
              vertical: spacing.xxs + 2,
            ),
            decoration: BoxDecoration(
              color: colors.assistantSurface.withValues(
                alpha: _pressed ? 0.96 : 0.86,
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
