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

  test(
      'tool-use reasoning deltas with the same logical thread stay in one truth message across non-reasoning events',
      () async {
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
        eventType: ChatEventType.assistantReasoningDelta,
        role: MessageRole.assistant,
        content: '先规划 HTML 架构展示。',
        payloadJson: const {
          'scope': 'tool_use',
          'logicalId': 'toolReasoning:resp_tool_1',
          'responseId': 'resp_tool_1',
        },
      ),
    );
    await processor.handle(
      ChatEvent(
        turnId: 11,
        groupId: 7,
        sequence: 2,
        eventType: ChatEventType.toolExecutionStarted,
        role: MessageRole.assistant,
        content: '正在执行工具',
        payloadJson: const {
          'toolName': 'create_artifact',
          'providerCallId': 'call_1',
        },
      ),
    );
    await processor.handle(
      ChatEvent(
        turnId: 11,
        groupId: 7,
        sequence: 3,
        eventType: ChatEventType.assistantReasoningDelta,
        role: MessageRole.assistant,
        content: '补充 SVG 布局细节。',
        payloadJson: const {
          'scope': 'tool_use',
          'logicalId': 'toolReasoning:resp_tool_1',
          'responseId': 'resp_tool_1',
        },
      ),
    );

    final toolReasoningMessages = container
        .read(messagesProvider)
        .where((message) => message.payloadJson?['reasoningScope'] == 'tool_use')
        .toList(growable: false);

    expect(toolReasoningMessages, hasLength(1));
    expect(
      toolReasoningMessages.single.reasoningContent,
      '先规划 HTML 架构展示。补充 SVG 布局细节。',
    );
    expect(storage.insertedMessages.where((m) => m.payloadJson?['reasoningScope'] == 'tool_use'), hasLength(1));
    expect(storage.updatedReasoningCalls, hasLength(1));
    expect(storage.updatedReasoningCalls.single.reasoningContent,
        '先规划 HTML 架构展示。补充 SVG 布局细节。');
  });
}

class _RecordingChatStorage implements ChatStorage {
  final List<ChatMessage> insertedMessages = <ChatMessage>[];
  final List<_UpdateReasoningCall> updatedReasoningCalls = <_UpdateReasoningCall>[];

  @override
  Future<int> insertMessage(ChatMessage message, int groupId) async {
    insertedMessages.add(message);
    return insertedMessages.length;
  }

  @override
  Future<void> updateMessageReasoning(int messageId, String? reasoningContent) async {
    updatedReasoningCalls.add(
      _UpdateReasoningCall(
        messageId: messageId,
        reasoningContent: reasoningContent,
      ),
    );
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UpdateReasoningCall {
  const _UpdateReasoningCall({
    required this.messageId,
    required this.reasoningContent,
  });

  final int messageId;
  final String? reasoningContent;
}
