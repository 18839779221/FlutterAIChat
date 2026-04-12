import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light theme exposes semantic extensions', () {
    final theme = AppTheme.light();

    expect(theme.extension<AppColors>(), isNotNull);
    expect(theme.extension<AppSpacing>(), isNotNull);
    expect(theme.extension<AppRadius>(), isNotNull);
  });

  test('light theme exposes calm light chat semantics', () {
    final theme = AppTheme.light();
    final colors = AppTheme.light().extension<AppColors>();

    expect(theme.colorScheme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF3F1EC));
    expect(colors, isNotNull);
    expect(colors!.chatBackground, const Color(0xFFF3F1EC));
    expect(colors.settingsPanelBackground, const Color(0xFFE3E4DE));
    expect(colors.toolWorkflowSurface, const Color(0xFFDDE4D8));
  });
}
