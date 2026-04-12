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
  });
}
