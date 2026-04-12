import 'dart:async';

import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/trace/chat_trace_event.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/services/agent_planner_service.dart';
import 'package:ai_chat/services/agent_turn_orchestrator.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:ai_chat/services/stop_verifier_service.dart';
import 'package:ai_chat/services/tool_call_service.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:ai_chat/services/transcript_builder_service.dart';
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
      final databaseHelper = _createTestDatabaseHelper();
      final orchestrator = _FakeAgentTurnOrchestrator(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '我刚才提过数据库版本吗？',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.assistantToolCall,
            role: MessageRole.assistant,
            content: '准备执行工具：search_chat_history',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.toolExecutionStarted,
            role: MessageRole.system,
            content: '正在执行工具：search_chat_history',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 4,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '已执行：搜索历史记录',
            payloadJson: {
              'toolName': 'search_chat_history',
              'status': 'success',
              'summary': '已执行：搜索历史记录',
              'data': {
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
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 5,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '最终回答',
          ),
        ],
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        orchestrator: orchestrator,
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
      expect(
        persisted.where(
            (message) => message.contentType == MessageContentType.toolResult),
        isNotEmpty,
      );

      await databaseHelper.deleteGroup(groupId);
    });

    test('agent loop 可在最终回答前连续消费多次工具事件', () async {
      final databaseHelper = DatabaseHelper(databaseName: 'chat_controller_agent_loop_test.db');
      final orchestrator = _FakeAgentTurnOrchestrator(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '先搜数据库版本，再查最新 schema',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.assistantToolCall,
            role: MessageRole.assistant,
            content: '准备执行工具：search_chat_history',
            payloadJson: const {
              'toolName': 'search_chat_history',
              'arguments': {'query': '数据库版本'},
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '历史里提到数据库版本已经升级到 7',
            payloadJson: const {
              'toolName': 'search_chat_history',
              'status': 'success',
              'summary': '历史里提到数据库版本已经升级到 7',
              'data': {'version': 7},
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 4,
            eventType: ChatEventType.assistantToolCall,
            role: MessageRole.assistant,
            content: '准备执行工具：fetch_webpage',
            payloadJson: const {
              'toolName': 'fetch_webpage',
              'arguments': {'url': 'https://example.com/schema'},
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 5,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '官网 schema 文档显示当前表结构已切到 turn/event 模式',
            payloadJson: const {
              'toolName': 'fetch_webpage',
              'status': 'success',
              'summary': '官网 schema 文档显示当前表结构已切到 turn/event 模式',
              'data': {'source': 'https://example.com/schema'},
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 6,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '我先查了历史，再查了 schema 文档，现在可以确认已经是 turn/event 结构。',
          ),
        ],
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        orchestrator: orchestrator,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state = ChatGroup(
        id: groupId,
        title: 'group',
      );

      await container.read(chatControllerProvider).sendMessage('先搜数据库版本，再查最新 schema');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final messages = container.read(messagesProvider);
      final toolResults = messages
          .where((message) => message.contentType == MessageContentType.toolResult)
          .toList();

      expect(toolResults, hasLength(2));
      expect(toolResults.first.text, '历史里提到数据库版本已经升级到 7');
      expect(toolResults.last.text, '官网 schema 文档显示当前表结构已切到 turn/event 模式');
      expect(
        messages.any(
          (message) =>
              message.isAssistant &&
              message.status == MessageStatus.completed &&
              message.text == '我先查了历史，再查了 schema 文档，现在可以确认已经是 turn/event 结构。',
        ),
        isTrue,
      );
      expect(orchestrator.recordedTurns.single.userInput, '先搜数据库版本，再查最新 schema');
    });

    test('不需要工具时不会新增 toolResult 消息', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final orchestrator = _FakeAgentTurnOrchestrator(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '直接回答这个问题',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '最终回答',
          ),
        ],
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        orchestrator: orchestrator,
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
      final databaseHelper = _createTestDatabaseHelper();
      final orchestrator = _FakeAgentTurnOrchestrator(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '帮我查一下',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.toolError,
            role: MessageRole.system,
            content: '搜索历史记录失败',
            status: 'empty_query',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '最终回答',
          ),
        ],
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        orchestrator: orchestrator,
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
      final databaseHelper = _createTestDatabaseHelper();
      final orchestrator = _FakeAgentTurnOrchestrator(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '提醒我交周报',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.assistantToolConfirmation,
            role: MessageRole.assistant,
            content: '准备执行工具：创建提醒',
            payloadJson: {
              'toolName': 'create_reminder',
              'arguments': {'title': '交周报'},
            },
          ),
        ],
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        orchestrator: orchestrator,
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
        confirmationMessage.payloadJson?['traceTurnId'],
        isA<String>().having((value) => value, 'non-empty', isNotEmpty),
      );
      expect(
        messages.where(
          (message) => message.contentType == MessageContentType.toolResult,
        ),
        isEmpty,
      );

      await databaseHelper.deleteGroup(groupId);
    });

    test('继续并信任会通过 orchestrator resume 执行挂起工具', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final traceLogs = <Map<String, dynamic>>[];
      final traceRecorder = ChatTraceRecorder(
        logger: (entry) => traceLogs.add(entry),
      );
      final orchestrator = _FakeAgentTurnOrchestrator(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.assistantToolConfirmation,
            role: MessageRole.assistant,
            content: '准备执行工具：创建提醒',
            payloadJson: const {
              'toolName': 'create_reminder',
              'arguments': {'title': '交周报'},
            },
          ),
        ],
        resumedEvents: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.toolExecutionStarted,
            role: MessageRole.system,
            content: '正在执行工具：创建提醒',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '已创建提醒：交周报',
            payloadJson: const {
              'toolName': 'create_reminder',
              'status': 'success',
              'summary': '已创建提醒：交周报',
              'data': {'title': '交周报'},
            },
          ),
        ],
      );
      final chatService = _FakeChatService(
        confirmedToolResult: const ToolPreparationResult(
          toolInvocation: ToolInvocation(
            toolName: 'create_reminder',
            arguments: {'title': '交周报'},
            status: ToolInvocationStatus.running,
            summary: '正在执行工具：创建提醒',
            requiresConfirmation: false,
          ),
          toolResult: ToolResult(
            toolName: 'create_reminder',
            status: ToolExecutionStatus.success,
            summary: '已创建提醒：交周报',
            data: {'title': '交周报'},
          ),
          additionalContextMessages: [],
        ),
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: chatService,
        orchestrator: orchestrator,
        traceRecorder: traceRecorder,
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
      expect(orchestrator.resumedTrustFlags, [true]);
      final initialTurnId = traceLogs
          .firstWhere((entry) => entry['stage'] == ChatTraceStage.sendStart.name)['turnId']
          as String;
      expect(
        traceLogs.any(
          (entry) =>
              entry['turnId'] == initialTurnId &&
              entry['stage'] == ChatTraceStage.toolConfirmationAction.name &&
              entry['status'] == ChatTraceStatus.success.name &&
              entry['summary'] == '用户确认继续执行工具',
        ),
        isTrue,
      );
      expect(chatService.confirmedTurnIds, isEmpty);

      await databaseHelper.deleteGroup(groupId);
    });

    test('agent loop confirmation 会通过 orchestrator 恢复执行并补齐最终回答', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final orchestrator = _FakeAgentTurnOrchestrator(
        databaseHelper: databaseHelper,
        events: [],
        resumedEvents: [
          ChatEvent(
            turnId: 9,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.toolExecutionStarted,
            role: MessageRole.system,
            content: '正在执行工具：创建提醒',
          ),
          ChatEvent(
            turnId: 9,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '已创建提醒：交周报',
            payloadJson: {
              'toolName': 'create_reminder',
              'status': 'success',
              'summary': '已创建提醒：交周报',
              'data': {'title': '交周报'},
            },
          ),
          ChatEvent(
            turnId: 9,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.assistantTextDelta,
            role: MessageRole.assistant,
            content: '提醒',
          ),
          ChatEvent(
            turnId: 9,
            groupId: 1,
            sequence: 4,
            eventType: ChatEventType.assistantTextDelta,
            role: MessageRole.assistant,
            content: '已安排',
          ),
          ChatEvent(
            turnId: 9,
            groupId: 1,
            sequence: 5,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '提醒已安排',
          ),
        ],
      );
      final chatService = _FakeChatService();
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: chatService,
        orchestrator: orchestrator,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');
      final confirmationMessage = ChatMessage(
        text: '准备执行工具：创建提醒',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.actionConfirmation,
        payloadJson: const {
          'toolName': 'create_reminder',
          'arguments': {'title': '交周报'},
          'status': 'awaitingConfirmation',
          'summary': '准备执行工具：创建提醒',
          'requiresConfirmation': true,
          'agentTurnId': 9,
        },
      );
      final confirmationMessageId =
          await databaseHelper.insertMessage(confirmationMessage, groupId);
      confirmationMessage.id = confirmationMessageId;
      container.read(messagesProvider.notifier).setMessages([confirmationMessage]);

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
      expect(
        messages.any(
          (message) =>
              message.isAssistant &&
              message.status == MessageStatus.completed &&
              message.text == '提醒已安排',
        ),
        isTrue,
      );
      expect(orchestrator.resumedTurnIds, [9]);
      expect(chatService.confirmedTurnIds, isEmpty);
    });

    test('agent loop delta 只会追加一次，避免流式文本重复', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final orchestrator = _FakeAgentTurnOrchestrator(
        databaseHelper: databaseHelper,
        events: [],
        resumedEvents: [
          ChatEvent(
            turnId: 11,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.assistantTextDelta,
            role: MessageRole.assistant,
            content: '我先搜索',
          ),
          ChatEvent(
            turnId: 11,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.assistantTextDelta,
            role: MessageRole.assistant,
            content: '，再总结',
          ),
        ],
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        orchestrator: orchestrator,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');
      final confirmationMessage = ChatMessage(
        text: '准备执行工具：联网搜索',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.actionConfirmation,
        payloadJson: const {
          'toolName': 'web_search',
          'arguments': {'query': 'OpenAI latest news'},
          'status': 'awaitingConfirmation',
          'summary': '准备执行工具：联网搜索',
          'requiresConfirmation': true,
          'agentTurnId': 11,
        },
      );
      final confirmationMessageId =
          await databaseHelper.insertMessage(confirmationMessage, groupId);
      confirmationMessage.id = confirmationMessageId;
      container.read(messagesProvider.notifier).setMessages([confirmationMessage]);

      await container
          .read(chatControllerProvider)
          .confirmToolInvocation(confirmationMessage, trustTool: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final assistantMessage = container
          .read(messagesProvider)
          .firstWhere((message) => message.isAssistant && message.id != confirmationMessageId);
      expect(assistantMessage.text, '我先搜索，再总结');
    });

    test('取消工具会记录取消 trace 并复位发送阶段', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final traceLogs = <Map<String, dynamic>>[];
      final traceRecorder = ChatTraceRecorder(
        logger: (entry) => traceLogs.add(entry),
      );
      final orchestrator = _FakeAgentTurnOrchestrator(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.assistantToolConfirmation,
            role: MessageRole.assistant,
            content: '准备执行工具：创建提醒',
            payloadJson: const {
              'toolName': 'create_reminder',
              'arguments': {'title': '交周报'},
            },
          ),
        ],
      );
      final chatService = _FakeChatService();
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: chatService,
        orchestrator: orchestrator,
        traceRecorder: traceRecorder,
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
          .cancelToolInvocation(confirmationMessage);

      expect(container.read(sendPhaseProvider), ChatSendPhase.idle);
      final updatedMessage = container
          .read(messagesProvider)
          .firstWhere((message) => message.id == confirmationMessage.id);
      expect(updatedMessage.text, '已取消工具执行');
      expect(updatedMessage.contentType, MessageContentType.plainText);

      final initialTurnId = traceLogs
          .firstWhere((entry) => entry['stage'] == ChatTraceStage.sendStart.name)['turnId']
          as String;
      expect(
        traceLogs.any(
          (entry) =>
              entry['turnId'] == initialTurnId &&
              entry['stage'] == ChatTraceStage.toolConfirmationAction.name &&
              entry['status'] == ChatTraceStatus.success.name &&
              entry['summary'] == '用户取消工具执行',
        ),
        isTrue,
      );

      await databaseHelper.deleteGroup(groupId);
    });

    test('发送时会立即进入 preparing 并插入用户消息，不等待工具准备完成', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final runTurnGate = Completer<void>();
      final orchestrator = _FakeAgentTurnOrchestrator(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '最终回答',
          ),
        ],
        runTurnGate: runTurnGate,
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        orchestrator: orchestrator,
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
      expect(container.read(chatSendStateProvider).phase, ChatSendPhase.preparing);
      expect(container.read(chatSendStateProvider).isGenerating, isFalse);
      expect(
        container.read(messagesProvider).any(
              (message) =>
                  message.isUser && message.text == '立即显示这条消息',
            ),
        isTrue,
      );

      runTurnGate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(container.read(sendPhaseProvider), ChatSendPhase.idle);
      expect(container.read(chatSendStateProvider).phase, ChatSendPhase.idle);
      expect(container.read(chatSendStateProvider).isGenerating, isFalse);

      await databaseHelper.deleteGroup(groupId);
    });

    test('agent loop 失败时会显示可见错误消息并复位发送状态', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final orchestrator = _FakeAgentTurnOrchestrator(
        databaseHelper: databaseHelper,
        events: const [],
        runTurnError: Exception('请先在设置页配置 API Key'),
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        orchestrator: orchestrator,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      await container.read(chatControllerProvider).sendMessage('测试缺配置失败');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(container.read(sendPhaseProvider), ChatSendPhase.idle);
      expect(container.read(chatSendStateProvider).isGenerating, isFalse);

      final failureMessage = container
          .read(messagesProvider)
          .lastWhere((message) => message.role == MessageRole.assistant);
      expect(failureMessage.status, MessageStatus.failed);
      expect(failureMessage.text, '发送失败：请先在设置页配置 API Key');

      await databaseHelper.deleteGroup(groupId);
    });

    test('sendMessage records controller trace boundary events in order', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final traceLogs = <Map<String, dynamic>>[];
      final traceRecorder = ChatTraceRecorder(
        logger: (entry) => traceLogs.add(entry),
      );
      final orchestrator = _FakeAgentTurnOrchestrator(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '最终回答',
          ),
        ],
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        orchestrator: orchestrator,
        traceRecorder: traceRecorder,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      await container.read(chatControllerProvider).sendMessage('测试发送 trace');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final traceTurnIds = traceLogs
          .map((entry) => entry['turnId'])
          .whereType<String>()
          .toSet();
      expect(traceTurnIds, hasLength(1));

      final stages = traceLogs
          .where((entry) => entry['turnId'] == traceTurnIds.single)
          .map((entry) => entry['stage'])
          .toList();

      expect(
        stages,
        containsAllInOrder([
          ChatTraceStage.sendStart.name,
          ChatTraceStage.sendDone.name,
        ]),
      );
      expect(traceLogs.first['status'], ChatTraceStatus.started.name);
      expect(traceLogs.last['status'], ChatTraceStatus.success.name);

      await databaseHelper.deleteGroup(groupId);
    });

    test(
        'chat controller delegates send transaction boundary to a dedicated coordinator',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final coordinator = _FakeChatSendCoordinator();
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        coordinator: coordinator,
      );
      addTearDown(container.dispose);

      await container.read(chatControllerProvider).sendMessage('委托发送测试');

      expect(coordinator.sentMessages, ['委托发送测试']);
    });

    test('chat controller delegates confirm and cancel tool actions to coordinator',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final coordinator = _FakeChatSendCoordinator();
      final sessionCoordinator = _FakeChatSessionCoordinator();
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        coordinator: coordinator,
        sessionCoordinator: sessionCoordinator,
      );
      addTearDown(container.dispose);

      final message = ChatMessage(
        id: 42,
        text: '准备执行工具：创建提醒',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.actionConfirmation,
        payloadJson: const {
          'toolName': 'create_reminder',
          'arguments': {'title': '交周报'},
          'status': 'awaitingConfirmation',
          'summary': '准备执行工具：创建提醒',
          'requiresConfirmation': true,
        },
      );

      await container
          .read(chatControllerProvider)
          .confirmToolInvocation(message, trustTool: true);
      await container.read(chatControllerProvider).cancelToolInvocation(message);

      expect(coordinator.confirmedMessages, [message]);
      expect(coordinator.confirmedTrustFlags, [true]);
      expect(coordinator.cancelledMessages, [message]);
      expect(sessionCoordinator.loadGroupsCalls, 0);
    });

    test('chat controller delegates session lifecycle actions to session coordinator',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final sessionCoordinator = _FakeChatSessionCoordinator();
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        sessionCoordinator: sessionCoordinator,
      );
      addTearDown(container.dispose);

      final group = ChatGroup(id: 7, title: 'group');

      await container.read(chatControllerProvider).loadGroups();
      await container.read(chatControllerProvider).loadCurrentGroup();
      await container.read(chatControllerProvider).createNewGroup();
      await container.read(chatControllerProvider).loadMessages();
      await container.read(chatControllerProvider).loadMoreMessages();
      await container.read(chatControllerProvider).selectGroup(group);

      expect(sessionCoordinator.loadGroupsCalls, 1);
      expect(sessionCoordinator.loadCurrentGroupCalls, 1);
      expect(sessionCoordinator.createNewGroupCalls, 1);
      expect(sessionCoordinator.loadMessagesCalls, 1);
      expect(sessionCoordinator.loadMoreMessagesCalls, 1);
      expect(sessionCoordinator.selectedGroups, [group]);
    });

    test('chat controller delegates deleteGroup to session coordinator',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final sessionCoordinator = _FakeChatSessionCoordinator();
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        sessionCoordinator: sessionCoordinator,
      );
      addTearDown(container.dispose);

      await container.read(chatControllerProvider).deleteGroup(42);

      expect(sessionCoordinator.deletedGroupIds, [42]);
    });

    test('chat controller delegates summary lifecycle to summary controller',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final summaryController = _FakeChatSummaryController();
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        summaryController: summaryController,
      );
      addTearDown(container.dispose);

      final summary =
          await container.read(chatControllerProvider).summarizeAndUpdateTitle();
      container.read(chatControllerProvider).cancelAutoSummaryTimer();

      expect(summary, 'fake-summary');
      expect(summaryController.summarizeCalls, 1);
      expect(summaryController.cancelTimerCalls, 1);
    });

    test('chat controller delegates debug structuring to debug controller',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final debugController = _FakeChatDebugController();
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        debugController: debugController,
      );
      addTearDown(container.dispose);

      final message = ChatMessage(
        text: 'debug me',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
      );

      await container.read(chatControllerProvider).structureMessageForDebug(message);

      expect(debugController.messages, [message]);
    });

    test('chat controller delegates preferences lifecycle to preferences controller',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final preferencesController = _FakeChatPreferencesController();
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        preferencesController: preferencesController,
      );
      addTearDown(container.dispose);

      await container.read(chatControllerProvider).setSystemPrompt('new prompt');
      container.read(chatControllerProvider).setUseReasoning(true);
      container.read(chatControllerProvider).setUseConciseMode(true);

      expect(preferencesController.systemPrompts, ['new prompt']);
      expect(preferencesController.reasoningValues, [true]);
      expect(preferencesController.conciseValues, [true]);
    });

    test('需要确认的工具会让发送事务停留在 awaitingConfirmation', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final orchestrator = _FakeAgentTurnOrchestrator(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.assistantToolConfirmation,
            role: MessageRole.assistant,
            content: '准备执行工具：创建提醒',
            payloadJson: {
              'toolName': 'create_reminder',
              'arguments': {'title': '交周报'},
            },
          ),
        ],
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        orchestrator: orchestrator,
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
      expect(
        container.read(chatSendStateProvider).phase,
        ChatSendPhase.awaitingConfirmation,
      );
      expect(container.read(chatSendStateProvider).isGenerating, isFalse);

      await databaseHelper.deleteGroup(groupId);
    });

  });
}

