import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

const Duration kRunningCardSweepDuration = Duration(milliseconds: 2600);
const double kRunningCardSweepAngle = -0.24;
const double kRunningCardSweepWidthFactor = 0.56;
const double kRunningCardSweepOpacity = 1.08;
const Color kRunningCardSweepColor = Color(0xFFF6F6F2);

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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 920),
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
      _controller.repeat(reverse: true);
      return;
    }
    _controller.stop();
    _controller.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        final t = widget.isRunning ? _curve.value : 0.0;
        final scale = 1 + (0.18 * t);
        final opacity = 0.82 + (0.14 * t);
        final glowOpacity = 0.12 + (0.14 * t);

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
                      blurRadius: 6 + (5 * t),
                      spreadRadius: 0.4 + (0.8 * t),
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

double _measureRunningSweepTextWidth({
  required String text,
  required TextStyle style,
  required int maxLines,
  required TextOverflow overflow,
  required double maxWidth,
  required TextDirection textDirection,
}) {
  final textPainter = TextPainter(
    text: TextSpan(
      text: text,
      style: style,
    ),
    maxLines: maxLines,
    ellipsis: overflow == TextOverflow.ellipsis ? '\u2026' : null,
    textDirection: textDirection,
  )..layout(maxWidth: maxWidth);
  return math.max(textPainter.width, 24.0);
}

Duration _resolveRunningSweepCycleDuration({
  required double totalTravel,
  required double visibleTravel,
  required Duration visibleSweepDuration,
  required Duration pauseDuration,
}) {
  final visibleMicros = visibleSweepDuration.inMicroseconds.toDouble();
  final pauseMicros = pauseDuration.inMicroseconds.toDouble();
  final travelRatio = totalTravel / math.max(visibleTravel, 1);
  final totalMicros = (pauseMicros + (visibleMicros * travelRatio)).round();
  return Duration(
    microseconds: totalMicros.clamp(900000, 5000000),
  );
}

double _resolveRunningSweepPauseFraction({
  required Duration cycleDuration,
  required Duration pauseDuration,
}) {
  final pauseMicros = pauseDuration.inMicroseconds.toDouble() / 2;
  final cycleMicros = cycleDuration.inMicroseconds.toDouble();
  return (pauseMicros / math.max(cycleMicros, 1)).clamp(0.04, 0.18);
}

double _resolveRunningSweepProgress({
  required double rawProgress,
  required double pauseFraction,
}) {
  final activeFraction = (1 - (pauseFraction * 2)).clamp(0.2, 1.0);
  if (rawProgress <= pauseFraction) {
    return 0.0;
  }
  if (rawProgress >= 1 - pauseFraction) {
    return 1.0;
  }
  return ((rawProgress - pauseFraction) / activeFraction).clamp(0.0, 1.0);
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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
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
      _controller.repeat(reverse: true);
      return;
    }
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

    final minAlpha = (widget.baseColor.a - 0.03).clamp(0.0, 1.0);
    final maxAlpha = (widget.baseColor.a + 0.04).clamp(0.0, 1.0);
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
    this.duration = const Duration(milliseconds: 1500),
    this.showBorder = true,
    this.sweepOpacity = 1.0,
    this.sweepAngle = -0.32,
    this.travelDirection = AxisDirection.right,
    this.sweepColor,
    this.activeSweepFraction = 1.0,
    this.usePreciseChildExtent = false,
    this.widthFactor = 0.34,
  });

  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final bool isRunning;
  final Duration duration;
  final bool showBorder;
  final double sweepOpacity;
  final double sweepAngle;
  final AxisDirection travelDirection;
  final Color? sweepColor;
  final double activeSweepFraction;
  final bool usePreciseChildExtent;
  final double widthFactor;

  @override
  State<RunningSweepSurface> createState() => _RunningSweepSurfaceState();
}

