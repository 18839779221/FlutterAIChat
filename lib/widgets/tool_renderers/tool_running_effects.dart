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
  });

  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final bool isRunning;

  @override
  State<RunningSweepSurface> createState() => _RunningSweepSurfaceState();
}

class _RunningSweepSurfaceState extends State<RunningSweepSurface>
    with SingleTickerProviderStateMixin {
  static const String _animationDebugTag = 'ToolAnimationDebug';
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
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
                    top: -constraints.maxHeight * 0.28,
                    bottom: -constraints.maxHeight * 0.28,
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
                                Colors.white.withValues(alpha: 0.18),
                                Colors.white.withValues(alpha: 0.42),
                                Colors.white.withValues(alpha: 0.18),
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
