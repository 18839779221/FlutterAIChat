import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/providers/chat_ui_providers.dart';
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
  });
}
