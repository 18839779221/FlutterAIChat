import 'dart:async';

import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/interaction/ask_user_question_request.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/trace/chat_trace_event.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/services/agent_planner_service.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:ai_chat/services/turn_harness.dart';
import 'package:ai_chat/services/turn_verifier.dart';
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
      final orchestrator = _FakeTurnHarness(
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
        harness: orchestrator,
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
      final databaseHelper =
          DatabaseHelper(databaseName: 'chat_controller_agent_loop_test.db');
      final orchestrator = _FakeTurnHarness(
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
        harness: orchestrator,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state = ChatGroup(
        id: groupId,
        title: 'group',
      );

      await container
          .read(chatControllerProvider)
          .sendMessage('先搜数据库版本，再查最新 schema');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final messages = container.read(messagesProvider);
      final toolResults = messages
          .where(
              (message) => message.contentType == MessageContentType.toolResult)
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
      expect(
          orchestrator.recordedTurns.single.userInput, '先搜数据库版本，再查最新 schema');
    });

    test('不需要工具时不会新增 toolResult 消息', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final orchestrator = _FakeTurnHarness(
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
        harness: orchestrator,
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
      final orchestrator = _FakeTurnHarness(
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
            payloadJson: const {
              'toolName': 'search_chat_history',
              'status': 'failure',
              'summary': '搜索历史记录失败',
              'executionPolicy': 'blocked',
              'toolAccess': {
                'toolName': 'search_chat_history',
                'executionDecision': 'blocked',
                'executionPolicy': 'blocked',
                'isVisibleToPlanner': false,
              },
              'errorMessage': 'empty_query',
            },
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
        harness: orchestrator,
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
      expect(toolMessage.payloadJson?['executionPolicy'], 'blocked');
      expect(
        toolMessage.payloadJson?['toolAccess']?['executionPolicy'],
        'blocked',
      );
      expect(toolMessage.payloadJson?['errorMessage'], 'empty_query');
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
      final orchestrator = _FakeTurnHarness(
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
        harness: orchestrator,
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
        (message) =>
            message.contentType == MessageContentType.actionConfirmation,
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

    test('继续并信任会通过 harness resume 执行挂起工具', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final traceLogs = <Map<String, dynamic>>[];
      final traceRecorder = ChatTraceRecorder(
        logger: (entry) => traceLogs.add(entry),
      );
      final orchestrator = _FakeTurnHarness(
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
        ),
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: chatService,
        harness: orchestrator,
        traceRecorder: traceRecorder,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      await container.read(chatControllerProvider).sendMessage('提醒我交周报');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final confirmationMessage = container.read(messagesProvider).firstWhere(
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
      final initialTurnId = traceLogs.firstWhere((entry) =>
          entry['stage'] == ChatTraceStage.sendStart.name)['turnId'] as String;
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

    test('agent loop confirmation 会通过 harness 恢复执行并补齐最终回答', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final orchestrator = _FakeTurnHarness(
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
        harness: orchestrator,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
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
      container
          .read(messagesProvider.notifier)
          .setMessages([confirmationMessage]);

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

    test('agent loop confirmation 遇到 toolError 时会保留失败策略 payload', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final orchestrator = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: [],
        resumedEvents: [
          ChatEvent(
            turnId: 13,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.toolError,
            role: MessageRole.system,
            content: '搜索历史记录失败',
            status: 'empty_query',
            payloadJson: const {
              'toolName': 'search_chat_history',
              'status': 'failure',
              'summary': '搜索历史记录失败',
              'executionPolicy': 'blocked',
              'toolAccess': {
                'toolName': 'search_chat_history',
                'executionDecision': 'blocked',
                'executionPolicy': 'blocked',
                'isVisibleToPlanner': false,
              },
              'errorMessage': 'empty_query',
            },
          ),
          ChatEvent(
            turnId: 13,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '我改用直接回答继续完成本轮。',
          ),
        ],
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        harness: orchestrator,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');
      final confirmationMessage = ChatMessage(
        text: '准备执行工具：搜索历史记录',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.actionConfirmation,
        payloadJson: const {
          'toolName': 'search_chat_history',
          'arguments': {'query': ''},
          'status': 'awaitingConfirmation',
          'summary': '准备执行工具：搜索历史记录',
          'requiresConfirmation': true,
          'agentTurnId': 13,
        },
      );
      final confirmationMessageId =
          await databaseHelper.insertMessage(confirmationMessage, groupId);
      confirmationMessage.id = confirmationMessageId;
      container
          .read(messagesProvider.notifier)
          .setMessages([confirmationMessage]);

      await container
          .read(chatControllerProvider)
          .confirmToolInvocation(confirmationMessage, trustTool: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final messages = container.read(messagesProvider);
      final toolMessage = messages.firstWhere(
        (message) => message.contentType == MessageContentType.toolResult,
      );

      expect(toolMessage.text, '搜索历史记录失败');
      expect(toolMessage.payloadJson?['executionPolicy'], 'blocked');
      expect(
        toolMessage.payloadJson?['toolAccess']?['executionPolicy'],
        'blocked',
      );
      expect(toolMessage.payloadJson?['errorMessage'], 'empty_query');
      expect(
        messages.any(
          (message) =>
              message.isAssistant &&
              message.status == MessageStatus.completed &&
              message.text == '我改用直接回答继续完成本轮。',
        ),
        isTrue,
      );
    });

    test('agent loop confirmation 后若下一步仍需确认，会展示新的确认卡并替换旧卡状态', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final orchestrator = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: [],
        resumedEvents: [
          ChatEvent(
            turnId: 12,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.toolExecutionStarted,
            role: MessageRole.system,
            content: '正在执行工具：写入文件',
            payloadJson: const {
              'toolName': 'Write',
              'arguments': {
                'file_path': 'notes/db-version.md',
                'content': '数据库版本：7',
              },
              'status': 'running',
              'summary': '正在执行工具：写入文件',
              'requiresConfirmation': false,
            },
          ),
          ChatEvent(
            turnId: 12,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '已写入文件：notes/db-version.md',
            payloadJson: const {
              'toolName': 'Write',
              'status': 'success',
              'summary': '已写入文件：notes/db-version.md',
            },
          ),
          ChatEvent(
            turnId: 12,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.assistantToolCall,
            role: MessageRole.assistant,
            content: '准备执行工具：创建提醒',
            payloadJson: const {
              'toolName': 'create_reminder',
              'arguments': {'title': '给测试同学'},
              'status': 'proposed',
              'summary': '准备执行工具：创建提醒',
              'requiresConfirmation': false,
            },
          ),
          ChatEvent(
            turnId: 12,
            groupId: 1,
            sequence: 4,
            eventType: ChatEventType.assistantToolConfirmation,
            role: MessageRole.assistant,
            content: '请确认执行工具：创建提醒',
            payloadJson: const {
              'toolName': 'create_reminder',
              'arguments': {'title': '给测试同学'},
              'status': 'awaitingConfirmation',
              'summary': '请确认执行工具：创建提醒',
              'requiresConfirmation': true,
            },
          ),
        ],
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        harness: orchestrator,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');
      final confirmationMessage = ChatMessage(
        text: '请确认执行工具：写入文件',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.actionConfirmation,
        payloadJson: const {
          'toolName': 'Write',
          'arguments': {
            'file_path': 'notes/db-version.md',
            'content': '数据库版本：7',
          },
          'status': 'awaitingConfirmation',
          'summary': '请确认执行工具：写入文件',
          'requiresConfirmation': true,
          'agentTurnId': 12,
        },
      );
      final confirmationMessageId =
          await databaseHelper.insertMessage(confirmationMessage, groupId);
      confirmationMessage.id = confirmationMessageId;
      container
          .read(messagesProvider.notifier)
          .setMessages([confirmationMessage]);

      await container
          .read(chatControllerProvider)
          .confirmToolInvocation(confirmationMessage, trustTool: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final messages = container.read(messagesProvider);
      final replacedMessage = messages.firstWhere(
        (message) => message.id == confirmationMessageId,
      );
      expect(replacedMessage.text, '正在执行工具：写入文件');
      expect(replacedMessage.contentType, MessageContentType.toolInvocation);
      expect(replacedMessage.payloadJson?['status'], 'running');
      expect(replacedMessage.payloadJson?['requiresConfirmation'], isFalse);

      final followupConfirmation = messages.firstWhere(
        (message) =>
            message.id != confirmationMessageId &&
            message.contentType == MessageContentType.actionConfirmation,
      );
      expect(followupConfirmation.text, '请确认执行工具：创建提醒');
      expect(followupConfirmation.payloadJson?['toolName'], 'create_reminder');
      expect(
          followupConfirmation.payloadJson?['status'], 'awaitingConfirmation');

      expect(container.read(sendPhaseProvider),
          ChatSendPhase.awaitingConfirmation);
    });

    test('agent loop delta 只会追加一次，避免流式文本重复', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final orchestrator = _FakeTurnHarness(
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
        harness: orchestrator,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
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
      container
          .read(messagesProvider.notifier)
          .setMessages([confirmationMessage]);

      await container
          .read(chatControllerProvider)
          .confirmToolInvocation(confirmationMessage, trustTool: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final assistantMessage = container.read(messagesProvider).firstWhere(
          (message) =>
              message.isAssistant && message.id != confirmationMessageId);
      expect(assistantMessage.text, '我先搜索，再总结');
    });

    test('agent loop delta 会延迟持久化到最终 flush，而不是每个 delta 立即写库', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final orchestrator = _DelayedResumeTurnHarness(
        databaseHelper: databaseHelper,
        resumedEvents: [
          ChatEvent(
            turnId: 12,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.assistantTextDelta,
            role: MessageRole.assistant,
            content: '我先搜索',
          ),
          ChatEvent(
            turnId: 12,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.assistantTextDelta,
            role: MessageRole.assistant,
            content: '，再总结',
          ),
          ChatEvent(
            turnId: 12,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '我先搜索，再总结',
          ),
        ],
        resumedEventDelays: const [
          Duration.zero,
          Duration.zero,
          Duration(milliseconds: 120),
        ],
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        harness: orchestrator,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
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
          'agentTurnId': 12,
        },
      );
      final confirmationMessageId =
          await databaseHelper.insertMessage(confirmationMessage, groupId);
      confirmationMessage.id = confirmationMessageId;
      container
          .read(messagesProvider.notifier)
          .setMessages([confirmationMessage]);

      final future = container
          .read(chatControllerProvider)
          .confirmToolInvocation(confirmationMessage, trustTool: true);

      await Future<void>.delayed(const Duration(milliseconds: 10));

      final earlyPersistedMessages =
          await databaseHelper.getMessagesByGroup(groupId);
      final earlyAssistantMessage = earlyPersistedMessages.firstWhere(
        (message) => message.id != confirmationMessageId && message.isAssistant,
      );
      expect(earlyAssistantMessage.text, isEmpty);

      await future;

      final persistedMessages =
          await databaseHelper.getMessagesByGroup(groupId);
      final finalAssistantMessage = persistedMessages.firstWhere(
        (message) => message.id != confirmationMessageId && message.isAssistant,
      );
      expect(finalAssistantMessage.text, '我先搜索，再总结');
      expect(finalAssistantMessage.status, MessageStatus.completed);
    });

    test('取消工具会记录取消 trace 并复位发送阶段', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final traceLogs = <Map<String, dynamic>>[];
      final traceRecorder = ChatTraceRecorder(
        logger: (entry) => traceLogs.add(entry),
      );
      final orchestrator = _FakeTurnHarness(
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
        harness: orchestrator,
        traceRecorder: traceRecorder,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      await container.read(chatControllerProvider).sendMessage('提醒我交周报');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final confirmationMessage = container.read(messagesProvider).firstWhere(
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

      final initialTurnId = traceLogs.firstWhere((entry) =>
          entry['stage'] == ChatTraceStage.sendStart.name)['turnId'] as String;
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
      final orchestrator = _FakeTurnHarness(
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
        harness: orchestrator,
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
          container.read(chatSendStateProvider).phase, ChatSendPhase.preparing);
      expect(container.read(chatSendStateProvider).isGenerating, isFalse);
      expect(
        container.read(messagesProvider).any(
              (message) => message.isUser && message.text == '立即显示这条消息',
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
      final orchestrator = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: const [],
        runTurnError: Exception('请先在设置页配置 API Key'),
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        harness: orchestrator,
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

    test('agent loop 达到迭代上限时会显示明确收口提示并复位发送状态', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final orchestrator = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.turnStatus,
            role: MessageRole.system,
            content: 'max_iterations_reached',
          ),
        ],
        runTurnFailureCode: 'max_iterations_reached',
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        harness: orchestrator,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      await container.read(chatControllerProvider).sendMessage('帮我继续检索');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(container.read(sendPhaseProvider), ChatSendPhase.idle);
      expect(container.read(chatSendStateProvider).phase, ChatSendPhase.idle);
      expect(container.read(chatSendStateProvider).isGenerating, isFalse);

      final failureMessage = container
          .read(messagesProvider)
          .lastWhere((message) => message.role == MessageRole.assistant);
      expect(failureMessage.status, MessageStatus.failed);
      expect(
        failureMessage.text,
        '本轮已达到工具探索上限，已停止继续执行。当前收集到了一些中间结果，但模型还没来得及整理出最终答复。你可以让我基于现有结果继续总结，或缩小问题范围后再试一次。',
      );

      await databaseHelper.deleteGroup(groupId);
    });

    test(
        'submitQuestionAnswers replaces ask-prompt message with askUserQuestionResult',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final orchestrator = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: const [],
        resumedQuestionEvents: [
          ChatEvent(
            turnId: 42,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.userInteractionResult,
            role: MessageRole.user,
            content: '已选择：移动端（iOS/Android）',
          ),
          ChatEvent(
            turnId: 42,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '收到，继续推进移动端方案。',
          ),
        ],
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        harness: orchestrator,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      const promptPayload = {
        'questions': [
          {
            'id': 'primary-platform',
            'header': 'Platform',
            'question': '目标平台是什么？',
            'multiSelect': false,
            'options': [
              {
                'label': '移动端（iOS/Android）',
                'description': '手机端优先',
              },
            ],
          },
        ],
        'agentTurnId': 42,
      };
      final promptId = await databaseHelper.insertMessage(
        ChatMessage(
          text: '请先回答几个问题',
          role: MessageRole.assistant,
          status: MessageStatus.completed,
          contentType: MessageContentType.askUserQuestionPrompt,
          payloadJson: promptPayload,
        ),
        groupId,
      );
      final promptMessage = ChatMessage(
        id: promptId,
        text: '请先回答几个问题',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.askUserQuestionPrompt,
        payloadJson: promptPayload,
      );
      container.read(messagesProvider.notifier).addMessage(promptMessage);

      await container.read(chatSendCoordinatorProvider).submitQuestionAnswers(
            promptMessage,
            response: const AskUserQuestionResponse(
              answersByQuestionId: {
                'primary-platform': '移动端（iOS/Android）',
              },
              selectedOptionLabelsByQuestionId: {
                'primary-platform': ['移动端（iOS/Android）'],
              },
              freeTextAnswersByQuestionId: {},
            ),
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final messages = container.read(messagesProvider);
      final replaced = messages.firstWhere((m) => m.id == promptId);
      expect(replaced.contentType, MessageContentType.askUserQuestionResult);
      expect(replaced.text, '已选择：移动端（iOS/Android）');
      expect(replaced.payloadJson?['status'], 'submitted');
      expect(replaced.payloadJson?['submittedAnswers'], isA<Map>());

      // No extra askUserQuestionResult message added
      final resultMessages = messages.where(
        (m) => m.contentType == MessageContentType.askUserQuestionResult,
      );
      expect(resultMessages.length, 1);

      // Final assistant answer still appended
      expect(
        messages.any(
          (m) =>
              m.isAssistant &&
              m.status == MessageStatus.completed &&
              m.text == '收到，继续推进移动端方案。',
        ),
        isTrue,
      );

      await databaseHelper.deleteGroup(groupId);
    });

    test(
        'submitQuestionAnswers keeps resumed loop cancellable and visible while waiting',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final resumeQuestionGate = Completer<void>();
      final orchestrator = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: const [],
        resumedQuestionEvents: const [],
        resumeQuestionGate: resumeQuestionGate,
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        harness: orchestrator,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      const promptPayload = {
        'questions': [
          {
            'id': 'primary-platform',
            'header': 'Platform',
            'question': '目标平台是什么？',
            'multiSelect': false,
            'options': [
              {
                'label': '移动端（iOS/Android）',
                'description': '手机端优先',
              },
            ],
          },
        ],
        'agentTurnId': 42,
      };
      final promptMessage = ChatMessage(
        id: await databaseHelper.insertMessage(
          ChatMessage(
            text: '请先回答几个问题',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            contentType: MessageContentType.askUserQuestionPrompt,
            payloadJson: promptPayload,
          ),
          groupId,
        ),
        text: '请先回答几个问题',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.askUserQuestionPrompt,
        payloadJson: promptPayload,
      );
      container.read(messagesProvider.notifier).addMessage(promptMessage);

      final future =
          container.read(chatSendCoordinatorProvider).submitQuestionAnswers(
                promptMessage,
                response: const AskUserQuestionResponse(
                  answersByQuestionId: {
                    'primary-platform': '移动端（iOS/Android）',
                  },
                  selectedOptionLabelsByQuestionId: {
                    'primary-platform': ['移动端（iOS/Android）'],
                  },
                  freeTextAnswersByQuestionId: {},
                ),
              );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(sendPhaseProvider), isNot(ChatSendPhase.idle));
      expect(container.read(streamSubscriptionProvider), isNotNull);

      resumeQuestionGate.complete();
      await future;
    });

    test('sendMessage records controller trace boundary events in order',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final traceLogs = <Map<String, dynamic>>[];
      final traceRecorder = ChatTraceRecorder(
        logger: (entry) => traceLogs.add(entry),
      );
      final orchestrator = _FakeTurnHarness(
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
        harness: orchestrator,
        traceRecorder: traceRecorder,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      await container.read(chatControllerProvider).sendMessage('测试发送 trace');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final traceTurnIds =
          traceLogs.map((entry) => entry['turnId']).whereType<String>().toSet();
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

    test(
        'chat controller delegates confirm and cancel tool actions to coordinator',
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
      await container
          .read(chatControllerProvider)
          .cancelToolInvocation(message);

      expect(coordinator.confirmedMessages, [message]);
      expect(coordinator.confirmedTrustFlags, [true]);
      expect(coordinator.cancelledMessages, [message]);
      expect(sessionCoordinator.loadGroupsCalls, 0);
    });

    test('stale confirmation message does not resume tool execution again',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final orchestrator = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: const [],
        resumedEvents: const [],
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        harness: orchestrator,
      );
      addTearDown(container.dispose);

      final groupId =
          await databaseHelper.insertGroup(ChatGroup(title: 'group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'group');

      final staleMessage = ChatMessage(
        id: 42,
        text: '准备执行工具：编辑文件',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.actionConfirmation,
        payloadJson: const {
          'toolName': 'Edit',
          'arguments': {
            'file_path': '我的爱好.md',
            'old_string': '---',
            'new_string': '---\n\n## 二、看电影',
          },
          'status': 'awaitingConfirmation',
          'summary': '准备执行工具：编辑文件',
          'requiresConfirmation': true,
          'agentTurnId': 9,
        },
      );
      container.read(messagesProvider.notifier).setMessages([
        staleMessage.copyWith(
          text: '正在执行工具：编辑文件',
          contentType: MessageContentType.toolInvocation,
          payloadJson: const {
            'toolName': 'Edit',
            'arguments': {
              'file_path': '我的爱好.md',
              'old_string': '---',
              'new_string': '---\n\n## 二、看电影',
            },
            'status': 'running',
            'summary': '正在执行工具：编辑文件',
            'requiresConfirmation': false,
            'agentTurnId': 9,
          },
        ),
      ]);

      await container.read(chatControllerProvider).confirmToolInvocation(
            staleMessage,
            trustTool: true,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(orchestrator.resumedTurnIds, isEmpty);
      expect(orchestrator.resumedTrustFlags, isEmpty);
    });

    test(
        'chat controller delegates session lifecycle actions to session coordinator',
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

      final summary = await container
          .read(chatControllerProvider)
          .summarizeAndUpdateTitle();
      container.read(chatControllerProvider).cancelAutoSummaryTimer();

      expect(summary, 'fake-summary');
      expect(summaryController.summarizeCalls, 1);
      expect(summaryController.cancelTimerCalls, 1);
    });

    test(
        'chat controller delegates preferences lifecycle to preferences controller',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final preferencesController = _FakeChatPreferencesController();
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        preferencesController: preferencesController,
      );
      addTearDown(container.dispose);

      await container
          .read(chatControllerProvider)
          .setSystemPrompt('new prompt');

      expect(preferencesController.systemPrompts, ['new prompt']);
    });

    test('sendMessage stores runtime current date in turn provider state',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final orchestrator = _FakeTurnHarness(
        databaseHelper: databaseHelper,
        events: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.finalAnswer,
            role: MessageRole.assistant,
            content: '这是今天的摘要。',
          ),
        ],
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        chatService: _FakeChatService(),
        harness: orchestrator,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper.insertGroup(
        ChatGroup(title: 'Date Aware Send Flow'),
      );
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'Date Aware Send Flow');

      await container.read(chatControllerProvider).sendMessage('今天有什么新消息？');

      final recordedTurn = orchestrator.recordedTurns.single;
      final runtimeContext =
          recordedTurn.providerStateJson?['runtime_context'] as Map?;
      expect(runtimeContext, isNotNull);
      expect(runtimeContext?['current_date'], isA<String>());
      expect(runtimeContext?.containsKey('date_change_reminder'), isFalse);

      await databaseHelper.deleteGroup(groupId);
    });

    test('需要确认的工具会让发送事务停留在 awaitingConfirmation', () async {
      final databaseHelper = _createTestDatabaseHelper();
      final orchestrator = _FakeTurnHarness(
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
        harness: orchestrator,
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
  TurnHarness? harness,
  ChatSessionCoordinator? sessionCoordinator,
  ChatSummaryController? summaryController,
  ChatPreferencesController? preferencesController,
}) {
  return ProviderContainer(
    overrides: [
      databaseProvider.overrideWith((ref) => databaseHelper),
      chatServiceProvider.overrideWith((ref) => chatService),
      if (coordinator != null)
        chatSendCoordinatorProvider.overrideWith((ref) => coordinator),
      if (harness != null) turnHarnessProvider.overrideWith((ref) => harness),
      if (sessionCoordinator != null)
        chatSessionCoordinatorProvider
            .overrideWith((ref) => sessionCoordinator),
      if (summaryController != null)
        chatSummaryControllerProvider.overrideWith((ref) => summaryController),
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
  }) : super(llm: _NoopBaseLLM());

  @override
  Future<ToolPreparationResult> executeToolInvocation({
    required int groupId,
    required ToolInvocation invocation,
    bool trustTool = false,
    String? turnId,
    ToolExecutionStartedCallback? onExecutionStarted,
  }) async {
    confirmedTrustFlags.add(trustTool);
    confirmedTurnIds.add(turnId);
    return confirmedToolResult ?? const ToolPreparationResult.noTool();
  }
}

class _FakeTurnHarness extends TurnHarness {
  final DatabaseHelper databaseHelper;
  final List<ChatEvent> events;
  final List<ChatEvent> resumedEvents;
  final List<ChatEvent> resumedQuestionEvents;
  final List<ChatTurn> recordedTurns = [];
  final List<int> resumedTurnIds = [];
  final List<int> resumedQuestionTurnIds = [];
  final List<bool> resumedTrustFlags = [];
  final Completer<void>? runTurnGate;
  final Completer<void>? resumeQuestionGate;
  final Object? runTurnError;
  final String? runTurnFailureCode;

  _FakeTurnHarness({
    required this.databaseHelper,
    required this.events,
    this.resumedEvents = const [],
    this.resumedQuestionEvents = const [],
    this.runTurnGate,
    this.resumeQuestionGate,
    this.runTurnError,
    this.runTurnFailureCode,
  }) : super(
          plannerService: AgentPlannerService(llm: _NoopBaseLLM()),
          turnRepository: ChatTurnRepository(databaseHelper),
          eventRepository: ChatEventRepository(databaseHelper),
          transcriptBuilderService: TranscriptBuilderService(
            eventRepository: ChatEventRepository(databaseHelper),
          ),
          turnVerifier: TurnVerifier(),
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
    final failureCode = runTurnFailureCode;
    if (failureCode != null && turn.id != null) {
      await ChatTurnRepository(databaseHelper).markFailed(
        turn.id!,
        errorMessage: failureCode,
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

  @override
  Stream<ChatEvent> resumeAfterQuestionAnswered({
    required int turnId,
    required AskUserQuestionRequest request,
    required AskUserQuestionResponse response,
    required ChatConfig config,
  }) async* {
    resumedQuestionTurnIds.add(turnId);
    final gate = resumeQuestionGate;
    if (gate != null) {
      await gate.future;
    }
    for (final event in resumedQuestionEvents) {
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

class _DelayedResumeTurnHarness extends _FakeTurnHarness {
  final List<Duration> resumedEventDelays;

  _DelayedResumeTurnHarness({
    required super.databaseHelper,
    required super.resumedEvents,
    required this.resumedEventDelays,
  })  : assert(resumedEvents.length == resumedEventDelays.length),
        super(
          events: const [],
        );

  @override
  Stream<ChatEvent> resumeAfterConfirmation({
    required int turnId,
    required ToolInvocation invocation,
    required ChatConfig config,
    bool trustTool = false,
  }) async* {
    resumedTurnIds.add(turnId);
    resumedTrustFlags.add(trustTool);

    for (var index = 0; index < resumedEvents.length; index += 1) {
      final delay = resumedEventDelays[index];
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      final event = resumedEvents[index];
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
  Future<ModelTurnDecision?> planTurnDecision({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    void Function(LlmRetryProgress progress)? onRetryScheduled,
  }) async =>
      null;

  @override
  String getModelName(ChatConfig config) => 'noop';

  @override
  Future<String> processWebpageContent({
    required String webpageContent,
    required String prompt,
  }) async =>
      '';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async => '';

}

class _FakeChatSendCoordinator implements ChatSendCoordinator {
  final List<String> sentMessages = [];
  final List<ChatMessage> confirmedMessages = [];
  final List<bool> confirmedTrustFlags = [];
  final List<ChatMessage> cancelledMessages = [];
  final List<ChatMessage> submittedQuestionMessages = [];

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

  @override
  Future<void> submitQuestionAnswers(
    ChatMessage message, {
    required AskUserQuestionResponse response,
  }) async {
    submittedQuestionMessages.add(message);
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

class _FakeChatPreferencesController implements ChatPreferencesController {
  final List<String?> systemPrompts = [];

  @override
  Future<void> setSystemPrompt(String? prompt) async {
    systemPrompts.add(prompt);
  }
}
