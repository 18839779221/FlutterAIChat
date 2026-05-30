import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/providers/chat_ui_providers.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/services/chat_timeline_projection_service.dart';
import 'package:ai_chat/services/turn_projection_dispatcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TurnProjectionDispatcher', () {
    test('clears preview before appending final answer for the same message',
        () async {
      final callOrder = <String>[];
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final dispatcher = container.read(turnProjectionDispatcherProvider);

      await dispatcher.dispatchPreviewEvent(
        const StreamingMessageStartEvent(messageId: 'm1'),
      );
      await dispatcher.dispatchPreviewEvent(
        const StreamingContentBlockStartEvent(
          messageId: 'm1',
          contentBlockId: 'm1:text',
          blockType: StreamingContentBlockType.text,
        ),
      );
      await dispatcher.dispatchPreviewEvent(
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:text',
          deltaType: StreamingContentDeltaType.text,
          value: 'hello',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 140));

      expect(
        container.read(runtimeStreamingPreviewStateProvider).messages,
        hasLength(1),
      );

      await dispatcher.dispatchTruthEvent(
        ChatEvent(
          turnId: 1,
          groupId: 1,
          sequence: 1,
          eventType: ChatEventType.finalAnswer,
          role: MessageRole.assistant,
          content: 'hello',
          payloadJson: const {'previewMessageId': 'm1'},
        ),
        (event) async {
          callOrder.add(
            'truth:${container.read(runtimeStreamingPreviewStateProvider).messages.length}',
          );
        },
      );

      expect(
        callOrder,
        ['truth:0'],
      );
      expect(container.read(runtimeStreamingPreviewStateProvider).isEmpty, isTrue);
    });

    test('drops late preview events for finalized message', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final dispatcher = container.read(turnProjectionDispatcherProvider);

      await dispatcher.dispatchPreviewEvent(
        const StreamingMessageStartEvent(messageId: 'm1'),
      );
      await dispatcher.dispatchTruthEvent(
        ChatEvent(
          turnId: 1,
          groupId: 1,
          sequence: 1,
          eventType: ChatEventType.finalAnswer,
          role: MessageRole.assistant,
          content: 'done',
          payloadJson: const {'previewMessageId': 'm1'},
        ),
        (_) async {},
      );
      await dispatcher.dispatchPreviewEvent(
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:text',
          deltaType: StreamingContentDeltaType.text,
          value: 'late',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 140));

      expect(container.read(runtimeStreamingPreviewStateProvider).isEmpty, isTrue);
    });

    test(
        'final takeover leaves only persisted final response in timeline projection',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final dispatcher = container.read(turnProjectionDispatcherProvider);

      container.read(currentGroupProvider.notifier).state = ChatGroup(
        id: 1,
        title: 'group',
        lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions,
      );

      await dispatcher.dispatchPreviewEvent(
        const StreamingMessageStartEvent(messageId: 'm1'),
      );
      await dispatcher.dispatchPreviewEvent(
        const StreamingContentBlockStartEvent(
          messageId: 'm1',
          contentBlockId: 'm1:text',
          blockType: StreamingContentBlockType.text,
        ),
      );
      await dispatcher.dispatchPreviewEvent(
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:text',
          deltaType: StreamingContentDeltaType.text,
          value: 'hello',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 140));

      await dispatcher.dispatchTruthEvent(
        ChatEvent(
          turnId: 1,
          groupId: 1,
          sequence: 1,
          eventType: ChatEventType.finalAnswer,
          role: MessageRole.assistant,
          content: 'hello',
          payloadJson: const {'previewMessageId': 'm1'},
        ),
        (_) async {
          container.read(messagesProvider.notifier).addMessage(
                ChatMessage(
                  id: 1,
                  text: 'hello',
                  role: MessageRole.assistant,
                  status: MessageStatus.completed,
                ),
              );
        },
      );

      final projection = ChatTimelineProjectionService().build(
        groupId: 1,
        messages: container.read(messagesProvider),
        runtimePreviewState: container.read(runtimeStreamingPreviewStateProvider),
      );
      final finalBlocks = projection.assistantBlocks
          .where((block) => block.type == AssistantTurnBlockType.finalResponse)
          .toList(growable: false);

      expect(finalBlocks, hasLength(1));
      expect(finalBlocks.single.text, 'hello');
      expect(finalBlocks.single.payload?['isRuntimePreview'], isNot(true));
      expect(container.read(runtimeStreamingPreviewStateProvider).isEmpty, isTrue);
    });
  });
}
