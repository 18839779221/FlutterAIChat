import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat/active_turn_status_presentation.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/chat_ui_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chat ui providers', () {
    test('默认 UI 状态符合聊天页预期', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(hasMoreMessagesProvider), isTrue);
      expect(container.read(isLoadingMoreProvider), isFalse);
      expect(container.read(isInitializingProvider), isTrue);
    });

    test('controller providers expose Flutter controllers', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(scrollControllerProvider), isA<ScrollController>());
      expect(
        container.read(textControllerProvider),
        isA<TextEditingController>(),
      );
      expect(container.read(focusNodeProvider), isA<FocusNode>());
    });

    test(
        'activePendingToolConfirmationProvider returns latest unresolved confirmation',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(messagesProvider.notifier).setMessages([
        ChatMessage(
          id: 1,
          text: '旧确认',
          role: MessageRole.assistant,
          contentType: MessageContentType.actionConfirmation,
          payloadJson: const ToolInvocation(
            toolName: 'Write',
            arguments: {'file_path': 'a.txt'},
            status: ToolInvocationStatus.awaitingConfirmation,
            summary: '准备写入 a.txt',
            requiresConfirmation: true,
          ).toJson(),
        ),
        ChatMessage(
          id: 2,
          text: '最新确认',
          role: MessageRole.assistant,
          contentType: MessageContentType.actionConfirmation,
          payloadJson: const ToolInvocation(
            toolName: 'Edit',
            arguments: {'file_path': 'b.txt'},
            status: ToolInvocationStatus.awaitingConfirmation,
            summary: '准备编辑 b.txt',
            requiresConfirmation: true,
          ).toJson(),
        ),
      ]);

      final pending = container.read(activePendingToolConfirmationProvider);

      expect(pending, isNotNull);
      expect(pending!.message.id, 2);
      expect(pending.invocation.toolName, 'Edit');
    });

    test('activePendingToolConfirmationProvider ignores resolved messages', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(messagesProvider.notifier).setMessages([
        ChatMessage(
          id: 1,
          text: '已运行',
          role: MessageRole.assistant,
          contentType: MessageContentType.toolInvocation,
          payloadJson: const ToolInvocation(
            toolName: 'Write',
            arguments: {'file_path': 'a.txt'},
            status: ToolInvocationStatus.running,
            summary: '正在写入 a.txt',
            requiresConfirmation: false,
          ).toJson(),
        ),
        ChatMessage(
          id: 2,
          text: '已取消',
          role: MessageRole.assistant,
          contentType: MessageContentType.plainText,
        ),
      ]);

      expect(container.read(activePendingToolConfirmationProvider), isNull);
    });

    test('activeAskUserQuestionMessageProvider reads projection snapshot', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(messagesProvider.notifier).setMessages([
        ChatMessage(
          id: 11,
          text: '旧问题',
          role: MessageRole.assistant,
          contentType: MessageContentType.askUserQuestionPrompt,
          payloadJson: const {
            'type': 'prompt',
            'agentTurnId': 41,
            'status': 'awaitingResponse',
            'questions': [
              {
                'id': 'old_question',
                'header': 'Old',
                'question': '旧问题',
                'options': [
                  {'label': 'A', 'description': 'old'},
                ],
              },
            ],
          },
        ),
        ChatMessage(
          id: 12,
          text: '新问题',
          role: MessageRole.assistant,
          contentType: MessageContentType.askUserQuestionPrompt,
          payloadJson: const {
            'type': 'prompt',
            'agentTurnId': 42,
            'status': 'awaitingResponse',
            'questions': [
              {
                'id': 'new_question',
                'header': 'New',
                'question': '新问题',
                'options': [
                  {'label': 'B', 'description': 'new'},
                ],
              },
            ],
          },
        ),
      ]);

      final active = container.read(activeAskUserQuestionMessageProvider);

      expect(active, isNotNull);
      expect(active!.id, 12);
      expect(
        container
            .read(chatTimelineProjectionProvider)
            .activeAskUserQuestionMessage
            ?.id,
        12,
      );
    });

    test('timeline projection provider reads runtime preview state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(messagesProvider.notifier).setMessages([
        ChatMessage(
          id: 30,
          text: '做个 artifact',
          role: MessageRole.user,
        ),
      ]);

      final notifier =
          container.read(runtimeStreamingPreviewStateProvider.notifier);
      notifier.publish(
        const StreamingMessageStartEvent(messageId: 'preview_1'),
      );
      notifier.publish(
        const StreamingContentBlockStartEvent(
          messageId: 'preview_1',
          contentBlockId: 'preview_1:tool:0',
          blockType: StreamingContentBlockType.toolUse,
          toolUseId: 'call_1',
          toolName: 'create_artifact',
        ),
      );
      notifier.publish(
        const StreamingContentBlockDeltaEvent(
          messageId: 'preview_1',
          contentBlockId: 'preview_1:tool:0',
          deltaType: StreamingContentDeltaType.inputJson,
          value:
              '{"id":"demo","type":"html","title":"Demo","source":"<div>Hello</div>"}',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 140));

      final projection = container.read(chatTimelineProjectionProvider);
      expect(projection.runtimePreviewState.messages, hasLength(1));
      expect(
        projection.assistantBlocks.any(
          (block) => block.payload?['isRuntimePreview'] == true,
        ),
        isTrue,
      );
    });

    test('runtime preview consumes deltas immediately within publish throttle window',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier =
          container.read(runtimeStreamingPreviewStateProvider.notifier);

      notifier.publish(
        const StreamingMessageStartEvent(messageId: 'preview_2'),
      );
      notifier.publish(
        const StreamingContentBlockStartEvent(
          messageId: 'preview_2',
          contentBlockId: 'preview_2:tool:0',
          blockType: StreamingContentBlockType.toolUse,
          toolUseId: 'call_2',
          toolName: 'create_artifact',
        ),
      );
      notifier.publish(
        const StreamingContentBlockDeltaEvent(
          messageId: 'preview_2',
          contentBlockId: 'preview_2:tool:0',
          deltaType: StreamingContentDeltaType.inputJson,
          value: '{"source":"<div>Hello',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));

      notifier.publish(
        const StreamingContentBlockDeltaEvent(
          messageId: 'preview_2',
          contentBlockId: 'preview_2:tool:0',
          deltaType: StreamingContentDeltaType.inputJson,
          value: ' world</div>"}',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(runtimeStreamingPreviewStateProvider);
      expect(state.messages, hasLength(1));
      expect(state.messages.single.blocks, hasLength(1));
      expect(
        state.messages.single.blocks.single.text,
        '{"source":"<div>Hello world</div>"}',
      );
    });

    test('floating visibility stays visible during active-status handoff', () {
      final statusProvider = StateProvider<ActiveTurnStatusPresentation?>(
        (ref) => const ActiveTurnStatusPresentation(
          phase: ActiveTurnStatusPhase.executingTool,
          text: '正在联网搜索',
          turnId: 'turn-b',
          sourceKind: ActiveTurnStatusSourceKind.toolEvent,
          allowFloating: true,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          activeTurnStatusPresentationProvider.overrideWith(
            (ref) => ref.watch(statusProvider),
          ),
          activeTurnStatusFloatingStateProvider.overrideWith(
            (ref) => const ActiveTurnStatusFloatingState(
              turnId: 'turn-a',
              isFloating: true,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(activeTurnStatusFloatingVisibilityProvider), isTrue);
    });

  });
}
