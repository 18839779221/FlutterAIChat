import 'package:ai_chat/models/session/context_window_segment.dart';
import 'package:ai_chat/models/session/context_window_snapshot.dart';
import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/widgets/context_window/context_window_status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('status bar renders without text copy and responds to taps',
      (tester) async {
    var tapCount = 0;

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
          body: ContextWindowStatusBar(
            snapshot: _snapshot(0.61),
            onTap: () => tapCount += 1,
            compact: true,
          ),
        ),
      ),
    );

    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('上下文'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('context-window-status-bar'))).width,
      lessThan(72),
    );

    await tester.tap(find.byKey(const ValueKey('context-window-status-bar')));
    expect(tapCount, 1);
  });
}

ContextWindowSnapshot _snapshot(double ratio) {
  return ContextWindowSnapshot(
    modelName: 'gpt-5.4',
    maxContextTokens: 128000,
    usableInputBudget: 104000,
    compressionTriggerRatio: 0.8,
    totalEstimatedInputTokens: 78080,
    totalWindowUsageRatio: ratio,
    usableInputUsageRatio: 0.75,
    didCompactHistory: false,
    recentCompletedTurnCount: 2,
    segments: const [
      ContextWindowSegment(
        type: ContextWindowSegmentType.currentTurnTranscript,
        label: 'current turn transcript',
        estimatedTokens: 1200,
        shareOfTotalWindow: 0.01,
        shareOfUsableInput: 0.02,
        isPlannerVisible: true,
      ),
    ],
  );
}