int _testDatabaseCounter = 0;

DatabaseHelper _createTestDatabaseHelper() {
  _testDatabaseCounter += 1;
  return DatabaseHelper(
    databaseName: 'chat_controller_tool_flow_test_$_testDatabaseCounter.db',
  );
}

ProviderContainer _createContainer({
  required DatabaseHelper databaseHelper,
  required ChatService chatService,
  ChatTraceRecorder? traceRecorder,
  ChatSendCoordinator? coordinator,
  AgentTurnOrchestrator? orchestrator,
  ChatSessionCoordinator? sessionCoordinator,
  ChatSummaryController? summaryController,
  ChatDebugController? debugController,
  ChatPreferencesController? preferencesController,
}) {
  return ProviderContainer(
    overrides: [
      databaseProvider.overrideWith((ref) => databaseHelper),
      chatServiceProvider.overrideWith((ref) => chatService),
      if (coordinator != null)
        chatSendCoordinatorProvider.overrideWith((ref) => coordinator),
      if (orchestrator != null)
        agentTurnOrchestratorProvider.overrideWith((ref) => orchestrator),
      if (sessionCoordinator != null)
        chatSessionCoordinatorProvider.overrideWith((ref) => sessionCoordinator),
      if (summaryController != null)
        chatSummaryControllerProvider.overrideWith((ref) => summaryController),
      if (debugController != null)
        chatDebugControllerProvider.overrideWith((ref) => debugController),
      if (preferencesController != null)
        chatPreferencesControllerProvider
            .overrideWith((ref) => preferencesController),
      if (traceRecorder != null)
        traceRecorderProvider.overrideWith((ref) => traceRecorder),
      scrollControllerProvider.overrideWith((ref) => ScrollController()),
      textControllerProvider.overrideWith((ref) => TextEditingController()),
      focusNodeProvider.overrideWith((ref) => FocusNode()),
    ],
  );
}

