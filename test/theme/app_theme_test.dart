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
    expect(theme.scaffoldBackgroundColor, const Color(0xFFFAF9F5));
    expect(spec, isNotNull);
    expect(spec!.id, 'claude');
    expect(spec.chatBackground, const Color(0xFFFAF9F5));
    expect(spec.settingsPanelBackground, const Color(0xFFF0EEE6));
    expect(spec.toolWorkflowSurface, const Color(0xFFEDE6D6));
    expect(
      theme.inputDecorationTheme.hintStyle?.color,
      spec.semantic.text.tertiary,
    );
  });

  test('claude theme exposes the semantic tokens that drive the UI', () {
    final spec = AppThemeSpec.claude();

    expect(spec.semantic.surfaces.pageBackground, const Color(0xFFFAF9F5));
    expect(spec.semantic.surfaces.readingSurface, const Color(0xFFFAF9F5));
    expect(spec.semantic.surfaces.toolResultSurface, const Color(0xFFE5DDC9));
    expect(spec.semantic.text.primary, const Color(0xFF1F1F1E));
    expect(spec.semantic.text.secondary, const Color(0xFF3D3D3A));
    expect(spec.semantic.text.tertiary, const Color(0xFF75726A));
    expect(spec.semantic.interaction.subtleBorder, const Color(0xFFE8E6DC));
    expect(spec.semantic.interaction.border, const Color(0xFFD9D6CC));
    expect(spec.semantic.interaction.focus, const Color(0xFFC96442));
  });

  test('olive paper theme exposes the semantic tokens that drive the UI', () {
    final spec = AppThemeSpec.olivePaper();

    expect(spec.semantic.surfaces.pageBackground, const Color(0xFFF3F1EC));
    expect(spec.semantic.surfaces.readingSurface, const Color(0xFFECE7DE));
    expect(spec.semantic.surfaces.toolResultSurface, const Color(0xFFE1E8DE));
    expect(spec.semantic.text.primary, const Color(0xFF182019));
    expect(spec.semantic.text.secondary, const Color(0xFF596259));
    expect(spec.semantic.text.tertiary, const Color(0xFF73796F));
    expect(spec.semantic.interaction.subtleBorder, const Color(0x2E20281F));
    expect(spec.semantic.interaction.border, const Color(0x664F5F55));
    expect(spec.semantic.interaction.focus, const Color(0xFF35594A));
  });
}
