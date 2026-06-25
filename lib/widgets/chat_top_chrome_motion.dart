import 'package:flutter/material.dart';

/// Shared motion snapshot for the home top chrome.
///
/// All chrome-related surfaces derive their visual state from the same
/// normalized gather progress so Lab and production stay on one path.
@immutable
class ChatTopChromeMotion {
  const ChatTopChromeMotion._({
    required this.chromeGatherProgress,
    required this.groupInsetProgress,
    required this.materialFocusProgress,
    required this.shadowTightenProgress,
    required this.centerSettleProgress,
  });

  static const double defaultTransitionDistance = 36;

  final double chromeGatherProgress;
  final double groupInsetProgress;
  final double materialFocusProgress;
  final double shadowTightenProgress;
  final double centerSettleProgress;

  factory ChatTopChromeMotion.fromScrollOffset({
    required double offset,
    double transitionDistance = defaultTransitionDistance,
  }) {
    final clampedDistance = transitionDistance <= 0
        ? defaultTransitionDistance
        : transitionDistance;
    final normalized = (offset / clampedDistance).clamp(0.0, 1.0).toDouble();
    return ChatTopChromeMotion.fromProgress(normalized);
  }

  factory ChatTopChromeMotion.fromProgress(double progress) {
    final clampedProgress = progress.clamp(0.0, 1.0).toDouble();

    return ChatTopChromeMotion._(
      chromeGatherProgress: clampedProgress,
      groupInsetProgress: Curves.easeOutCubic.transform(clampedProgress),
      materialFocusProgress: Curves.easeOutQuart.transform(clampedProgress),
      shadowTightenProgress: _delayedProgress(
        clampedProgress,
        begin: 0.12,
        end: 0.92,
        curve: Curves.easeOutCubic,
      ),
      centerSettleProgress: _delayedProgress(
        clampedProgress,
        begin: 0.18,
        end: 1.0,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  static double _delayedProgress(
    double progress, {
    required double begin,
    required double end,
    required Curve curve,
  }) {
    if (progress <= begin) {
      return 0;
    }
    if (progress >= end) {
      return 1;
    }

    final normalized =
        ((progress - begin) / (end - begin)).clamp(0.0, 1.0).toDouble();
    return curve.transform(normalized);
  }
}
