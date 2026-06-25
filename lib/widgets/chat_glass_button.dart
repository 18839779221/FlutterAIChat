import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_spec.dart';
import '../theme/app_typography.dart';

/// Shared frosted/glass button surface used by composer and top bar chrome.
class ChatGlassButton extends StatelessWidget {
  const ChatGlassButton({
    super.key,
    this.buttonKey,
    this.leadingIcon,
    this.boxShadows = const <BoxShadow>[],
    this.gradientColors,
    this.disabledGradientColors,
    this.borderColor,
    this.edgeGlowColor,
    this.topHighlightColors,
    this.label,
    required this.onPressed,
    this.onLongPress,
    required this.enabled,
    this.maxTextWidth,
    this.minWidth,
    this.height = 28,
    this.horizontalPadding,
    this.iconSize = 15.5,
    this.backdropBlurSigma = 30,
    this.borderWidth = 0.85,
    this.surfaceOverlayColors,
    this.edgeGlowPrimaryBlur = 18,
    this.edgeGlowPrimarySpread = 1.2,
    this.edgeGlowPrimaryOffset = const Offset(0, -1.5),
    this.edgeGlowSecondaryBlur = 28,
    this.edgeGlowSecondarySpread = 2.2,
    this.edgeGlowSecondaryAlphaMultiplier = 0.38,
    this.edgeGlowSecondaryOffset = const Offset(0, 0),
  }) : assert(label != null || leadingIcon != null);

  final Key? buttonKey;
  final IconData? leadingIcon;
  final List<BoxShadow> boxShadows;
  final List<Color>? gradientColors;
  final List<Color>? disabledGradientColors;
  final Color? borderColor;
  final Color? edgeGlowColor;
  final List<Color>? topHighlightColors;
  final String? label;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final bool enabled;
  final double? maxTextWidth;
  final double? minWidth;
  final double height;
  final double? horizontalPadding;
  final double iconSize;
  final double backdropBlurSigma;
  final double borderWidth;
  final List<Color>? surfaceOverlayColors;
  final double edgeGlowPrimaryBlur;
  final double edgeGlowPrimarySpread;
  final Offset edgeGlowPrimaryOffset;
  final double edgeGlowSecondaryBlur;
  final double edgeGlowSecondarySpread;
  final double edgeGlowSecondaryAlphaMultiplier;
  final Offset edgeGlowSecondaryOffset;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final hasLabel = (label?.isNotEmpty ?? false);
    final isIconOnly = leadingIcon != null && !hasLabel;
    final resolvedHorizontalPadding = isIconOnly
        ? 0.0
        : (horizontalPadding ?? (hasLabel ? spacing.sm + 2 : 0));
    final borderRadius = BorderRadius.circular(radius.pill);
    final resolvedGradientColors = enabled
        ? (gradientColors ??
            <Color>[
              colors.semantic.text.inverse.withValues(alpha: 0.28),
              colors.assistantSurface.withValues(alpha: 0.44),
              colors.assistantSurface.withValues(alpha: 0.68),
            ])
        : (disabledGradientColors ??
            <Color>[
              colors.semantic.text.inverse.withValues(alpha: 0.14),
              colors.assistantSurface.withValues(alpha: 0.24),
              colors.assistantSurface.withValues(alpha: 0.34),
            ]);
    final resolvedBorderColor = borderColor ??
        colors.semantic.text.inverse.withValues(alpha: enabled ? 0.48 : 0.22);
    final resolvedEdgeGlowColor =
        edgeGlowColor ?? colors.semantic.text.inverse.withValues(alpha: 0.18);
    final resolvedTopHighlightColors = topHighlightColors ??
        <Color>[
          colors.semantic.text.inverse.withValues(alpha: enabled ? 0.32 : 0.14),
          colors.semantic.text.inverse.withValues(alpha: 0),
        ];

    return _PressableScale(
      enabled: enabled,
      pressedScale: 0.94,
      child: Material(
        key: buttonKey,
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          onLongPress: enabled ? onLongPress : null,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          customBorder: RoundedRectangleBorder(
            borderRadius: borderRadius,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              boxShadow: [
                BoxShadow(
                  color: resolvedEdgeGlowColor,
                  blurRadius: edgeGlowPrimaryBlur,
                  spreadRadius: edgeGlowPrimarySpread,
                  offset: edgeGlowPrimaryOffset,
                ),
                BoxShadow(
                  color: resolvedEdgeGlowColor.withValues(
                    alpha: edgeGlowSecondaryAlphaMultiplier,
                  ),
                  blurRadius: edgeGlowSecondaryBlur,
                  spreadRadius: edgeGlowSecondarySpread,
                  offset: edgeGlowSecondaryOffset,
                ),
                ...boxShadows,
              ],
            ),
            child: ClipRRect(
              borderRadius: borderRadius,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: backdropBlurSigma,
                  sigmaY: backdropBlurSigma,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: resolvedGradientColors,
                      stops: const [0, 0.32, 1],
                    ),
                    border: Border.all(
                        color: resolvedBorderColor, width: borderWidth),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 2,
                        right: 2,
                        top: 1,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(radius.pill),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: resolvedTopHighlightColors,
                              ),
                            ),
                            child: SizedBox(height: height * 0.48),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: borderRadius,
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: surfaceOverlayColors ??
                                    [
                                      Colors.white.withValues(alpha: 0.06),
                                      Colors.white.withValues(alpha: 0),
                                      const Color(0x14D8D2C7),
                                    ],
                                stops: const [0, 0.45, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isIconOnly ? height : minWidth,
                        height: height,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: resolvedHorizontalPadding,
                            vertical: (height - 1.4 * 2 - iconSize) / 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (leadingIcon != null) ...[
                                Icon(
                                  leadingIcon,
                                  size: iconSize,
                                  color: enabled
                                      ? colors.primaryText
                                          .withValues(alpha: 0.96)
                                      : colors.secondaryText
                                          .withValues(alpha: 0.45),
                                ),
                                if (hasLabel) const SizedBox(width: 4),
                              ],
                              if (hasLabel)
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: maxTextWidth ?? 160,
                                  ),
                                  child: Text(
                                    label!,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    softWrap: false,
                                    style: AppTypography.uiStyle(
                                      color: enabled
                                          ? colors.primaryText
                                          : colors.secondaryText.withValues(
                                              alpha: 0.45,
                                            ),
                                      fontSize: 12.2,
                                      fontWeight: FontWeight.w500,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
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

/// Press feedback wrapper for buttons that should keep their own tap logic.
class _PressableScale extends StatefulWidget {
  const _PressableScale({
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.9,
  });

  final Widget child;
  final bool enabled;
  final double pressedScale;

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled) {
      return;
    }
    if (_pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActivePressed = _pressed && widget.enabled;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: isActivePressed ? widget.pressedScale : 1,
        duration: Duration(milliseconds: isActivePressed ? 90 : 240),
        curve: isActivePressed ? Curves.easeOutCubic : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