class _FakeChatService extends ChatService {
  final ToolPreparationResult? confirmedToolResult;
  final List<bool> confirmedTrustFlags = [];
  final List<String?> confirmedTurnIds = [];

  _FakeChatService({
    this.confirmedToolResult,
  })
      : super(llm: _NoopBaseLLM());

  @override
  Future<ToolPreparationResult> executeToolInvocation({
    required int groupId,
    required ToolInvocation invocation,
    bool trustTool = false,
    String? turnId,
  }) async {
    confirmedTrustFlags.add(trustTool);
    confirmedTurnIds.add(turnId);
    return confirmedToolResult ?? const ToolPreparationResult.noTool();
  }
}

class _FakeAgentTurnOrchestrator extends AgentTurnOrchestrator {
  final List<ChatEvent> events;
  final List<ChatEvent> resumedEvents;
  final List<ChatTurn> recordedTurns = [];
  final List<int> resumedTurnIds = [];
  final List<bool> resumedTrustFlags = [];
  final Completer<void>? runTurnGate;
  final Object? runTurnError;

  _FakeAgentTurnOrchestrator({
    required DatabaseHelper databaseHelper,
    required this.events,
    this.resumedEvents = const [],
    this.runTurnGate,
    this.runTurnError,
  })
      : super(
          plannerService: AgentPlannerService(llm: _NoopBaseLLM()),
          turnRepository: ChatTurnRepository(databaseHelper),
          eventRepository: ChatEventRepository(databaseHelper),
          transcriptBuilderService: TranscriptBuilderService(
            eventRepository: ChatEventRepository(databaseHelper),
          ),
          stopVerifierService: StopVerifierService(),
          chatService: ChatService(llm: _NoopBaseLLM()),
          toolCallService: ToolCallService(
            toolExecutor: ToolExecutor(chatStorage: databaseHelper),
          ),
        );

