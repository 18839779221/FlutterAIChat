import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/session/session_runtime_config.dart';
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
      ChatGroup(title: 'group'),
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

  test('web storage persists and reloads session runtime config by group',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final storage = WebChatStorage(preferences);
    final groupId = await storage.insertGroup(ChatGroup(title: 'group'));

    final configId = await storage.insertSessionRuntimeConfig(
      SessionRuntimeConfig(
        groupId: groupId,
        providerId: 'openai',
        modelId: 'gpt-5.4',
        providerStyle: ChatTurnProviderStyle.openaiResponses,
        sideProviderId: 'anthropic',
        sideModelId: 'claude-haiku',
        sideProviderStyle: ChatTurnProviderStyle.anthropicMessages,
      ),
    );

    final created = await storage.getSessionRuntimeConfigByGroup(groupId);
    expect(created, isNotNull);
    expect(created!.id, configId);
    expect(created.providerId, 'openai');
    expect(created.sideProviderId, 'anthropic');

    await storage.updateSessionRuntimeConfig(
      created.copyWith(
        providerId: 'anthropic',
        modelId: 'claude-sonnet-4-5',
        providerStyle: ChatTurnProviderStyle.anthropicMessages,
        clearSideProviderId: true,
        clearSideModelId: true,
        clearSideProviderStyle: true,
      ),
    );

    final updated = await storage.getSessionRuntimeConfigByGroup(groupId);
    expect(updated, isNotNull);
    expect(updated!.providerId, 'anthropic');
    expect(updated.modelId, 'claude-sonnet-4-5');
    expect(updated.sideProviderId, isNull);
  });
}
