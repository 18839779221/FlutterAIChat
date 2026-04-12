import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_send/chat_send_drafts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildChatSendTransactionDraft', () {
    test('仅保留完整的普通 user-assistant 历史对', () {
      final draft = buildChatSendTransactionDraft(
        text: '新的问题',
        currentMessages: [
          ChatMessage(
            text: '用户 1',
            role: MessageRole.user,
            status: MessageStatus.completed,
          ),
          ChatMessage(
            text: '助手 1',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
          ),
          ChatMessage(
            text: '用户 2',
            role: MessageRole.user,
            status: MessageStatus.completed,
          ),
          ChatMessage(
            text: '助手生成中',
            role: MessageRole.assistant,
            status: MessageStatus.generating,
          ),
        ],
      );

      expect(draft.userMessage.text, '新的问题');
      expect(draft.assistantPlaceholder.status, MessageStatus.generating);
      expect(draft.historyMessages.map((message) => message.text).toList(),
          ['用户 1', '助手 1']);
    });
  });
}
