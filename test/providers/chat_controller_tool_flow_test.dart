import 'dart:async';
import 'dart:convert';

import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/tool_call_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatController.sendMessage tool flow', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test('工具命中时会新增 toolResult 消息再生成最终回答', () async {
      final databaseHelper = DatabaseHelper();
      final chatService = _FakeChatService(
        toolPreparationResult: ToolPreparationResult(
          toolResult: const ToolResult(
            toolName: 'search_chat_history',
            status: ToolExecutionStatus.success,
            displayText: '已执行：搜索历史记录',
            payload: {
              'query': '数据库',
              'matchCount': 1,
              'matches': [
                {
                  'id': 1,
                  'text': '数据库版本已经升级到 6',
                  'role': 'assistant',
                },
              ],
            },
          ),
          additionalContextMessages: [
            ChatMessage(
              text: '命中历史消息：数据库版本已经升级到 6',
              role: MessageRole.system,
              status: MessageStatus.completed,
            ),
          ],
        ),
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: chatService,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      await container.read(chatControllerProvider).sendMessage('我刚才提过数据库版本吗？');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final messages = container.read(messagesProvider);
      final toolMessage = messages.firstWhere(
        (message) => message.contentType == MessageContentType.toolResult,
      );
      final finalAssistantMessage = messages.firstWhere(
        (message) =>
            message.isAssistant &&
            message.contentType == MessageContentType.plainText &&
            message.status == MessageStatus.completed &&
            message.text == '最终回答',
      );
      final persisted = await databaseHelper.getMessagesByGroup(groupId);

      expect(toolMessage.text, '已执行：搜索历史记录');
      expect(toolMessage.payloadJson?['toolName'], 'search_chat_history');
      expect(toolMessage.payloadJson?['data']?['matchCount'], 1);
      expect(finalAssistantMessage.text, '最终回答');
      expect(chatService.preparedUserMessages, ['我刚才提过数据库版本吗？']);
      expect(
          chatService.streamHistories.single
              .any((message) => message.role == MessageRole.system),
          isTrue);
      expect(
        persisted.where(
            (message) => message.contentType == MessageContentType.toolResult),
        isNotEmpty,
      );

      await databaseHelper.deleteGroup(groupId);
    });

    test('不需要工具时不会新增 toolResult 消息', () async {
      final databaseHelper = DatabaseHelper();
      final chatService = _FakeChatService(
        toolPreparationResult: const ToolPreparationResult.noTool(),
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: chatService,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      await container.read(chatControllerProvider).sendMessage('直接回答这个问题');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final messages = container.read(messagesProvider);

      expect(
        messages.where(
            (message) => message.contentType == MessageContentType.toolResult),
        isEmpty,
      );
      expect(
        messages.any(
          (message) =>
              message.isAssistant &&
              message.status == MessageStatus.completed &&
              message.text == '最终回答',
        ),
        isTrue,
      );

      await databaseHelper.deleteGroup(groupId);
    });

    test('工具失败时仍会记录失败状态消息且最终回答链路不中断', () async {
      final databaseHelper = DatabaseHelper();
      final chatService = _FakeChatService(
        toolPreparationResult: ToolPreparationResult(
          toolResult: const ToolResult(
            toolName: 'search_chat_history',
            status: ToolExecutionStatus.failure,
            displayText: '搜索历史记录失败',
            payload: {
              'reason': 'empty_query',
            },
          ),
          additionalContextMessages: [
            ChatMessage(
              text: '工具执行失败，请谨慎回答。',
              role: MessageRole.system,
              status: MessageStatus.completed,
            ),
          ],
        ),
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: chatService,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      await container.read(chatControllerProvider).sendMessage('帮我查一下');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final messages = container.read(messagesProvider);
      final toolMessage = messages.firstWhere(
        (message) => message.contentType == MessageContentType.toolResult,
      );

      expect(toolMessage.text, '搜索历史记录失败');
      expect(toolMessage.payloadJson?['status'], 'failure');
      expect(
        messages.any(
          (message) =>
              message.isAssistant &&
              message.status == MessageStatus.completed &&
              message.text == '最终回答',
        ),
        isTrue,
      );

      await databaseHelper.deleteGroup(groupId);
    });

    test('需要确认的工具会先插入 actionConfirmation 消息', () async {
      final databaseHelper = DatabaseHelper();
      final chatService = _FakeChatService(
        toolPreparationResult: ToolPreparationResult(
          toolInvocation: const ToolInvocation(
            toolName: 'create_reminder',
            arguments: {'title': '交周报'},
            status: ToolInvocationStatus.awaitingConfirmation,
            summary: '准备执行工具：创建提醒',
            requiresConfirmation: true,
          ),
          toolResult: null,
          additionalContextMessages: const [],
        ),
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: chatService,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      await container.read(chatControllerProvider).sendMessage('提醒我交周报');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final messages = container.read(messagesProvider);
      final confirmationMessage = messages.firstWhere(
        (message) => message.contentType == MessageContentType.actionConfirmation,
      );

      expect(confirmationMessage.text, '准备执行工具：创建提醒');
      expect(
        messages.where(
          (message) => message.contentType == MessageContentType.toolResult,
        ),
        isEmpty,
      );
      expect(chatService.streamHistories, isEmpty);

      await databaseHelper.deleteGroup(groupId);
    });

    test('继续并信任会执行挂起工具并追加 toolResult 消息', () async {
      final databaseHelper = DatabaseHelper();
      final chatService = _FakeChatService(
        toolPreparationResult: ToolPreparationResult(
          toolInvocation: const ToolInvocation(
            toolName: 'create_reminder',
            arguments: {'title': '交周报'},
            status: ToolInvocationStatus.awaitingConfirmation,
            summary: '准备执行工具：创建提醒',
            requiresConfirmation: true,
          ),
          toolResult: null,
          additionalContextMessages: const [],
        ),
        confirmedToolResult: const ToolPreparationResult(
          toolInvocation: const ToolInvocation(
            toolName: 'create_reminder',
            arguments: {'title': '交周报'},
            status: ToolInvocationStatus.running,
            summary: '正在执行工具：创建提醒',
            requiresConfirmation: false,
          ),
          toolResult: const ToolResult(
            toolName: 'create_reminder',
            status: ToolExecutionStatus.success,
            summary: '已创建提醒：交周报',
            data: {'title': '交周报'},
          ),
          additionalContextMessages: const [],
        ),
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: chatService,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      await container.read(chatControllerProvider).sendMessage('提醒我交周报');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final confirmationMessage = container
          .read(messagesProvider)
          .firstWhere(
            (message) =>
                message.contentType == MessageContentType.actionConfirmation,
          );
      await container
          .read(chatControllerProvider)
          .confirmToolInvocation(confirmationMessage, trustTool: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final messages = container.read(messagesProvider);
      expect(
        messages.any(
          (message) =>
              message.contentType == MessageContentType.toolInvocation &&
              message.text == '正在执行工具：创建提醒',
        ),
        isTrue,
      );
      expect(
        messages.any(
          (message) =>
              message.contentType == MessageContentType.toolResult &&
              message.text == '已创建提醒：交周报',
        ),
        isTrue,
      );
      expect(chatService.confirmedTrustFlags, [true]);

      await databaseHelper.deleteGroup(groupId);
    });

    test('发送时会立即进入 preparing 并插入用户消息，不等待工具准备完成', () async {
      final databaseHelper = DatabaseHelper();
      final prepareCompleter = Completer<ToolPreparationResult>();
      final chatService = _FakeChatService(
        toolPreparationResult: const ToolPreparationResult.noTool(),
        prepareCompleter: prepareCompleter,
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: chatService,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      unawaited(
        container.read(chatControllerProvider).sendMessage('立即显示这条消息'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        container.read(sendPhaseProvider),
        ChatSendPhase.preparing,
      );
      expect(
        container.read(messagesProvider).any(
              (message) =>
                  message.isUser && message.text == '立即显示这条消息',
            ),
        isTrue,
      );

      prepareCompleter.complete(const ToolPreparationResult.noTool());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(container.read(sendPhaseProvider), ChatSendPhase.idle);

      await databaseHelper.deleteGroup(groupId);
    });

    test('需要确认的工具会让发送事务停留在 awaitingConfirmation', () async {
      final databaseHelper = DatabaseHelper();
      final chatService = _FakeChatService(
        toolPreparationResult: const ToolPreparationResult(
          toolInvocation: const ToolInvocation(
            toolName: 'create_reminder',
            arguments: {'title': '交周报'},
            status: ToolInvocationStatus.awaitingConfirmation,
            summary: '准备执行工具：创建提醒',
            requiresConfirmation: true,
          ),
          toolResult: null,
          additionalContextMessages: const [],
        ),
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: chatService,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      await container.read(chatControllerProvider).sendMessage('提醒我交周报');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        container.read(sendPhaseProvider),
        ChatSendPhase.awaitingConfirmation,
      );

      await databaseHelper.deleteGroup(groupId);
    });
  });
}

ProviderContainer _createContainer({
  required DatabaseHelper databaseHelper,
  required ChatService chatService,
}) {
  return ProviderContainer(
    overrides: [
      databaseProvider.overrideWith((ref) => databaseHelper),
      chatServiceProvider.overrideWith((ref) => chatService),
      scrollControllerProvider.overrideWith((ref) => ScrollController()),
      textControllerProvider.overrideWith((ref) => TextEditingController()),
      focusNodeProvider.overrideWith((ref) => FocusNode()),
    ],
  );
}

class _FakeChatService extends ChatService {
  final ToolPreparationResult toolPreparationResult;
  final ToolPreparationResult? confirmedToolResult;
  final Completer<ToolPreparationResult>? prepareCompleter;
  final List<String> preparedUserMessages = [];
  final List<List<ChatMessage>> streamHistories = [];
  final List<bool> confirmedTrustFlags = [];

  _FakeChatService({
    required this.toolPreparationResult,
    this.confirmedToolResult,
    this.prepareCompleter,
  })
      : super(llm: _NoopBaseLLM());

  @override
  Future<ToolPreparationResult> prepareToolAssistance({
    required int groupId,
    required String userMessage,
    required List<ChatMessage> history,
  }) async {
    preparedUserMessages.add(userMessage);
    final pendingPrepare = prepareCompleter;
    if (pendingPrepare != null) {
      return pendingPrepare.future;
    }
    return toolPreparationResult;
  }

  @override
  Stream<String> sendMessageStream(
    String message,
    List<ChatMessage> history,
    ChatConfig config,
  ) async* {
    streamHistories.add(history);
    yield jsonEncode({'type': 'content', 'content': '最终回答'});
  }

  @override
  Future<ToolPreparationResult> executeToolInvocation({
    required int groupId,
    required ToolInvocation invocation,
    bool trustTool = false,
  }) async {
    confirmedTrustFlags.add(trustTool);
    return confirmedToolResult ?? const ToolPreparationResult.noTool();
  }
}

class _NoopBaseLLM implements BaseLLM {
  @override
  Map<String, dynamic> get config => const {};

  @override
  Stream<String> chatStream(List<ChatMessage> messages, ChatConfig config) =>
      const Stream.empty();

  @override
  Future<String> decideToolCall({
    required String userMessage,
    required List<ChatMessage> history,
    required List<ToolDefinition> tools,
  }) {
    throw UnimplementedError();
  }

  @override
  String getModelName(ChatConfig config) => 'noop';

  @override
  Future<String> structureSummaryCard(String sourceText) {
    throw UnimplementedError();
  }

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async => '';

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;
}
