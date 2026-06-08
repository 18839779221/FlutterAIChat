import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/debug/streaming_trace_snapshot.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/providers/chat_ui_providers.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/streaming_trace_providers.dart';
import 'package:ai_chat/services/chat_timeline_projection_service.dart';
import 'package:ai_chat/services/debug/streaming_trace_recorder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TurnProjectionDispatcher', () {
    test(
        'preserves preview state through finalAnswer so per-entity dedup handles takeover',
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

      // Truth callback runs while the preview message is still present;
      // projection-layer dedup is the new takeover mechanism.
      expect(
        callOrder,
        ['truth:1'],
      );
      expect(
        container.read(runtimeStreamingPreviewStateProvider).messages,
        hasLength(1),
      );
    });

    test('keeps late preview events until projection-level logicalId takeover', () async {
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

      // Dispatcher no longer drops late preview deltas. Cleanup happens only
      // through projection-level logicalId takeover or end-of-turn disposal.
      final state = container.read(runtimeStreamingPreviewStateProvider);
      expect(state.messages, hasLength(1));
      expect(state.messages.single.blocks.single.text, 'late');
    });

    test('keeps previous preview message when same turn starts a new provider message', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final dispatcher = container.read(turnProjectionDispatcherProvider);
      const metadata = {
        'streamTurnId': 'turn-1',
        'streamTraceId': 'trace-1',
      };

      await dispatcher.dispatchPreviewEvent(
        const StreamingMessageStartEvent(
          messageId: 'm1',
          runtimeMetadata: metadata,
        ),
      );
      await dispatcher.dispatchPreviewEvent(
        const StreamingContentBlockStartEvent(
          messageId: 'm1',
          contentBlockId: 'm1:thinking',
          blockType: StreamingContentBlockType.thinking,
          runtimeMetadata: metadata,
        ),
      );
      await dispatcher.dispatchPreviewEvent(
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:thinking',
          deltaType: StreamingContentDeltaType.thinking,
          value: 'old reasoning',
          runtimeMetadata: metadata,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 140));
      expect(
        container.read(runtimeStreamingPreviewStateProvider).messages,
        hasLength(1),
      );

      await dispatcher.dispatchPreviewEvent(
        const StreamingMessageStartEvent(
          messageId: 'm2',
          runtimeMetadata: metadata,
        ),
      );
      await dispatcher.dispatchPreviewEvent(
        const StreamingContentBlockStartEvent(
          messageId: 'm2',
          contentBlockId: 'm2:text',
          blockType: StreamingContentBlockType.text,
          runtimeMetadata: metadata,
        ),
      );
      await dispatcher.dispatchPreviewEvent(
        const StreamingContentBlockDeltaEvent(
          messageId: 'm2',
          contentBlockId: 'm2:text',
          deltaType: StreamingContentDeltaType.text,
          value: 'new text',
          runtimeMetadata: metadata,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 140));

      final state = container.read(runtimeStreamingPreviewStateProvider);
      expect(state.messages, hasLength(2));
      expect(
        state.messages.map((message) => message.messageId).toList(),
        ['m1', 'm2'],
      );
      expect(state.messages.first.blocks.single.text, 'old reasoning');
      expect(state.messages.last.blocks.single.text, 'new text');
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
      // Seed a user message so the preview projection resolves to the same
      // `<groupId>_<userMessageId>` turn id the persisted final answer ends
      // up with; otherwise the dedup keys disagree and both blocks survive.
      container.read(messagesProvider.notifier).addMessage(
            ChatMessage(
              id: 10,
              text: 'hi',
              role: MessageRole.user,
            ),
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
          payloadJson: const {
            'logicalId': 'final:1_10',
          },
        ),
        (_) async {
          container.read(messagesProvider.notifier).addMessage(
                ChatMessage(
                  id: 11,
                  text: 'hello',
                  role: MessageRole.assistant,
                  status: MessageStatus.completed,
                  payloadJson: const {
                    'isFinalAnswer': true,
                    'logicalId': 'final:1_10',
                  },
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
      expect(finalBlocks.single.logicalId, 'final:1_10');
      // Preview state itself is kept; the dedup happens at projection time.
      expect(
        container.read(runtimeStreamingPreviewStateProvider).messages,
        hasLength(1),
      );
    });

    test('records current-turn trace across tool phase and final takeover',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final dispatcher = container.read(turnProjectionDispatcherProvider);
      final traceId = streamingTraceIdForTurn(42);
      final startedAt = DateTime(2026, 5, 31, 13, 0, 0);

      container.read(streamingTraceRecorderProvider.notifier).recordStage(
            traceId: traceId,
            turnId: '42',
            stage: StreamingTraceStage.turnStarted,
            timestamp: startedAt,
            details: const {'userMessagePreview': '查一下今天的更新'},
          );

      await dispatcher.dispatchTruthEvent(
        ChatEvent(
          turnId: 42,
          groupId: 1,
          sequence: 1,
          eventType: ChatEventType.assistantToolCall,
          role: MessageRole.assistant,
          payloadJson: const {'toolName': 'web_search'},
          createdAt: startedAt.add(const Duration(milliseconds: 900)),
        ),
        (_) async {},
      );

      await dispatcher.dispatchTruthEvent(
        ChatEvent(
          turnId: 42,
          groupId: 1,
          sequence: 2,
          eventType: ChatEventType.toolResult,
          role: MessageRole.system,
          payloadJson: const {'toolName': 'web_search'},
          createdAt: startedAt.add(const Duration(milliseconds: 2400)),
        ),
        (_) async {},
      );

      await dispatcher.dispatchTruthEvent(
        ChatEvent(
          turnId: 42,
          groupId: 1,
          sequence: 3,
          eventType: ChatEventType.finalAnswer,
          role: MessageRole.assistant,
          content: '今天的主要变化是模型等待时间更长。',
          createdAt: startedAt.add(const Duration(milliseconds: 4200)),
        ),
        (_) async {},
      );

      final snapshot = container.read(streamingTraceSnapshotProvider);

      expect(snapshot, isNotNull);
      expect(snapshot!.traceId, traceId);
      expect(snapshot.turnId, '42');
      expect(snapshot.status, StreamingTraceLifecycleStatus.completed);
      expect(snapshot.takeoverAt, isNotNull);
      expect(
        snapshot.entries.map((entry) => entry.stage).toList(),
        [
          StreamingTraceStage.turnStarted,
          StreamingTraceStage.toolCallStarted,
          StreamingTraceStage.toolCallCompleted,
          StreamingTraceStage.finalTakeover,
        ],
      );
      expect(
        snapshot.entries[1].details['toolName'],
        'web_search',
      );
      expect(
        snapshot.entries.last.details['previewText'],
        '今天的主要变化是模型等待时间更长。',
      );
    });
  });
}
