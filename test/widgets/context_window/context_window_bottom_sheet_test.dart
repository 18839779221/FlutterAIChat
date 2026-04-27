import 'package:ai_chat/models/session/context_window_segment.dart';
import 'package:ai_chat/models/session/context_window_snapshot.dart';
import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/widgets/context_window/context_window_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'bottom sheet shows total and usable ratios with segment breakdown',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            AppColors.light(),
            AppSpacing.base(),
            AppRadius.base(),
          ],
        ),
        home: Scaffold(
          body: ContextWindowBottomSheet(
            snapshot: _snapshot(),
          ),
        ),
      ),
    );

    expect(find.text('system prompt'), findsOneWidget);
    expect(find.text('current turn transcript'), findsOneWidget);
    expect(find.text('GPT-5.4'), findsOneWidget);
    expect(find.textContaining('总窗口'), findsOneWidget);
    expect(find.textContaining('可用输入预算'), findsOneWidget);
  });
}

ContextWindowSnapshot _snapshot() {
  return ContextWindowSnapshot(
    modelName: 'GPT-5.4',
    maxContextTokens: 128000,
    usableInputBudget: 104000,
    compressionTriggerRatio: 0.8,
    totalEstimatedInputTokens: 70000,
    totalWindowUsageRatio: 0.546875,
    usableInputUsageRatio: 0.6731,
    didCompactHistory: true,
    snapshotCoveredUntilTurnId: 42,
    recentCompletedTurnCount: 3,
    segments: const [
      ContextWindowSegment(
        type: ContextWindowSegmentType.systemPrompt,
        label: 'system prompt',
        estimatedTokens: 8000,
        shareOfTotalWindow: 0.0625,
        shareOfUsableInput: 0.076,
        isPlannerVisible: true,
      ),
      ContextWindowSegment(
        type: ContextWindowSegmentType.currentTurnTranscript,
        label: 'current turn transcript',
        estimatedTokens: 18000,
        shareOfTotalWindow: 0.14,
        shareOfUsableInput: 0.17,
        isPlannerVisible: true,
      ),
      ContextWindowSegment(
        type: ContextWindowSegmentType.reservedOutput,
        label: 'reserved output',
        estimatedTokens: 12000,
        shareOfTotalWindow: 0.09,
        shareOfUsableInput: 0.11,
        isPlannerVisible: false,
      ),
    ],
  );
}
