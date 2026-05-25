import 'package:ai_chat/theme/app_motion.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light theme exposes theme spec extensions', () {
    final theme = AppTheme.light();

    expect(theme.extension<AppThemeSpec>(), isNotNull);
    expect(theme.extension<AppSpacing>(), isNotNull);
    expect(theme.extension<AppRadius>(), isNotNull);
    expect(theme.extension<AppMotion>(), isNotNull);
  });

  test('light theme exposes calm light chat semantics', () {
    final theme = AppTheme.light();
    final spec = AppTheme.light().extension<AppThemeSpec>();

    expect(theme.colorScheme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF5F4EE));
    expect(spec, isNotNull);
    expect(spec!.id, 'claude');
    expect(spec.chatBackground, const Color(0xFFF5F4EE));
    expect(spec.settingsPanelBackground, const Color(0xFFF0EEE6));
    expect(spec.toolWorkflowSurface, const Color(0xFFF5F2EA));
  });

  test('claude theme exposes artifact and chart semantic tokens', () {
    final spec = AppThemeSpec.claude();

    expect(spec.artifactPageBackground, const Color(0xFFF5F4EE));
    expect(spec.artifactSurface, const Color(0xFFFAF9F5));
    expect(spec.artifactSurfaceMuted, const Color(0xFFF2F1EB));
    expect(spec.artifactTextPrimary, const Color(0xFF1F1F1E));
    expect(spec.artifactTextSecondary, const Color(0xFF3D3D3A));
    expect(spec.artifactTextTertiary, const Color(0xFF75726A));
    expect(spec.artifactBorderSubtle, const Color(0xFFE8E6DC));
    expect(spec.artifactBorderStrong, const Color(0xFFD9D6CC));
    expect(spec.artifactAccent, const Color(0xFFC96442));
    expect(spec.artifactChart1, isA<Color>());
    expect(spec.artifactChart2, isA<Color>());
    expect(spec.artifactChart3, isA<Color>());
    expect(spec.artifactChart4, isA<Color>());
    expect(spec.artifactChart5, isA<Color>());
    expect(spec.artifactChartGrid, isA<Color>());
    expect(spec.artifactChartAxis, isA<Color>());
    expect(spec.artifactChartHighlight, isA<Color>());
  });

  test('olive paper theme exposes artifact and chart semantic tokens', () {
    final spec = AppThemeSpec.olivePaper();

    expect(spec.artifactPageBackground, const Color(0xFFF3F1EC));
    expect(spec.artifactSurface, const Color(0xFFECE7DE));
    expect(spec.artifactSurfaceMuted, const Color(0xFFE1E8DE));
    expect(spec.artifactTextPrimary, const Color(0xFF182019));
    expect(spec.artifactTextSecondary, const Color(0xFF596259));
    expect(spec.artifactTextTertiary, const Color(0xFF73796F));
    expect(spec.artifactBorderSubtle, const Color(0x2E20281F));
    expect(spec.artifactBorderStrong, const Color(0x664F5F55));
    expect(spec.artifactAccent, const Color(0xFF35594A));
    expect(spec.artifactChart1, isA<Color>());
    expect(spec.artifactChart2, isA<Color>());
    expect(spec.artifactChart3, isA<Color>());
    expect(spec.artifactChart4, isA<Color>());
    expect(spec.artifactChart5, isA<Color>());
    expect(spec.artifactChartGrid, isA<Color>());
    expect(spec.artifactChartAxis, isA<Color>());
    expect(spec.artifactChartHighlight, isA<Color>());
  });
}
