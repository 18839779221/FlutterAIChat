import 'package:ai_chat/models/session/context_usage_category.dart';
import 'package:ai_chat/models/session/context_usage_top_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('context usage category exposes label tokens and total share', () {
    const category = ContextUsageCategory(
      type: ContextUsageCategoryType.recentConversation,
      label: '最近对话',
      estimatedTokens: 18000,
      shareOfTotalWindow: 0.14,
    );

    expect(category.label, '最近对话');
    expect(category.estimatedTokens, 18000);
    expect(category.shareOfTotalWindow, 0.14);
  });

  test('context usage top item keeps tool label and total share', () {
    const item = ContextUsageTopItem(
      toolName: 'fetch_webpage',
      objectLabel: 'openai.com/pricing',
      estimatedTokens: 12000,
      shareOfTotalWindow: 0.09,
    );

    expect(item.toolName, 'fetch_webpage');
    expect(item.objectLabel, contains('openai.com'));
    expect(item.displayLabel, 'fetch_webpage · openai.com/pricing');
  });
}
