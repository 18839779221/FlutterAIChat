import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_spec.dart';
import '../theme/app_typography.dart';

class ChatHeaderButton extends StatefulWidget {
  final Key? shellKey;
  final Key? buttonKey;
  final String tooltip;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final bool filled;
  final IconData? icon;
  final String? label;
  final double? maxLabelWidth;
  final ChatHeaderButtonShadowSpec shadowSpec;

  const ChatHeaderButton({
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
    this.shadowSpec = const ChatHeaderButtonShadowSpec(),
  }) : assert(icon != null || label != null);

  bool get _isLabelButton => label != null;

  @override
  State<ChatHeaderButton> createState() => _ChatHeaderButtonState();
}

class _ChatHeaderButtonState extends State<ChatHeaderButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final isLabelButton = widget._isLabelButton;
    const buttonSize = 46.0;
    final labelHorizontalPadding = spacing.sm + 1;
    final maxButtonWidth = widget.maxLabelWidth;
    final maxTextWidth = maxButtonWidth == null
        ? null
        : (maxButtonWidth - labelHorizontalPadding * 2 - 4).clamp(24.0, 240.0);

    final isActivePressed = _pressed && widget.onPressed != null;
    final borderRadius = BorderRadius.circular(radius.pill);
    final shadowSpec = widget.shadowSpec;
    final surface = isLabelButton
        ? _buildLabelSurface(
            colors: colors,
            borderRadius: borderRadius,
            labelButtonHeight: buttonSize,
            labelHorizontalPadding: labelHorizontalPadding,
            maxButtonWidth: maxButtonWidth,
            maxTextWidth: maxTextWidth,
          )
        : _buildIconSurface(
            colors: colors,
            buttonSize: buttonSize,
          );

    return AnimatedScale(
      scale: isActivePressed ? 0.94 : 1,
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
                    borderRadius: borderRadius,
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
                borderRadius: isLabelButton ? borderRadius : null,
                boxShadow: [
                  for (final boxShadow
                      in shadowSpec.resolve(colors, isActivePressed))
                    boxShadow,
                ],
              ),
              child: surface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabelSurface({
    required AppThemeSpec colors,
    required BorderRadius borderRadius,
    required double labelButtonHeight,
    required double labelHorizontalPadding,
    required double? maxButtonWidth,
    required double? maxTextWidth,
  }) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.rectangle,
            borderRadius: borderRadius,
            color: colors.chatBackground.withValues(
              alpha: widget.filled ? 0.52 : 0.46,
            ),
            border: Border.all(
              color: colors.semantic.text.inverse.withValues(
                alpha: widget.filled ? 0.24 : 0.2,
              ),
              width: 1.5,
            ),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            height: labelButtonHeight,
            constraints: maxButtonWidth != null
                ? BoxConstraints(maxWidth: maxButtonWidth)
                : null,
            padding: EdgeInsets.symmetric(
              horizontal: labelHorizontalPadding,
              vertical: 0,
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    size: 15.5,
                    color: widget.onPressed == null
                        ? colors.secondaryText.withValues(alpha: 0.45)
                        : colors.primaryText.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 4),
                ],
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
                      style: AppTypography.uiStyle(
                        color: widget.onPressed == null
                            ? colors.secondaryText.withValues(alpha: 0.45)
                            : colors.primaryText.withValues(alpha: 0.94),
                        fontSize: 12.2,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconSurface({
    required AppThemeSpec colors,
    required double buttonSize,
  }) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.chatBackground.withValues(
              alpha: widget.filled ? 0.52 : 0.46,
            ),
            border: Border.all(
              color: colors.semantic.text.inverse.withValues(
                alpha: widget.filled ? 0.24 : 0.2,
              ),
              width: 1.5,
            ),
          ),
          child: SizedBox(
            width: buttonSize,
            height: buttonSize,
            child: Center(
              child: Icon(
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
    );
  }
}

class ChatHeaderButtonShadowSpec {
  const ChatHeaderButtonShadowSpec({
    this.nearShadowAlpha = 0.12,
    this.nearShadowBlur = 24,
    this.nearShadowOffsetY = 9,
    this.nearShadowSpread = -2,
    this.farShadowAlpha = 0.09,
    this.farShadowBlur = 10,
    this.farShadowOffsetY = 4,
    this.farShadowSpread = -1,
    this.highlightAlpha = 0.24,
  });

  final double nearShadowAlpha;
  final double nearShadowBlur;
  final double nearShadowOffsetY;
  final double nearShadowSpread;
  final double farShadowAlpha;
  final double farShadowBlur;
  final double farShadowOffsetY;
  final double farShadowSpread;
  final double highlightAlpha;

  List<BoxShadow> resolve(AppThemeSpec colors, bool isActivePressed) {
    return [
      BoxShadow(
        color: colors.core.elevation.shadowColor.withValues(
            alpha: isActivePressed ? nearShadowAlpha * 0.6 : nearShadowAlpha),
        blurRadius: isActivePressed ? nearShadowBlur * 0.5 : nearShadowBlur,
        spreadRadius: nearShadowSpread,
        offset: Offset(
            0, isActivePressed ? nearShadowOffsetY * 0.45 : nearShadowOffsetY),
      ),
      BoxShadow(
        color: colors.core.elevation.shadowColor.withValues(
            alpha: isActivePressed ? farShadowAlpha * 0.65 : farShadowAlpha),
        blurRadius: isActivePressed ? farShadowBlur * 0.55 : farShadowBlur,
        spreadRadius: farShadowSpread,
        offset: Offset(
            0, isActivePressed ? farShadowOffsetY * 0.5 : farShadowOffsetY),
      ),
      BoxShadow(
        color: colors.semantic.text.inverse.withValues(alpha: highlightAlpha),
        blurRadius: 6,
        offset: const Offset(0, -2),
      ),
    ];
  }
}
