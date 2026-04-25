import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ai_chat/utils/logger.dart';

/// Gently pulses a compact status dot while a tool card is running.
class RunningStatusDot extends StatefulWidget {
  const RunningStatusDot({
    super.key,
    required this.color,
    required this.isRunning,
    this.size = 7,
    this.margin,
  });

  final Color color;
  final bool isRunning;
  final double size;
  final EdgeInsetsGeometry? margin;

  @override
  State<RunningStatusDot> createState() => _RunningStatusDotState();
}

class _RunningStatusDotState extends State<RunningStatusDot>
    with SingleTickerProviderStateMixin {
  static const String _animationDebugTag = 'ToolAnimationDebug';
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  );

  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant RunningStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isRunning != widget.isRunning) {
      _syncAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation() {
    if (widget.isRunning) {
      Logger.temp(
        _animationDebugTag,
        'status_dot_repeat',
        data: {
          'widget': 'RunningStatusDot',
          'stateHash': identityHashCode(this),
          'size': widget.size,
        },
      );
      _controller.repeat(reverse: true);
      return;
    }
    Logger.temp(
      _animationDebugTag,
      'status_dot_stop',
      data: {
        'widget': 'RunningStatusDot',
        'stateHash': identityHashCode(this),
        'size': widget.size,
      },
    );
    _controller.stop();
    _controller.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        final t = widget.isRunning ? _curve.value : 0.0;
        final scale = 1 + (0.42 * t);
        final opacity = 0.78 + (0.22 * t);
        final glowOpacity = 0.22 + (0.28 * t);

        return Container(
          width: widget.size,
          height: widget.size,
          margin: widget.margin,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: widget.isRunning
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: glowOpacity),
                      blurRadius: 10 + (8 * t),
                      spreadRadius: 1.2 + (1.8 * t),
                    ),
                  ]
                : null,
          ),
          child: Transform.scale(
            scale: scale,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Adds a very soft background breathing to low-noise running rows.
class SubtleRunningBreathingSurface extends StatefulWidget {
  const SubtleRunningBreathingSurface({
    super.key,
    required this.child,
    required this.baseColor,
    required this.borderRadius,
    required this.isRunning,
  });

  final Widget child;
  final Color baseColor;
  final BorderRadiusGeometry borderRadius;
  final bool isRunning;

  @override
  State<SubtleRunningBreathingSurface> createState() =>
      _SubtleRunningBreathingSurfaceState();
}

class _SubtleRunningBreathingSurfaceState
    extends State<SubtleRunningBreathingSurface>
    with SingleTickerProviderStateMixin {
  static const String _animationDebugTag = 'ToolAnimationDebug';
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant SubtleRunningBreathingSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isRunning != widget.isRunning) {
      _syncAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation() {
    if (widget.isRunning) {
      Logger.temp(
        _animationDebugTag,
        'breathing_surface_repeat',
        data: {
          'widget': 'SubtleRunningBreathingSurface',
          'stateHash': identityHashCode(this),
        },
      );
      _controller.repeat(reverse: true);
      return;
    }
    Logger.temp(
      _animationDebugTag,
      'breathing_surface_stop',
      data: {
        'widget': 'SubtleRunningBreathingSurface',
        'stateHash': identityHashCode(this),
      },
    );
    _controller.stop();
    _controller.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isRunning) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: widget.baseColor,
          borderRadius: widget.borderRadius,
        ),
        child: widget.child,
      );
    }

    final minAlpha = (widget.baseColor.a - 0.055).clamp(0.0, 1.0);
    final maxAlpha = (widget.baseColor.a + 0.07).clamp(0.0, 1.0);
    final colorTween = ColorTween(
      begin: widget.baseColor.withValues(alpha: minAlpha),
      end: widget.baseColor.withValues(alpha: maxAlpha),
    );

    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colorTween.evaluate(_curve) ?? widget.baseColor,
            borderRadius: widget.borderRadius,
          ),
          child: child,
        );
      },
    );
  }
}

/// Adds a faint diagonal sweep to larger running workflow cards.
class RunningSweepSurface extends StatefulWidget {
  const RunningSweepSurface({
    super.key,
    required this.child,
    required this.borderRadius,
    required this.isRunning,
    this.duration = const Duration(milliseconds: 1100),
    this.showBorder = true,
    this.sweepOpacity = 1.0,
  });

  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final bool isRunning;
  final Duration duration;
  final bool showBorder;
  final double sweepOpacity;

  @override
  State<RunningSweepSurface> createState() => _RunningSweepSurfaceState();
}

