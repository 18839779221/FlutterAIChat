import 'package:ai_chat/models/session/context_window_segment.dart';
import 'package:ai_chat/models/session/context_window_snapshot.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/widgets/context_window/context_window_usage_color.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final colors = AppThemeSpec.light();

  ContextWindowSnapshot snapshot(double ratio) {
    return ContextWindowSnapshot(
      modelName: 'gpt-test',
      maxContextTokens: 128000,
      effectiveInputBudget: 104000,
      autoCompactTriggerTokens: 91000,
      totalEstimatedInputTokens: 0,
      plannerInputUsageRatio: 0.0,
      totalWindowUsageRatio: ratio,
      effectiveInputUsageRatio: 0.0,
      didCompactHistory: false,
      recentCompletedTurnCount: 0,
      segments: const <ContextWindowSegment>[],
    );
  }

  test('low ratio uses secondaryText base color', () {
    final color = resolveContextWindowUsageColor(colors, snapshot(0.2));
    expect(
      color.toARGB32(),
      colors.secondaryText.withValues(alpha: 0.48).toARGB32(),
    );
  });

  test('mid ratio uses workflowRunning', () {
    final color = resolveContextWindowUsageColor(colors, snapshot(0.85));
    expect(
      color.toARGB32(),
      colors.workflowRunning.withValues(alpha: 0.64).toARGB32(),
    );
  });

  test('at or above trigger uses workflowWarning', () {
    final color = resolveContextWindowUsageColor(colors, snapshot(1.0));
    expect(
      color.toARGB32(),
      colors.workflowWarning.withValues(alpha: 0.72).toARGB32(),
    );
  });
}
