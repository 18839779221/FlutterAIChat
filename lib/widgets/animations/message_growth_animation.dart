import 'package:flutter/material.dart';

/// Message growth animation - messages "grow" into view rather than suddenly appear.
///
/// Combines fade, slide, and scale for a natural appearance that matches
/// the rhythm of conversation. Based on Claude's message appearance pattern.
class MessageGrowthAnimation extends StatelessWidget {
  final Widget child;
  final Duration? duration;
  final Curve? curve;

  const MessageGrowthAnimation({
    super.key,
    required this.child,
    this.duration,
    this.curve,
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
            offset: Offset(0, 20 * (1 - value)), // Slide up from 20px below
            child: Transform.scale(
              scale: 0.96 + (0.04 * value), // Scale from 96% to 100%
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
