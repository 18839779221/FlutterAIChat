import 'package:flutter/material.dart';

import 'app_theme_spec.dart';

/// Shared component defaults so pages read as one design system.
class AppComponentTheme {
  static InputDecorationTheme inputDecorationTheme(
    AppThemeSpec spec,
  ) {
    final colors = spec.semantic;
    final radius = spec.core.radius;
    final spacing = spec.core.spacing;
    return InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaces.readingSurface,
      hintStyle: TextStyle(
        color: colors.text.tertiary,
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: spacing.md,
        vertical: spacing.sm,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius.lg),
        borderSide: BorderSide(color: colors.interaction.subtleBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius.lg),
        borderSide: BorderSide(color: colors.interaction.subtleBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius.lg),
        borderSide: BorderSide(color: colors.state.running, width: 1.2),
      ),
    );
  }

  static CardThemeData cardTheme(AppThemeSpec spec) {
    final colors = spec.semantic;
    final radius = spec.core.radius;
    return CardThemeData(
      color: colors.surfaces.readingSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius.md),
        side: BorderSide(color: colors.interaction.subtleBorder),
      ),
    );
  }
}