class _RunningSweepSurfaceState extends State<RunningSweepSurface>
    with SingleTickerProviderStateMixin {
  static const String _animationDebugTag = 'ToolAnimationDebug';
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant RunningSweepSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isRunning != widget.isRunning) {
      _syncAnimation();
    }
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
      if (widget.isRunning) {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation() {
    if (widget.isRunning) {
      Logger.temp(
        _animationDebugTag,
        'sweep_surface_repeat',
        data: {
          'widget': 'RunningSweepSurface',
          'stateHash': identityHashCode(this),
        },
      );
      _controller.repeat();
      return;
    }
    Logger.temp(
      _animationDebugTag,
      'sweep_surface_stop',
      data: {
        'widget': 'RunningSweepSurface',
        'stateHash': identityHashCode(this),
      },
    );
    _controller.stop();
    _controller.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isRunning) {
      return widget.child;
    }

    return ClipRRect(
      borderRadius: widget.borderRadius.resolve(Directionality.of(context)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sweepWidth = math.max(constraints.maxWidth * 0.56, 180.0);
          final travel = constraints.maxWidth + (sweepWidth * 2.5);
          final sweepHeight = constraints.hasBoundedHeight
              ? constraints.maxHeight * 1.56
              : 96.0;
          return AnimatedBuilder(
            animation: _curve,
            child: widget.child,
            builder: (context, child) {
              final left = (-sweepWidth) + (travel * _curve.value);
              final borderOpacity = 0.16 + (0.16 * _curve.value);
              return Stack(
                fit: StackFit.passthrough,
                children: [
                  child!,
                  if (widget.showBorder)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.white.withValues(alpha: borderOpacity),
                              width: 1.4,
                            ),
                            borderRadius: widget.borderRadius
                                .resolve(Directionality.of(context)),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: left,
                    top: -(sweepHeight - (constraints.hasBoundedHeight
                            ? constraints.maxHeight
                            : 0)) /
                        2,
                    height: sweepHeight,
                    child: IgnorePointer(
                      child: Transform.rotate(
                        angle: -0.32,
                        child: Container(
                          width: sweepWidth,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white.withValues(
                                  alpha: 0.18 * widget.sweepOpacity,
                                ),
                                Colors.white.withValues(
                                  alpha: 0.42 * widget.sweepOpacity,
                                ),
                                Colors.white.withValues(
                                  alpha: 0.18 * widget.sweepOpacity,
                                ),
                                Colors.white.withValues(alpha: 0),
                              ],
                              stops: const [0, 0.18, 0.5, 0.82, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Adds a low-noise sweep highlight to the text glyphs themselves.
class RunningSweepLabel extends StatefulWidget {
  const RunningSweepLabel({
    super.key,
    required this.text,
    required this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.isRunning = true,
  });

  final String text;
  final TextStyle style;
  final int maxLines;
  final TextOverflow overflow;
  final bool isRunning;

  @override
  State<RunningSweepLabel> createState() => _RunningSweepLabelState();
}

class _RunningSweepLabelState extends State<RunningSweepLabel>
    with SingleTickerProviderStateMixin {
  static const String _animationDebugTag = 'ToolAnimationDebug';
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );

  late final Animation<double> _progress = TweenSequence<double>([
    TweenSequenceItem<double>(
      tween: ConstantTween<double>(0.0),
      weight: 12,
    ),
    TweenSequenceItem<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0)
          .chain(CurveTween(curve: Curves.easeInOutCubic)),
      weight: 74,
    ),
    TweenSequenceItem<double>(
      tween: ConstantTween<double>(1.0),
      weight: 14,
    ),
  ]).animate(
    CurvedAnimation(
      parent: _controller,
      curve: Curves.linear,
    ),
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant RunningSweepLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isRunning != widget.isRunning) {
      _syncAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation() {
    if (widget.isRunning) {
      Logger.temp(
        _animationDebugTag,
        'sweep_label_repeat',
        data: {
          'widget': 'RunningSweepLabel',
          'stateHash': identityHashCode(this),
        },
      );
      _controller.repeat();
      return;
    }
    Logger.temp(
      _animationDebugTag,
      'sweep_label_stop',
      data: {
        'widget': 'RunningSweepLabel',
        'stateHash': identityHashCode(this),
      },
    );
    _controller.stop();
    _controller.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final baseText = Text(
      widget.text,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      style: widget.style,
    );
    if (!widget.isRunning) {
      return baseText;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : math.max(widget.text.length * (widget.style.fontSize ?? 12) * 0.72, 120);
        final sweepWidth = math.max(width * 0.42, 56.0);
        final travel = width + (sweepWidth * 2);
        return AnimatedBuilder(
          animation: _progress,
          builder: (context, _) {
            final left = (-sweepWidth) + (travel * _progress.value);
            return Stack(
              children: [
                baseText,
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _RunningSweepLabelPainter(
                        text: widget.text,
                        style: widget.style,
                        maxLines: widget.maxLines,
                        overflow: widget.overflow,
                        sweepOffsetX: left,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({
    required this.offsetX,
  });

  final double offsetX;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.identity()..translate(offsetX);
  }
}

class _RunningSweepLabelPainter extends CustomPainter {
  const _RunningSweepLabelPainter({
    required this.text,
    required this.style,
    required this.maxLines,
    required this.overflow,
    required this.sweepOffsetX,
  });

  final String text;
  final TextStyle style;
  final int maxLines;
  final TextOverflow overflow;
  final double sweepOffsetX;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final gradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Colors.transparent,
        Colors.white.withValues(alpha: 0.16),
        Colors.white.withValues(alpha: 0.95),
        Colors.white.withValues(alpha: 0.22),
        Colors.transparent,
      ],
      stops: const [0.0, 0.28, 0.5, 0.72, 1.0],
      transform: _SlidingGradientTransform(offsetX: sweepOffsetX),
    );

    final foregroundPaint = Paint()
      ..shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(
          foreground: foregroundPaint,
          color: null,
        ),
      ),
      maxLines: maxLines,
      ellipsis: overflow == TextOverflow.ellipsis ? '\u2026' : null,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);

    textPainter.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(covariant _RunningSweepLabelPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.style != style ||
        oldDelegate.maxLines != maxLines ||
        oldDelegate.overflow != overflow ||
        oldDelegate.sweepOffsetX != sweepOffsetX;
  }
}
