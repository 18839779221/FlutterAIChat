import 'package:ai_chat/models/chat_message.dart';
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
  });
}
