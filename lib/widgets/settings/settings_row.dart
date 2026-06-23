import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_motion.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Shared status row for the settings domain.
class SettingsRow extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Widget trailing;
  final Widget? leading;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.trailing,
    this.leading,
    this.padding,
    this.onTap,
  });

  @override
  State<SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<SettingsRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final motion = Theme.of(context).extension<AppMotion>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final isAction = widget.onTap != null;
    final rowPadding = widget.padding ??
        EdgeInsets.symmetric(horizontal: spacing.sm, vertical: spacing.sm);

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.leading != null) ...[
          Padding(
            padding: EdgeInsets.only(top: widget.subtitle == null ? 1 : 2),
            child: SizedBox(
              width: 22,
              child: Align(
                alignment: Alignment.topLeft,
                child: IconTheme(
                  data: IconThemeData(
                    size: 18,
                    color: colors.secondaryText.withValues(alpha: 0.88),
                  ),
                  child: widget.leading!,
                ),
              ),
            ),
          ),
          SizedBox(width: spacing.sm),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
              ),
              if (widget.subtitle != null) ...[
                SizedBox(height: spacing.xxs),
                Text(
                  widget.subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                        height: 1.4,
                      ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(width: spacing.md),
        Flexible(
          fit: FlexFit.loose,
          child: Align(
            alignment: Alignment.topRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: widget.trailing),
                  if (isAction) ...[
                    SizedBox(width: spacing.xs),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: colors.secondaryText,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );

    if (!isAction) {
      return Padding(
        key: ValueKey('settings-row-display-${widget.title}'),
        padding: rowPadding,
        child: content,
      );
    }

    return Semantics(
      button: true,
      child: AnimatedContainer(
        key: ValueKey('settings-row-shell-${widget.title}'),
        duration: motion.quick,
        curve: motion.easeOut,
        decoration: BoxDecoration(
          color: colors.assistantSurface.withValues(
            alpha: _pressed ? 0.78 : 0,
          ),
          borderRadius: BorderRadius.circular(radius.md),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(radius.md),
            onHighlightChanged: (value) {
              if (_pressed != value) {
                setState(() {
                  _pressed = value;
                });
              }
            },
            child: Padding(
              key: ValueKey('settings-row-action-${widget.title}'),
              padding: rowPadding,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
