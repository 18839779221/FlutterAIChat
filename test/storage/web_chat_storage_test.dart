import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/storage/web_chat_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('web storage uses latest-first pagination windows', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final storage = WebChatStorage(preferences);
    final groupId = await storage.insertGroup(
      ChatGroup(
        title: 'group',
        lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions,
      ),
    );

    for (var index = 0; index < 45; index += 1) {
      await storage.insertMessage(
        ChatMessage(
          text: 'Message $index',
          role: index.isEven ? MessageRole.user : MessageRole.assistant,
          timestamp: DateTime(2026, 1, 1, 10, index),
        ),
        groupId,
      );
    }

    final initialMessages = await storage.getMessagesByGroup(groupId);
    final olderMessages = await storage.getMessagesByGroupWithPagination(
      groupId: groupId,
      limit: 20,
      offset: initialMessages.length,
    );

    expect(initialMessages.map((message) => message.text).toList(), [
      for (var index = 25; index < 45; index += 1) 'Message $index',
    ]);
    expect(olderMessages.map((message) => message.text).toList(), [
      for (var index = 5; index < 25; index += 1) 'Message $index',
    ]);
  });
}
