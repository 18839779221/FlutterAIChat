import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('messagesProvider', () {
    test('setMessages 会按时间升序整理消息', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final lateMessage = ChatMessage(
        id: 2,
        text: 'later',
        role: MessageRole.user,
        timestamp: DateTime(2026, 4, 12, 12, 0, 1),
      );
      final earlyMessage = ChatMessage(
        id: 1,
        text: 'earlier',
        role: MessageRole.user,
        timestamp: DateTime(2026, 4, 12, 12, 0, 0),
      );

      container.read(messagesProvider.notifier).setMessages([
        lateMessage,
        earlyMessage,
      ]);

      expect(
        container.read(messagesProvider).map((message) => message.id).toList(),
        [1, 2],
      );
    });

    test('setMessages 在同一时间戳下保持用户消息先于助手回复', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final timestamp = DateTime(2026, 4, 13, 1, 40, 0);
      final assistantMessage = ChatMessage(
        id: 2,
        text: 'assistant reply',
        role: MessageRole.assistant,
        timestamp: timestamp,
      );
      final userMessage = ChatMessage(
        id: 1,
        text: 'user prompt',
        role: MessageRole.user,
        timestamp: timestamp,
      );

      container.read(messagesProvider.notifier).setMessages([
        assistantMessage,
        userMessage,
      ]);

      expect(
        container.read(messagesProvider).map((message) => message.id).toList(),
        [1, 2],
      );
    });
  });
}
