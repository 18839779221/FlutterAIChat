import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Claude theme exposes reader-first typography roles', () {
    final theme = AppThemeSpec.claude();

    expect(theme.id, 'claude');
    expect(theme.displayName, 'Claude');
    expect(theme.brightness, Brightness.light);
    expect(theme.core.typography.documentFontFamily, 'SourceSerif4');
    expect(theme.core.typography.uiFontFamily, 'AnthropicSans');
    expect(theme.chatBackground, const Color(0xFFFAF9F5));
    expect(theme.assistantSurface, const Color(0xFFFAF9F5));
    expect(theme.toolWorkflowSurface, const Color(0xFFEDE6D6));
  });

  test('Claude theme keeps strong structural border contrast for table edges', () {
    final theme = AppThemeSpec.claude();

    expect(theme.semantic.interaction.border, const Color(0xFFD9D6CC));
    expect(theme.semantic.interaction.border.computeLuminance(),
        lessThan(theme.assistantSurface.computeLuminance()));
  });
}
