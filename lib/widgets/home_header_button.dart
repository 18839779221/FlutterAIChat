import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_spec.dart';

/// Shared glass button used by the homepage header and the lab preview.
class HomeHeaderButton extends StatefulWidget {
  final Key? shellKey;
  final Key? buttonKey;
  final String tooltip;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final bool filled;
  final IconData? icon;
  final String? label;
  final double? maxLabelWidth;

  const HomeHeaderButton({
    super.key,
    this.shellKey,
    this.buttonKey,
    required this.tooltip,
    required this.onPressed,
    this.onLongPress,
    this.filled = false,
    this.icon,
    this.label,
    this.maxLabelWidth,
  }) : assert(icon != null || label != null);

  bool get _isLabelButton => label != null;

  @override
  State<HomeHeaderButton> createState() => _HomeHeaderButtonState();
}

class _HomeHeaderButtonState extends State<HomeHeaderButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final isLabelButton = widget._isLabelButton;
    const iconButtonSize = 46.0;
    const labelButtonHeight = 46.0;
    final labelHorizontalPadding = spacing.sm + 1;
    final maxButtonWidth = widget.maxLabelWidth;
    final maxTextWidth = maxButtonWidth == null
        ? null
        : (maxButtonWidth - labelHorizontalPadding * 2 - 4).clamp(24.0, 240.0);

    final isActivePressed = _pressed && widget.onPressed != null;

    return AnimatedScale(
      scale: isActivePressed ? 0.92 : 1,
      duration: Duration(milliseconds: isActivePressed ? 90 : 240),
      curve: isActivePressed ? Curves.easeOutCubic : Curves.easeOutBack,
      child: Material(
        key: widget.shellKey,
        color: Colors.transparent,
        child: Tooltip(
          message: widget.tooltip,
          child: InkWell(
            key: widget.buttonKey,
            customBorder: isLabelButton
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radius.pill),
                  )
                : const CircleBorder(),
            onTap: widget.onPressed,
            onLongPress: widget.onPressed == null ? null : widget.onLongPress,
            onHighlightChanged: (value) {
              if (_pressed != value) {
                setState(() {
                  _pressed = value;
                });
              }
            },
            child: AnimatedContainer(
              duration: Duration(milliseconds: isActivePressed ? 90 : 240),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                shape: isLabelButton ? BoxShape.rectangle : BoxShape.circle,
                borderRadius:
                    isLabelButton ? BorderRadius.circular(radius.pill) : null,
                boxShadow: [
                  BoxShadow(
                    color: colors.core.elevation.shadowColor
                        .withValues(alpha: isActivePressed ? 0.07 : 0.12),
                    blurRadius: isActivePressed ? 12 : 24,
                    spreadRadius: -2,
                    offset: Offset(0, isActivePressed ? 4 : 9),
                  ),
                  BoxShadow(
                    color: colors.core.elevation.shadowColor
                        .withValues(alpha: isActivePressed ? 0.06 : 0.09),
                    blurRadius: isActivePressed ? 6 : 10,
                    spreadRadius: -1,
                    offset: Offset(0, isActivePressed ? 2 : 4),
                  ),
                  BoxShadow(
                    color: colors.semantic.text.inverse.withValues(alpha: 0.24),
                    blurRadius: 6,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius.pill),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape:
                          isLabelButton ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius: isLabelButton
                          ? BorderRadius.circular(radius.pill)
                          : null,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colors.assistantSurface
                              .withValues(alpha: widget.filled ? 0.28 : 0.24),
                          colors.assistantSurface
                              .withValues(alpha: widget.filled ? 0.52 : 0.46),
                          colors.assistantSurface
                              .withValues(alpha: widget.filled ? 0.72 : 0.66),
                        ],
                        stops: const [0, 0.42, 1],
                      ),
                      border: Border.all(
                        color: colors.assistantSurface.withValues(
                          alpha: widget.filled ? 0.95 : 0.85,
                        ),
                        width: 1.5,
                      ),
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 110),
                      curve: Curves.easeOutCubic,
                      width: isLabelButton ? null : iconButtonSize,
                      height:
                          isLabelButton ? labelButtonHeight : iconButtonSize,
                      constraints: isLabelButton && maxButtonWidth != null
                          ? BoxConstraints(maxWidth: maxButtonWidth)
                          : null,
                      padding: EdgeInsets.symmetric(
                        horizontal: isLabelButton ? labelHorizontalPadding : 0,
                        vertical: 0,
                      ),
                      alignment: Alignment.center,
                      child: isLabelButton
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: maxTextWidth ?? 120,
                                    ),
                                    child: Text(
                                      widget.label!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: false,
                                      style: TextStyle(
                                        color: widget.onPressed == null
                                            ? colors.secondaryText
                                                .withValues(alpha: 0.45)
                                            : colors.primaryText
                                                .withValues(alpha: 0.94),
                                        fontSize: 12.2,
                                        fontWeight: FontWeight.w600,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Icon(
                              widget.icon,
                              size: 17.5,
                              color: widget.onPressed == null
                                  ? colors.secondaryText.withValues(alpha: 0.45)
                                  : colors.primaryText.withValues(alpha: 0.9),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
