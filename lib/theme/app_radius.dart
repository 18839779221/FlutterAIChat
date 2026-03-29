import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Shared radius scale for app surfaces.
@immutable
class AppRadius extends ThemeExtension<AppRadius> {
  final double sm;
  final double md;
  final double lg;
  final double pill;

  const AppRadius({
    required this.sm,
    required this.md,
    required this.lg,
    required this.pill,
  });

  factory AppRadius.base() {
    return const AppRadius(
      sm: 10,
      md: 12,
      lg: 16,
      pill: 999,
    );
  }

  @override
  ThemeExtension<AppRadius> copyWith({
    double? sm,
    double? md,
    double? lg,
    double? pill,
  }) {
    return AppRadius(
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      pill: pill ?? this.pill,
    );
  }

  @override
  ThemeExtension<AppRadius> lerp(
    covariant ThemeExtension<AppRadius>? other,
    double t,
  ) {
    if (other is! AppRadius) {
      return this;
    }
    return AppRadius(
      sm: lerpDouble(sm, other.sm, t)!,
      md: lerpDouble(md, other.md, t)!,
      lg: lerpDouble(lg, other.lg, t)!,
      pill: lerpDouble(pill, other.pill, t)!,
    );
  }
}
