import 'package:ai_chat/controllers/agent_event_processor.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final refProvider = Provider<Ref>((ref) => ref);

  test('context compacted event is persisted as a boundary message', () async {
    final storage = _RecordingChatStorage();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    final processor = AgentEventProcessor(
      ref: container.read(refProvider),
      groupId: 7,
      traceTurnId: 'trace-1',
    );

    await processor.handle(
      ChatEvent(
        turnId: 11,
        groupId: 7,
        sequence: 1,
        eventType: ChatEventType.contextCompacted,
        role: MessageRole.system,
        content: '已压缩历史上下文',
        payloadJson: const {
          'coveredUntilTurnId': 3,
          'trigger': 'manual',
        },
      ),
    );

    expect(storage.insertedMessages, hasLength(1));
    expect(storage.insertedMessages.single.text, '已压缩历史上下文');
    expect(
      storage.insertedMessages.single.contentType,
      MessageContentType.contextBoundary,
    );
    expect(container.read(messagesProvider), hasLength(1));
  });
}

class _RecordingChatStorage implements ChatStorage {
  final List<ChatMessage> insertedMessages = <ChatMessage>[];

  @override
  Future<int> insertMessage(ChatMessage message, int groupId) async {
    insertedMessages.add(message);
    return insertedMessages.length;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
