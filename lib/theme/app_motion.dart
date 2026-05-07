import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Motion design system for FlutterAIChat.
///
/// Based on human perception research and aligned with Claude/Apple standards.
/// All durations and curves have scientific rationale.
@immutable
class AppMotion extends ThemeExtension<AppMotion> {
  // Duration scale based on human perception

  /// Instant feedback - based on tactile feedback delay (human finger touch)
  final Duration instant;

  /// Quick transition - based on visual tracking speed (eye movement)
  final Duration quick;

  /// Standard animation - based on word recognition time (reading rhythm)
  final Duration standard;

  /// Emphasized animation - based on spatial perception (room size judgment)
  final Duration emphasized;

  /// Gentle animation - based on attention shift cycle
  final Duration gentle;

  // Loop animation rhythms

  /// Pulse rhythm - based on resting breathing cycle (12-20 breaths/min)
  final Duration pulse;

  /// Sweep rhythm - based on visual scanning speed (reading a line)
  final Duration sweep;

  /// Ambient rhythm - background animation that doesn't distract
  final Duration ambient;

  // Easing curves

  /// Element enter - fast response, slow stop (matches physical inertia)
  final Curve easeOut;

  /// Element exit - slow start, fast disappear (reduces distraction)
  final Curve easeIn;

  /// Element move - natural acceleration and deceleration
  final Curve easeInOut;

  /// Spring effect - completion moment ceremony (tool execution complete)
  final Curve spring;

  /// Breathing curve - smooth loop animation (no jank)
  final Curve breathing;

  /// Gentle curve - slow transition for large areas
  final Curve gentleCurve;

  const AppMotion({
    required this.instant,
    required this.quick,
    required this.standard,
    required this.emphasized,
    required this.gentle,
    required this.pulse,
    required this.sweep,
    required this.ambient,
    required this.easeOut,
    required this.easeIn,
    required this.easeInOut,
    required this.spring,
    required this.breathing,
    required this.gentleCurve,
  });

  factory AppMotion.base() {
    return const AppMotion(
      // Durations
      instant: Duration(milliseconds: 100),
      quick: Duration(milliseconds: 200),
      standard: Duration(milliseconds: 300),
      emphasized: Duration(milliseconds: 400),
      gentle: Duration(milliseconds: 600),
      pulse: Duration(milliseconds: 800),
      sweep: Duration(milliseconds: 1200),
      ambient: Duration(milliseconds: 2000),
      // Curves
      easeOut: Curves.easeOutCubic,
      easeIn: Curves.easeInCubic,
      easeInOut: Curves.easeInOutCubic,
      spring: Curves.elasticOut,
      breathing: Curves.easeInOutSine,
      gentleCurve: Curves.easeOutQuart,
    );
  }

  @override
  ThemeExtension<AppMotion> copyWith({
    Duration? instant,
    Duration? quick,
    Duration? standard,
    Duration? emphasized,
    Duration? gentle,
    Duration? pulse,
    Duration? sweep,
    Duration? ambient,
    Curve? easeOut,
    Curve? easeIn,
    Curve? easeInOut,
    Curve? spring,
    Curve? breathing,
    Curve? gentleCurve,
  }) {
    return AppMotion(
      instant: instant ?? this.instant,
      quick: quick ?? this.quick,
      standard: standard ?? this.standard,
      emphasized: emphasized ?? this.emphasized,
      gentle: gentle ?? this.gentle,
      pulse: pulse ?? this.pulse,
      sweep: sweep ?? this.sweep,
      ambient: ambient ?? this.ambient,
      easeOut: easeOut ?? this.easeOut,
      easeIn: easeIn ?? this.easeIn,
      easeInOut: easeInOut ?? this.easeInOut,
      spring: spring ?? this.spring,
      breathing: breathing ?? this.breathing,
      gentleCurve: gentleCurve ?? this.gentleCurve,
    );
  }

  @override
  ThemeExtension<AppMotion> lerp(
    covariant ThemeExtension<AppMotion>? other,
    double t,
  ) {
    if (other is! AppMotion) {
      return this;
    }
    return AppMotion(
      instant: Duration(
        milliseconds: lerpDouble(
          instant.inMilliseconds,
          other.instant.inMilliseconds,
          t,
        )!.round(),
      ),
      quick: Duration(
        milliseconds: lerpDouble(
          quick.inMilliseconds,
          other.quick.inMilliseconds,
          t,
        )!.round(),
      ),
      standard: Duration(
        milliseconds: lerpDouble(
          standard.inMilliseconds,
          other.standard.inMilliseconds,
          t,
        )!.round(),
      ),
      emphasized: Duration(
        milliseconds: lerpDouble(
          emphasized.inMilliseconds,
          other.emphasized.inMilliseconds,
          t,
        )!.round(),
      ),
      gentle: Duration(
        milliseconds: lerpDouble(
          gentle.inMilliseconds,
          other.gentle.inMilliseconds,
          t,
        )!.round(),
      ),
      pulse: Duration(
        milliseconds: lerpDouble(
          pulse.inMilliseconds,
          other.pulse.inMilliseconds,
          t,
        )!.round(),
      ),
      sweep: Duration(
        milliseconds: lerpDouble(
          sweep.inMilliseconds,
          other.sweep.inMilliseconds,
          t,
        )!.round(),
      ),
      ambient: Duration(
        milliseconds: lerpDouble(
          ambient.inMilliseconds,
          other.ambient.inMilliseconds,
          t,
        )!.round(),
      ),
      easeOut: easeOut,
      easeIn: easeIn,
      easeInOut: easeInOut,
      spring: spring,
      breathing: breathing,
      gentleCurve: gentleCurve,
    );
  }
}
