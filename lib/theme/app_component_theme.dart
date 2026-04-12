import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_spacing.dart';

/// Shared component defaults so pages read as one design system.
class AppComponentTheme {
  static InputDecorationTheme inputDecorationTheme(
    AppColors colors,
    AppRadius radius,
    AppSpacing spacing,
  ) {
    return InputDecorationTheme(
      filled: true,
      fillColor: colors.assistantSurface,
      contentPadding: EdgeInsets.symmetric(
        horizontal: spacing.md,
        vertical: spacing.sm,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius.lg),
        borderSide: BorderSide(color: colors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius.lg),
        borderSide: BorderSide(color: colors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius.lg),
        borderSide: BorderSide(color: colors.workflowRunning, width: 1.2),
      ),
    );
  }

  static CardThemeData cardTheme(
    AppColors colors,
    AppRadius radius,
  ) {
    return CardThemeData(
      color: colors.assistantSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius.md),
        side: BorderSide(color: colors.divider),
      ),
    );
  }
}
