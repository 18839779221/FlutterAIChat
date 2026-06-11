import 'package:ai_chat/models/session/context_usage_category.dart';
import 'package:ai_chat/models/session/context_usage_top_item.dart';
import 'package:ai_chat/models/session/context_window_segment.dart';
import 'package:ai_chat/models/session/context_window_snapshot.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/widgets/context_window/context_window_bottom_sheet.dart';
import 'package:ai_chat/widgets/context_window/context_window_usage_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'bottom sheet shows usage grid categories top items and collapsed technical details',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            AppThemeSpec.light(),
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

    expect(find.byKey(const ValueKey('context-usage-grid')), findsOneWidget);
    expect(find.text('GPT-5.4'), findsOneWidget);
    expect(find.text('压缩预留区 19.5%'), findsOneWidget);
    final sheetScrollable = find.descendant(
      of: find.byKey(const ValueKey('context-window-bottom-sheet')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Top 5'),
      180,
      scrollable: sheetScrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Top 5'), findsOneWidget);
    expect(find.text('最近对话'), findsWidgets);
    expect(find.text('工具 / 网页 / 文件结果'), findsWidgets);
    expect(find.text('fetch_webpage · openai.com/pricing'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('技术细节'),
      180,
      scrollable: sheetScrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('技术细节'), findsOneWidget);
  });

  testWidgets('tapping usage indicator opens context window bottom sheet',
      (tester) async {
    final snapshot = _snapshot();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            AppThemeSpec.light(),
            AppSpacing.base(),
            AppRadius.base(),
          ],
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => ContextWindowUsageIndicator(
              snapshot: snapshot,
              onTap: () {
                showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => ContextWindowBottomSheet(snapshot: snapshot),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('context-window-usage-indicator')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('context-window-bottom-sheet')),
      findsOneWidget,
    );
  });

  testWidgets(
      'sheet stays partial-height when opened as scroll-controlled modal',
      (tester) async {
    final snapshot = _snapshot();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            AppThemeSpec.light(),
            AppSpacing.base(),
            AppRadius.base(),
          ],
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => ContextWindowBottomSheet(snapshot: snapshot),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final rect = tester.getRect(
      find.byKey(const ValueKey('context-window-bottom-sheet')),
    );
    expect(rect.top, greaterThan(40));
  });
}

ContextWindowSnapshot _snapshot() {
  return const ContextWindowSnapshot(
    modelName: 'GPT-5.4',
    maxContextTokens: 128000,
    effectiveInputBudget: 104000,
    autoCompactTriggerTokens: 91000,
    totalEstimatedInputTokens: 70000,
    plannerInputUsageRatio: 70000 / 91000,
    totalWindowUsageRatio: 0.546875,
    effectiveInputUsageRatio: 0.6731,
    didCompactHistory: true,
    snapshotCoveredUntilTurnId: 42,
    recentCompletedTurnCount: 3,
    plannerReserveTokens: 12000,
    segments: [
      ContextWindowSegment(
        type: ContextWindowSegmentType.systemPrompt,
        label: 'system prompt',
        estimatedTokens: 8000,
        shareOfTotalWindow: 0.0625,
        shareOfEffectiveInput: 0.076,
        isPlannerVisible: true,
      ),
      ContextWindowSegment(
        type: ContextWindowSegmentType.currentTurnTranscript,
        label: 'current turn transcript',
        estimatedTokens: 18000,
        shareOfTotalWindow: 0.14,
        shareOfEffectiveInput: 0.17,
        isPlannerVisible: true,
      ),
      ContextWindowSegment(
        type: ContextWindowSegmentType.reservedOutput,
        label: 'reserved output',
        estimatedTokens: 12000,
        shareOfTotalWindow: 0.09,
        shareOfEffectiveInput: 0.11,
        isPlannerVisible: false,
      ),
    ],
    categories: [
      ContextUsageCategory(
        type: ContextUsageCategoryType.recentConversation,
        label: '最近对话',
        estimatedTokens: 22000,
        shareOfTotalWindow: 0.1719,
      ),
      ContextUsageCategory(
        type: ContextUsageCategoryType.toolResults,
        label: '工具 / 网页 / 文件结果',
        estimatedTokens: 18000,
        shareOfTotalWindow: 0.1406,
      ),
      ContextUsageCategory(
        type: ContextUsageCategoryType.historySummary,
        label: '历史摘要',
        estimatedTokens: 14000,
        shareOfTotalWindow: 0.1094,
      ),
      ContextUsageCategory(
        type: ContextUsageCategoryType.systemSettings,
        label: '系统设定',
        estimatedTokens: 12000,
        shareOfTotalWindow: 0.0938,
      ),
    ],
    topItems: [
      ContextUsageTopItem(
        toolName: 'fetch_webpage',
        objectLabel: 'openai.com/pricing',
        estimatedTokens: 12000,
        shareOfTotalWindow: 0.0938,
      ),
      ContextUsageTopItem(
        toolName: 'Read',
        objectLabel: '/workspaces/demo/README.md',
        estimatedTokens: 6000,
        shareOfTotalWindow: 0.0469,
      ),
    ],
  );
}