class _RunningSweepSurfaceState extends State<RunningSweepSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  double? _measuredChildHeight;

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
      _controller.repeat();
      return;
    }
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
          final sweepWidth = math.max(
            constraints.maxWidth * widget.widthFactor.clamp(0.2, 0.7),
            120.0,
          );
          final travel = constraints.maxWidth + (sweepWidth * 2.0);
          final baseHeight = widget.usePreciseChildExtent
              ? (_measuredChildHeight ??
                  (constraints.hasBoundedHeight ? constraints.maxHeight : 96.0))
              : (constraints.hasBoundedHeight ? constraints.maxHeight : 96.0);
          final sweepHeight = widget.usePreciseChildExtent
              ? math.max(
                  baseHeight +
                      (sweepWidth * math.sin(widget.sweepAngle.abs())),
                  baseHeight,
                )
              : baseHeight * 1.56;
          return AnimatedBuilder(
            animation: _controller,
            child: _SweepMeasuredChild(
              onHeightChanged: widget.usePreciseChildExtent
                  ? (height) {
                      if ((_measuredChildHeight ?? 0) == height) {
                        return;
                      }
                      setState(() {
                        _measuredChildHeight = height;
                      });
                    }
                  : null,
              child: widget.child,
            ),
            builder: (context, child) {
              final activeSweepFraction =
                  widget.activeSweepFraction.clamp(0.05, 1.0);
              final rawProgress = _controller.value;
              final isSweepActive = rawProgress <= activeSweepFraction;
              final normalizedActiveProgress = activeSweepFraction >= 1
                  ? rawProgress
                  : (rawProgress / activeSweepFraction).clamp(0.0, 1.0);
              final easedProgress =
                  Curves.easeInOut.transform(normalizedActiveProgress);
              final progress = widget.travelDirection == AxisDirection.left
                  ? 1 - easedProgress
                  : easedProgress;
              final left = (-sweepWidth) + (travel * progress);
              final borderOpacity = 0.16 + (0.16 * easedProgress);
              final sweepColor = widget.sweepColor ?? kRunningCardSweepColor;
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
                              color:
                                  Colors.white.withValues(alpha: borderOpacity),
                              width: 1.4,
                            ),
                            borderRadius: widget.borderRadius
                                .resolve(Directionality.of(context)),
                          ),
                        ),
                      ),
                    ),
                  if (isSweepActive)
                    Positioned(
                      left: left,
                      top: widget.usePreciseChildExtent
                          ? (baseHeight - sweepHeight) / 2
                          : -(sweepHeight -
                                  (constraints.hasBoundedHeight
                                      ? constraints.maxHeight
                                      : 0)) /
                              2,
                      height: sweepHeight,
                      child: IgnorePointer(
                        child: Transform.rotate(
                          angle: widget.sweepAngle,
                          child: Container(
                            width: sweepWidth,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  sweepColor.withValues(alpha: 0),
                                  sweepColor.withValues(
                                    alpha: 0.12 * widget.sweepOpacity,
                                  ),
                                  sweepColor.withValues(
                                    alpha: 0.3 * widget.sweepOpacity,
                                  ),
                                  sweepColor.withValues(
                                    alpha: 0.46 * widget.sweepOpacity,
                                  ),
                                  sweepColor.withValues(
                                    alpha: 0.3 * widget.sweepOpacity,
                                  ),
                                  sweepColor.withValues(
                                    alpha: 0.12 * widget.sweepOpacity,
                                  ),
                                  sweepColor.withValues(alpha: 0),
                                ],
                                stops: const [
                                  0,
                                  0.16,
                                  0.34,
                                  0.5,
                                  0.66,
                                  0.84,
                                  1,
                                ],
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

class _SweepMeasuredChild extends SingleChildRenderObjectWidget {
  const _SweepMeasuredChild({
    required this.onHeightChanged,
    required super.child,
  });

  final ValueChanged<double>? onHeightChanged;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSweepMeasuredChild(onHeightChanged);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSweepMeasuredChild renderObject,
  ) {
    renderObject.onHeightChanged = onHeightChanged;
  }
}

class _RenderSweepMeasuredChild extends RenderProxyBox {
  _RenderSweepMeasuredChild(this.onHeightChanged);

  ValueChanged<double>? onHeightChanged;
  double? _lastHeight;

  @override
  void performLayout() {
    super.performLayout();
    final nextHeight = child?.size.height ?? size.height;
    if (_lastHeight == nextHeight) {
      return;
    }
    _lastHeight = nextHeight;
    if (onHeightChanged == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onHeightChanged?.call(nextHeight);
    });
  }
}

/// Drives the status-copy dot with the same sweep phase as the text highlight.
class RunningSweepStatusDot extends StatelessWidget {
  const RunningSweepStatusDot({
    super.key,
    required this.color,
    required this.isRunning,
    required this.sweepProgress,
    required this.sweepDuration,
    this.size = 7,
    this.minScale = 0.72,
    this.minOpacity = 0.6,
    this.margin,
  });

  final Color color;
  final bool isRunning;
  final double sweepProgress;
  final Duration sweepDuration;
  final double size;
  final double minScale;
  final double minOpacity;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final compression = isRunning
        ? math.sin(sweepProgress.clamp(0.0, 1.0) * math.pi)
        : 0.0;
    final scale = 1 - ((1 - minScale) * compression);
    final opacity = 1 - ((1 - minOpacity) * compression);
    final glowOpacity = (0.16 - (0.08 * compression)).clamp(0.06, 0.16);

    return Container(
      width: size,
      height: size,
      margin: margin,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: isRunning
            ? [
                BoxShadow(
                  color: color.withValues(alpha: glowOpacity),
                  blurRadius: 6 - (1.5 * compression),
                  spreadRadius: 0.42 - (0.14 * compression),
                ),
              ]
            : null,
      ),
      child: Transform.scale(
        scale: scale,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: opacity),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// Keeps the primary running status dot and text on the same sweep cadence.
class RunningSweepStatusLine extends StatefulWidget {
  const RunningSweepStatusLine({
    super.key,
    required this.text,
    required this.style,
    required this.dotColor,
    this.isRunning = true,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.visibleSweepDuration = const Duration(milliseconds: 2500),
    this.pauseDuration = const Duration(milliseconds: 340),
    this.dotSize = 7,
    this.dotSpacing = 6,
  });

  final String text;
  final TextStyle style;
  final Color dotColor;
  final bool isRunning;
  final int maxLines;
  final TextOverflow overflow;
  final Duration visibleSweepDuration;
  final Duration pauseDuration;
  final double dotSize;
  final double dotSpacing;

  @override
  State<RunningSweepStatusLine> createState() => _RunningSweepStatusLineState();
}

class _RunningSweepStatusLineState extends State<RunningSweepStatusLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.visibleSweepDuration,
  );
  Duration? _lastResolvedDuration;

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant RunningSweepStatusLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isRunning != widget.isRunning ||
        oldWidget.visibleSweepDuration != widget.visibleSweepDuration ||
        oldWidget.pauseDuration != widget.pauseDuration ||
        oldWidget.text != widget.text ||
        oldWidget.style != widget.style) {
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
      _controller.repeat();
      return;
    }
    _controller.stop();
    _controller.value = 0;
  }

  void _syncResolvedDuration(Duration duration) {
    if (_lastResolvedDuration == duration) {
      return;
    }
    _lastResolvedDuration = duration;
    _controller.duration = duration;
    if (widget.isRunning) {
      _controller.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isRunning) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RunningSweepStatusDot(
            color: widget.dotColor,
            isRunning: false,
            sweepProgress: 0,
            sweepDuration: widget.visibleSweepDuration,
            size: widget.dotSize,
          ),
          SizedBox(width: widget.dotSpacing),
          Flexible(
            child: RunningSweepText(
              text: widget.text,
              style: widget.style,
              maxLines: widget.maxLines,
              overflow: widget.overflow,
              isRunning: false,
              visibleSweepDuration: widget.visibleSweepDuration,
              pauseDuration: widget.pauseDuration,
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final textDirection = Directionality.of(context);
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : double.infinity;
        final maxTextWidth = maxWidth.isFinite
            ? math.max(maxWidth - widget.dotSize - widget.dotSpacing, 24.0)
            : double.infinity;
        final textWidth = _measureRunningSweepTextWidth(
          text: widget.text,
          style: widget.style,
          maxLines: widget.maxLines,
          overflow: widget.overflow,
          maxWidth: maxTextWidth,
          textDirection: textDirection,
        );
        final sweepWidth = math.max(textWidth * 0.72, 72.0);
        final totalTravel = textWidth + (sweepWidth * 2);
        final visibleTravel = textWidth + sweepWidth;
        final cycleDuration = _resolveRunningSweepCycleDuration(
          totalTravel: totalTravel,
          visibleTravel: visibleTravel,
          visibleSweepDuration: widget.visibleSweepDuration,
          pauseDuration: widget.pauseDuration,
        );
        _syncResolvedDuration(cycleDuration);
        final pauseFraction = _resolveRunningSweepPauseFraction(
          cycleDuration: cycleDuration,
          pauseDuration: widget.pauseDuration,
        );

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final sweepProgress = _resolveRunningSweepProgress(
              rawProgress: _controller.value,
              pauseFraction: pauseFraction,
            );
            final easedSweepProgress =
                Curves.easeInOutCubic.transform(sweepProgress);
            final sweepCenterX =
                (-sweepWidth * 0.5) + (totalTravel * easedSweepProgress);
            final dotProgress =
                (sweepCenterX / math.max(textWidth, 1)).clamp(0.0, 1.0);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RunningSweepStatusDot(
                  color: widget.dotColor,
                  isRunning: true,
                  sweepProgress: dotProgress,
                  sweepDuration: widget.visibleSweepDuration,
                  size: widget.dotSize,
                ),
                SizedBox(width: widget.dotSpacing),
                Flexible(
                  child: RunningSweepText(
                    text: widget.text,
                    style: widget.style,
                    maxLines: widget.maxLines,
                    overflow: widget.overflow,
                    isRunning: true,
                    visibleSweepDuration: widget.visibleSweepDuration,
                    pauseDuration: widget.pauseDuration,
                    externalSweepProgress: sweepProgress,
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

/// Adds a low-noise sweep highlight to the text glyphs themselves.
class RunningSweepText extends StatefulWidget {
  const RunningSweepText({
    super.key,
    required this.text,
    required this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.isRunning = true,
    this.visibleSweepDuration = const Duration(milliseconds: 2500),
    this.pauseDuration = const Duration(milliseconds: 340),
    this.externalSweepProgress,
  });

  final String text;
  final TextStyle style;
  final int maxLines;
  final TextOverflow overflow;
  final bool isRunning;
  final Duration visibleSweepDuration;
  final Duration pauseDuration;
  final double? externalSweepProgress;

  @override
  State<RunningSweepText> createState() => _RunningSweepTextState();
}

class _RunningSweepTextState extends State<RunningSweepText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2100),
  );
  Duration? _lastResolvedDuration;
  bool get _usesExternalSweepProgress => widget.externalSweepProgress != null;

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant RunningSweepText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isRunning != widget.isRunning ||
        oldWidget.visibleSweepDuration != widget.visibleSweepDuration ||
        oldWidget.pauseDuration != widget.pauseDuration ||
        oldWidget.externalSweepProgress != widget.externalSweepProgress) {
      _syncAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation() {
    if (_usesExternalSweepProgress) {
      _controller.stop();
      return;
    }
    if (widget.isRunning) {
      _controller.repeat();
      return;
    }
    _controller.stop();
    _controller.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    final defaultTextColor = DefaultTextStyle.of(context).style.color;
    final baseColor = widget.style.color ?? defaultTextColor ?? Colors.black87;
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
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : double.infinity;
        final textWidth = _measureRunningSweepTextWidth(
          text: widget.text,
          style: widget.style,
          maxLines: widget.maxLines,
          overflow: widget.overflow,
          maxWidth: maxWidth,
          textDirection: textDirection,
        );
        final sweepWidth = math.max(textWidth * 0.72, 72.0);
        final totalTravel = textWidth + (sweepWidth * 2);
        final visibleTravel = textWidth + sweepWidth;
        final cycleDuration = _resolveRunningSweepCycleDuration(
          totalTravel: totalTravel,
          visibleTravel: visibleTravel,
          visibleSweepDuration: widget.visibleSweepDuration,
          pauseDuration: widget.pauseDuration,
        );
        if (!_usesExternalSweepProgress) {
          _syncResolvedDuration(cycleDuration);
        }
        final bandFraction = (sweepWidth / math.max(totalTravel, 1)).clamp(
          0.12,
          0.48,
        );
        final leadColor = const Color(0xFFCDD0D4).withValues(
          alpha: (baseColor.a + 0.04).clamp(0.0, 1.0),
        );
        final centerColor = const Color(0xFFE8EAED).withValues(
          alpha: (baseColor.a + 0.1).clamp(0.0, 1.0),
        );
        final trailColor = const Color(0xFFD9DCE0).withValues(
          alpha: (baseColor.a + 0.06).clamp(0.0, 1.0),
        );
        Widget buildMaskedText(double sweepProgress) {
          final easedProgress =
              Curves.easeInOutCubic.transform(sweepProgress.clamp(0.0, 1.0));
          final left = (-sweepWidth) + (totalTravel * easedProgress);
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) {
              final resolvedHeight = math.max(
                bounds.height,
                widget.style.fontSize ?? 12,
              );
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  baseColor,
                  baseColor,
                  leadColor,
                  centerColor,
                  trailColor,
                  baseColor,
                  baseColor,
                ],
                stops: [
                  0.0,
                  bandFraction * 0.08,
                  bandFraction * 0.34,
                  bandFraction * 0.5,
                  bandFraction * 0.68,
                  bandFraction,
                  1.0,
                ],
                transform: _SlidingGradientTransform(offsetX: left),
              ).createShader(
                Rect.fromLTWH(0, 0, totalTravel, resolvedHeight),
              );
            },
            child: Text(
              widget.text,
              maxLines: widget.maxLines,
              overflow: widget.overflow,
              style: widget.style.copyWith(
                color: Colors.white,
                foreground: null,
              ),
            ),
          );
        }

        if (_usesExternalSweepProgress) {
          return buildMaskedText(widget.externalSweepProgress!);
        }

        final pauseFraction = _resolveRunningSweepPauseFraction(
          cycleDuration: cycleDuration,
          pauseDuration: widget.pauseDuration,
        );
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final sweepProgress = _resolveRunningSweepProgress(
              rawProgress: _controller.value,
              pauseFraction: pauseFraction,
            );
            return buildMaskedText(sweepProgress);
          },
        );
      },
    );
  }

  void _syncResolvedDuration(Duration duration) {
    if (_lastResolvedDuration == duration) {
      return;
    }
    _lastResolvedDuration = duration;
    _controller.duration = duration;
    if (widget.isRunning) {
      _controller.repeat();
    }
  }
}

@Deprecated('Use RunningSweepText instead.')
class RunningSweepLabel extends RunningSweepText {
  const RunningSweepLabel({
    super.key,
    required super.text,
    required super.style,
    super.maxLines = 1,
    super.overflow = TextOverflow.ellipsis,
    super.isRunning = true,
    super.visibleSweepDuration = const Duration(milliseconds: 2500),
    super.pauseDuration = const Duration(milliseconds: 340),
  });
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({
    required this.offsetX,
  });

  final double offsetX;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.identity()..translateByDouble(offsetX, 0, 0, 1);
  }
}
