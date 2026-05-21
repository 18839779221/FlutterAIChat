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
    expect(theme.chatBackground, const Color(0xFFF5F4EE));
    expect(theme.assistantSurface, const Color(0xFFFAF9F5));
    expect(theme.toolWorkflowSurface, const Color(0xFFF5F2EA));
  });
}
