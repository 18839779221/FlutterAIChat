import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_component_theme.dart';
import 'app_radius.dart';
import 'app_spacing.dart';

/// Central app theme entry point.
class AppTheme {
  static ThemeData light() {
    final colors = AppColors.light();
    final spacing = AppSpacing.base();
    final radius = AppRadius.base();
    final colorScheme = const ColorScheme.light().copyWith(
      primary: colors.workflowRunning,
      surface: colors.assistantSurface,
      onSurface: colors.primaryText,
      onPrimary: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.chatBackground,
      fontFamily: 'JetBrainsMono',
      textTheme: Typography.blackMountainView.apply(
        bodyColor: colors.primaryText,
        displayColor: colors.primaryText,
      ),
      inputDecorationTheme: AppComponentTheme.inputDecorationTheme(
        colors,
        radius,
        spacing,
      ),
      cardTheme: AppComponentTheme.cardTheme(colors, radius),
      dividerColor: colors.divider,
      extensions: <ThemeExtension<dynamic>>[
        colors,
        spacing,
        radius,
      ],
    );
  }
}