  @override
  Stream<ChatEvent> runTurn({
    required ChatTurn turn,
    required ChatConfig config,
  }) async* {
    recordedTurns.add(turn);
    final gate = runTurnGate;
    if (gate != null) {
      await gate.future;
    }
    final error = runTurnError;
    if (error != null) {
      throw error;
    }
    for (final event in events) {
      yield ChatEvent(
        turnId: turn.id ?? event.turnId,
        groupId: turn.groupId,
        sequence: event.sequence,
        eventType: event.eventType,
        role: event.role,
        status: event.status,
        content: event.content,
        payloadJson: event.payloadJson,
        createdAt: event.createdAt,
      );
    }
  }

  @override
  Stream<ChatEvent> resumeAfterConfirmation({
    required int turnId,
    required ToolInvocation invocation,
    required ChatConfig config,
    bool trustTool = false,
  }) async* {
    resumedTurnIds.add(turnId);
    resumedTrustFlags.add(trustTool);
    for (final event in resumedEvents) {
      yield ChatEvent(
        turnId: turnId,
        groupId: event.groupId,
        sequence: event.sequence,
        eventType: event.eventType,
        role: event.role,
        status: event.status,
        content: event.content,
        payloadJson: event.payloadJson,
        createdAt: event.createdAt,
      );
    }
  }
}

