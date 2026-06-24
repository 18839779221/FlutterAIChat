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
        EdgeInsets.symmetric(horizontal: spacing.lg, vertical: spacing.sm);

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.leading != null) ...[
          Padding(
            padding: EdgeInsets.only(top: widget.subtitle == null ? 2 : 3),
            child: SizedBox(
              width: 18,
              child: Align(
                alignment: Alignment.topLeft,
                child: IconTheme(
                  data: IconThemeData(
                    size: 16,
                    color: colors.secondaryText.withValues(alpha: 0.8),
                  ),
                  child: widget.leading!,
                ),
              ),
            ),
          ),
          SizedBox(width: spacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w400,
                      fontSize: 14,
                      height: 1.18,
                    ),
              ),
              if (widget.subtitle != null) ...[
                SizedBox(height: spacing.xxs + 1),
                Text(
                  widget.subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                        height: 1.3,
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
              constraints: const BoxConstraints(maxWidth: 180),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: widget.trailing),
                  if (isAction) ...[
                    SizedBox(width: spacing.xxs + 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: colors.secondaryText.withValues(alpha: 0.72),
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
            alpha: _pressed ? 0.72 : 0,
          ),
          borderRadius: BorderRadius.circular(radius.lg),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(radius.lg),
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
