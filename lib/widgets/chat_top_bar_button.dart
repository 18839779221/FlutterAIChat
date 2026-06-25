import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/app_theme_spec.dart';
import 'chat_header_button.dart';
import 'chat_glass_button.dart';
import 'chat_top_chrome_motion.dart';

class ChatTopBarButton extends StatefulWidget {
  const ChatTopBarButton({
    super.key,
    this.shellKey,
    this.buttonKey,
    required this.tooltip,
    required this.onPressed,
    this.onLongPress,
    this.icon,
    this.label,
    this.width,
    this.shadowSpec = const ChatHeaderButtonShadowSpec(),
    this.motion,
  }) : assert(icon != null || label != null);

  final Key? shellKey;
  final Key? buttonKey;
  final String tooltip;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final IconData? icon;
  final String? label;
  final double? width;
  final ChatHeaderButtonShadowSpec shadowSpec;
  final ChatTopChromeMotion? motion;

  @override
  State<ChatTopBarButton> createState() => _ChatTopBarButtonState();
}

class _ChatTopBarButtonState extends State<ChatTopBarButton> {
  bool _pressed = false;

  static const _glassGradientColors = <Color>[
    Color(0xF2FFFFFF),
    Color(0xDFFFFFFF),
    Color(0xBEFFFDFC),
  ];
  static const _glassBorderColor = Color(0x46FFFFFF);
  static const _glassEdgeGlowColor = Color(0x9CFFFFFF);
  static const _glassTopHighlightColors = <Color>[
    Color(0xFFFFFFFF),
    Color(0x00FFFFFF),
  ];

  void _setPressed(bool value) {
    if (widget.onPressed == null) {
      return;
    }
    if (_pressed != value) {
      setState(() {
        _pressed = value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final hasLabel = widget.label != null;
    final motion = widget.motion ?? ChatTopChromeMotion.fromProgress(0);
    final materialFocus = motion.materialFocusProgress;
    final gatheredHighlight = motion.centerSettleProgress;
    final shadowTighten = motion.shadowTightenProgress;

    final gradientColors = <Color>[
      Color.lerp(
        _glassGradientColors[0],
        const Color(0xFCFFFFFF),
        materialFocus,
      )!,
      Color.lerp(
        _glassGradientColors[1],
        const Color(0xEDFFFFFF),
        materialFocus,
      )!,
      Color.lerp(
        _glassGradientColors[2],
        const Color(0xD0FFFDFC),
        materialFocus,
      )!,
    ];
    final topHighlightColors = <Color>[
      Color.lerp(
        _glassTopHighlightColors[0],
        const Color(0xFFFFFFFF),
        gatheredHighlight,
      )!,
      Color.lerp(
        const Color(0x14FFFFFF),
        const Color(0x06FFFFFF),
        materialFocus,
      )!,
    ];
    final surfaceOverlayColors = <Color>[
      Colors.white.withValues(
        alpha: lerpDouble(0.1, 0.16, gatheredHighlight)!,
      ),
      Colors.white.withValues(
        alpha: lerpDouble(0.025, 0.045, materialFocus)!,
      ),
      Color.lerp(
        const Color(0x08E4DED5),
        const Color(0x0CFFF8F0),
        materialFocus,
      )!,
    ];

    return KeyedSubtree(
      key: widget.shellKey,
      child: Tooltip(
        message: widget.tooltip,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _setPressed(true),
          onPointerUp: (_) => _setPressed(false),
          onPointerCancel: (_) => _setPressed(false),
          child: ChatGlassButton(
            buttonKey: widget.buttonKey,
            leadingIcon: widget.icon,
            label: widget.label,
            onPressed: widget.onPressed,
            onLongPress: widget.onLongPress,
            enabled: widget.onPressed != null,
            minWidth: hasLabel ? widget.width : null,
            maxTextWidth: hasLabel
                ? ((widget.width ?? 170) - 52).clamp(48.0, 180.0)
                : null,
            height: 46,
            iconSize: hasLabel ? 15.5 : 17.5,
            gradientColors: gradientColors,
            borderColor: Color.lerp(
              _glassBorderColor,
              const Color(0x52FFFFFF),
              materialFocus,
            ),
            edgeGlowColor: Color.lerp(
              _glassEdgeGlowColor,
              const Color(0xBAFFFFFF),
              materialFocus,
            ),
            topHighlightColors: topHighlightColors,
            surfaceOverlayColors: surfaceOverlayColors,
            backdropBlurSigma: lerpDouble(36, 30, materialFocus)!,
            borderWidth: lerpDouble(0.6, 0.76, materialFocus)!,
            edgeGlowPrimaryBlur: lerpDouble(30, 24, materialFocus)!,
            edgeGlowPrimarySpread: lerpDouble(2.0, 1.5, materialFocus)!,
            edgeGlowPrimaryOffset: Offset(
              0,
              lerpDouble(-2.1, -1.6, materialFocus)!,
            ),
            edgeGlowSecondaryBlur: lerpDouble(46, 36, materialFocus)!,
            edgeGlowSecondarySpread: lerpDouble(4.2, 3.0, materialFocus)!,
            edgeGlowSecondaryAlphaMultiplier: lerpDouble(
              0.32,
              0.28,
              materialFocus,
            )!,
            boxShadows: _tightenShadows(
              widget.shadowSpec.resolve(colors, _pressed),
              shadowTighten,
            ),
          ),
        ),
      ),
    );
  }

  List<BoxShadow> _tightenShadows(
    List<BoxShadow> shadows,
    double progress,
  ) {
    return shadows
        .map(
          (shadow) => shadow.copyWith(
            blurRadius: lerpDouble(
              shadow.blurRadius,
              shadow.blurRadius * 0.76,
              progress,
            ),
            spreadRadius: lerpDouble(
              shadow.spreadRadius,
              shadow.spreadRadius * 0.88,
              progress,
            ),
            offset: Offset(
              shadow.offset.dx,
              lerpDouble(shadow.offset.dy, shadow.offset.dy * 0.72, progress)!,
            ),
          ),
        )
        .toList(growable: false);
  }
}
