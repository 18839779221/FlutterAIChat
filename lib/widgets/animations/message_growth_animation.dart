import 'package:flutter/material.dart';

/// Message growth animation - messages "grow" into view rather than suddenly appear.
///
/// Combines fade, slide, and scale for a natural appearance that matches
/// the rhythm of conversation. Based on Claude's message appearance pattern.
class MessageGrowthAnimation extends StatelessWidget {
  final Widget child;
  final Duration? duration;
  final Curve? curve;
  final double offsetY;
  final double beginScale;

  const MessageGrowthAnimation({
    super.key,
    required this.child,
    this.duration,
    this.curve,
    this.offsetY = 10,
    this.beginScale = 0.985,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: duration ?? const Duration(milliseconds: 300),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: curve ?? Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, offsetY * (1 - value)),
            child: Transform.scale(
              scale: beginScale + ((1 - beginScale) * value),
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}
