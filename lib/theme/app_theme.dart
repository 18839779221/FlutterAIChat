import 'package:flutter/material.dart';

import 'app_component_theme.dart';
import 'app_theme_spec.dart';

/// Central app theme entry point.
class AppTheme {
  static ThemeData light() {
    return fromSpec(AppThemeSpec.light());
  }

  static ThemeData dark() {
    return fromSpec(AppThemeSpec.dark());
  }

  static ThemeData fromSpec(AppThemeSpec spec) {
    final colorScheme = (spec.brightness == Brightness.dark
            ? const ColorScheme.dark()
            : const ColorScheme.light())
        .copyWith(
      primary: spec.workflowRunning,
      secondary: spec.workflowSuccess,
      surface: spec.assistantSurface,
      onSurface: spec.primaryText,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      outlineVariant: spec.divider,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: spec.core.typography.uiFontFamily,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: spec.chatBackground,
      textTheme: (spec.brightness == Brightness.dark
              ? Typography.whiteMountainView
              : Typography.blackMountainView)
          .apply(
        bodyColor: spec.primaryText,
        displayColor: spec.primaryText,
      ),
      canvasColor: spec.settingsPanelBackground,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      inputDecorationTheme: AppComponentTheme.inputDecorationTheme(
        spec,
      ),
      cardTheme: AppComponentTheme.cardTheme(spec),
      dividerColor: spec.divider,
      iconTheme: IconThemeData(color: spec.primaryText),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: spec.primaryText,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      extensions: <ThemeExtension<dynamic>>[
        spec,
        spec.core.spacing,
        spec.core.radius,
        spec.core.motion,
      ],
    );
  }
}
