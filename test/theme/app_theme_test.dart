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
}