class _NoopBaseLLM implements BaseLLM {
  @override
  Map<String, dynamic> get config => const {};

  @override
  Stream<String> chatStream(List<ChatMessage> messages, ChatConfig config) =>
      const Stream.empty();

  @override
  Future<String> planNextAction({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async => '{"action":"respond","response":"stub"}';

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

class _FakeChatSendCoordinator implements ChatSendCoordinator {
  final List<String> sentMessages = [];
  final List<ChatMessage> confirmedMessages = [];
  final List<bool> confirmedTrustFlags = [];
  final List<ChatMessage> cancelledMessages = [];

  @override
  Future<void> sendMessage(
    String text, {
    required VoidCallback scheduleAutoSummary,
    required VoidCallback cancelActiveStream,
  }) async {
    sentMessages.add(text);
  }

  @override
  Future<void> confirmToolInvocation(
    ChatMessage message, {
    bool trustTool = false,
  }) async {
    confirmedMessages.add(message);
    confirmedTrustFlags.add(trustTool);
  }

  @override
  Future<void> cancelToolInvocation(ChatMessage message) async {
    cancelledMessages.add(message);
  }
}

class _FakeChatSessionCoordinator implements ChatSessionCoordinator {
  int loadGroupsCalls = 0;
  int loadCurrentGroupCalls = 0;
  int createNewGroupCalls = 0;
  int loadMessagesCalls = 0;
  int loadMoreMessagesCalls = 0;
  final List<ChatGroup> selectedGroups = [];
  final List<int> deletedGroupIds = [];

  @override
  Future<void> createNewGroup() async {
    createNewGroupCalls += 1;
  }

  @override
  Future<void> loadCurrentGroup() async {
    loadCurrentGroupCalls += 1;
  }

  @override
  Future<void> loadGroups() async {
    loadGroupsCalls += 1;
  }

  @override
  Future<void> loadMessages() async {
    loadMessagesCalls += 1;
  }

  @override
  Future<void> loadMoreMessages() async {
    loadMoreMessagesCalls += 1;
  }

  @override
  Future<void> selectGroup(ChatGroup group) async {
    selectedGroups.add(group);
  }

  @override
  Future<void> deleteGroup(int id) async {
    deletedGroupIds.add(id);
  }
}

class _FakeChatSummaryController implements ChatSummaryController {
  int summarizeCalls = 0;
  int cancelTimerCalls = 0;

  @override
  void cancelAutoSummaryTimer() {
    cancelTimerCalls += 1;
  }

  @override
  void scheduleAutoSummary() {}

  @override
  Future<String?> summarizeAndUpdateTitle() async {
    summarizeCalls += 1;
    return 'fake-summary';
  }
}

class _FakeChatDebugController implements ChatDebugController {
  final List<ChatMessage> messages = [];

  @override
  Future<void> structureMessageForDebug(ChatMessage message) async {
    messages.add(message);
  }
}

class _FakeChatPreferencesController implements ChatPreferencesController {
  final List<String?> systemPrompts = [];
  final List<bool> reasoningValues = [];
  final List<bool> conciseValues = [];

  @override
  Future<void> setSystemPrompt(String? prompt) async {
    systemPrompts.add(prompt);
  }

  @override
  void setUseConciseMode(bool value) {
    conciseValues.add(value);
  }

  @override
  void setUseReasoning(bool value) {
    reasoningValues.add(value);
  }
}
