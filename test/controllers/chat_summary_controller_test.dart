import 'package:ai_chat/controllers/chat_summary_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DefaultChatSummaryController.isDefaultTitle', () {
    test('matches auto-generated defaults: 新对话 <digits>', () {
      expect(DefaultChatSummaryController.isDefaultTitle('新对话 1'), isTrue);
      expect(DefaultChatSummaryController.isDefaultTitle('新对话 42'), isTrue);
      expect(DefaultChatSummaryController.isDefaultTitle('新对话 9999'), isTrue);
    });

    test('matches legacy defaults: AI Chat / 默认对话', () {
      expect(DefaultChatSummaryController.isDefaultTitle('AI Chat'), isTrue);
      expect(DefaultChatSummaryController.isDefaultTitle('默认对话'), isTrue);
    });

    test('rejects user-customized titles starting with 新对话', () {
      expect(DefaultChatSummaryController.isDefaultTitle('新对话的想法'), isFalse);
      expect(DefaultChatSummaryController.isDefaultTitle('新对话'), isFalse);
      expect(DefaultChatSummaryController.isDefaultTitle('新对话abc'), isFalse);
      expect(DefaultChatSummaryController.isDefaultTitle('新对话1'), isFalse);
      expect(DefaultChatSummaryController.isDefaultTitle('新对话 1 备注'), isFalse);
    });

    test('rejects unrelated titles', () {
      expect(DefaultChatSummaryController.isDefaultTitle(''), isFalse);
      expect(DefaultChatSummaryController.isDefaultTitle('今天的工作'), isFalse);
      expect(DefaultChatSummaryController.isDefaultTitle('ai chat'), isFalse);
      expect(DefaultChatSummaryController.isDefaultTitle('默认对话 1'), isFalse);
    });
  });
}
