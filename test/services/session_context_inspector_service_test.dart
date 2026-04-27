import 'package:ai_chat/models/session/context_window_segment.dart';
import 'package:ai_chat/models/session/context_window_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContextWindowSnapshot', () {
    test('exposes total and usable ratios separately', () {
      const snapshot = ContextWindowSnapshot(
        modelName: 'gpt-5',
        maxContextTokens: 128000,
        usableInputBudget: 104000,
        compressionTriggerRatio: 0.8,
        totalEstimatedInputTokens: 64000,
        totalWindowUsageRatio: 0.5,
        usableInputUsageRatio: 64000 / 104000,
        didCompactHistory: false,
        recentCompletedTurnCount: 2,
        segments: [
          ContextWindowSegment(
            type: ContextWindowSegmentType.systemPrompt,
            label: 'system prompt',
            estimatedTokens: 8000,
            shareOfTotalWindow: 8000 / 128000,
            shareOfUsableInput: 8000 / 104000,
            isPlannerVisible: true,
          ),
        ],
      );

      expect(snapshot.totalWindowUsageRatio, 0.5);
      expect(snapshot.usableInputUsageRatio, greaterThan(0.6));
      expect(snapshot.segments.single.isPlannerVisible, isTrue);
      expect(
        snapshot.segments.single.type,
        ContextWindowSegmentType.systemPrompt,
      );
    });
  });
}
