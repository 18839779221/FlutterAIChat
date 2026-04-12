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
      secondary: colors.workflowSuccess,
      surface: colors.assistantSurface,
      onSurface: colors.primaryText,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      outlineVariant: colors.divider,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.chatBackground,
      textTheme: Typography.blackMountainView.apply(
        bodyColor: colors.primaryText,
        displayColor: colors.primaryText,
      ),
      canvasColor: colors.settingsPanelBackground,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      inputDecorationTheme: AppComponentTheme.inputDecorationTheme(
        colors,
        radius,
        spacing,
      ),
      cardTheme: AppComponentTheme.cardTheme(colors, radius),
      dividerColor: colors.divider,
      iconTheme: IconThemeData(color: colors.primaryText),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: colors.primaryText,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      extensions: <ThemeExtension<dynamic>>[
        colors,
        spacing,
        radius,
      ],
    );
  }
}
